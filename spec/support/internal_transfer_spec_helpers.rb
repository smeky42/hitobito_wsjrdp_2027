# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Builders for the Umbuchung specs: own accounts and the rows on them. All
# IBANs are valid test IBANs, all names and amounts invented.
module InternalTransferSpecHelpers
  GIRO_IBAN = "DE02120300000000202051"
  SAVINGS_IBAN = "DE02500105170137075030"
  NOTICE_IBAN = "DE89370400440532013000"
  WALLET_TOP_UP_IBAN = "DE16100100101111111111"

  def it_account(name, iban: nil, top_up_iban: nil, wallet: false)
    WsjrdpFinAccount.create!(short_name: name, account_identification: iban || "ACC-#{SecureRandom.hex(4)}",
      iban: iban, top_up_iban: top_up_iban, opening_balance_cents: 0, opening_balance_currency: "EUR",
      opening_balance_date: Date.new(2026, 1, 1),
      transaction_type: wallet ? "MossBalanceMovement" : "WsjrdpCamtTransaction")
  end

  def it_camt(account, amount, date, dbtr_iban: nil, cdtr_iban: nil, **attrs)
    WsjrdpCamtTransaction.create!(fin_account: account, camt_type: "CAMT053",
      account_identification: account.account_identification, account_servicer_reference: SecureRandom.hex(8),
      credit_debit_indication: amount.negative? ? "DBIT" : "CRDT", signed_base_amount: amount,
      base_currency: "EUR", value_date: date, description: "Buchung #{amount}",
      dbtr_iban: dbtr_iban, cdtr_iban: cdtr_iban, **attrs)
  end

  def it_top_up(wallet, amount, date)
    MossTopUp.create!(moss_transaction_uuid: SecureRandom.uuid, fin_account: wallet, signed_total_base_amount: amount,
      signed_total_transaction_amount: amount, currency: "EUR", booking_date: date, top_up_sender: "Verband")
  end
end

RSpec.configure { |config| config.include InternalTransferSpecHelpers }
