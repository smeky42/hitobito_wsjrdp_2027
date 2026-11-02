# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The parts of a bank transaction's codes as columns of their own, generated
# from the stored strings, so lists and filters can query them:
#
# - bank_transaction_code is the ISO 20022 Bank Transaction Code
#   "<Domain>+<Family>+<SubFamily>" (BkTxCd/Domn, ISO external code list
#   "Bank Transaction Codes");
# - bank_transaction_code_dk is the code of the German banks
#   "<SWIFT code>+<GVC>[+<Primanota>[+<Textschlüsselergänzung>]]"
#   (BkTxCd/Prtry with Issr DK, DFÜ-Abkommen Anlage 3, chapter 7.1.8.5.2);
#   its GVC (Geschäftsvorfallcode) maps to the ISO code by Anhang 1 of Anlage 3.
#
# return_kind sorts the transactions that bring a payment back by what came
# back, from the codes and -- for a transaction without a usable code -- its
# return reason: our direct debit (return, refund, reject or reversal), our
# credit transfer, a credit transfer we received, a direct debit we were
# charged, or anything else returned.
class AddBankTransactionCodeParts < ActiveRecord::Migration[7.1]
  ISO = "bank_transaction_code"
  DK = "bank_transaction_code_dk"

  def self.part(column, index) = "NULLIF(split_part(#{column}, '+', #{index}), '')"

  FAMILY = part(ISO, 2)
  SUB_FAMILY = part(ISO, 3)

  RETURN_KIND = <<~SQL.squish
    CASE
      WHEN #{FAMILY} = 'IDDT' AND #{SUB_FAMILY} IN ('UPDD', 'RCDD', 'PRDD') THEN 'direct_debit'
      WHEN #{FAMILY} IN ('ICDT', 'IRCT') AND #{SUB_FAMILY} IN ('RRTN', 'XRTN') THEN 'credit_transfer'
      WHEN #{FAMILY} IN ('RCDT', 'RRCT') AND #{SUB_FAMILY} IN ('RRTN', 'XRTN') THEN 'received_credit_transfer'
      WHEN #{FAMILY} = 'RDDT' AND #{SUB_FAMILY} IN ('UPDD', 'RCDD', 'PRDD') THEN 'received_direct_debit'
      WHEN #{SUB_FAMILY} IN ('UPCT', 'UPCQ', 'RRTN', 'XRTN') THEN 'other'
      WHEN return_reason IS NOT NULL AND (#{FAMILY} IS NULL OR #{FAMILY} = 'NTAV')
        THEN CASE WHEN mandate_id IS NOT NULL THEN 'direct_debit' ELSE 'other' END
      WHEN return_reason IS NOT NULL THEN 'other'
    END
  SQL

  def change
    add_column :wsjrdp_camt_transactions, :bank_transaction_domain, :virtual, type: :string, stored: true,
      as: self.class.part(ISO, 1), comment: "ISO Bank Transaction Code: Domain (e.g. PMNT), from bank_transaction_code"
    add_column :wsjrdp_camt_transactions, :bank_transaction_family, :virtual, type: :string, stored: true,
      as: FAMILY, comment: "ISO Bank Transaction Code: Family (e.g. IDDT), from bank_transaction_code"
    add_column :wsjrdp_camt_transactions, :bank_transaction_sub_family, :virtual, type: :string, stored: true,
      as: SUB_FAMILY, comment: "ISO Bank Transaction Code: SubFamily (e.g. UPDD), from bank_transaction_code"
    add_column :wsjrdp_camt_transactions, :gvc, :virtual, type: :string, stored: true,
      as: self.class.part(DK, 2), comment: "Geschäftsvorfallcode of the German banks (e.g. 109), from bank_transaction_code_dk"
    add_column :wsjrdp_camt_transactions, :return_kind, :virtual, type: :string, stored: true,
      as: RETURN_KIND,
      comment: "What came back: direct_debit, credit_transfer, received_credit_transfer, " \
               "received_direct_debit, other; NULL for no return"

    add_index :wsjrdp_camt_transactions, [:bank_transaction_family, :bank_transaction_sub_family],
      name: "index_wsjrdp_camt_transactions_btc_family_sub_family"
    add_index :wsjrdp_camt_transactions, :gvc
    add_index :wsjrdp_camt_transactions, :return_kind, where: "return_kind IS NOT NULL"
  end
end
