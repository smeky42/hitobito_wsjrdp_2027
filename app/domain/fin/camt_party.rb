# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The other side of a bank transaction, as SQL, so a table shows and sorts it
# alike. The first rule that gives a value wins:
#
# 1. A leg of an internal transfer: the account(s) on the transfer's other side.
# 2. The other side's IBAN is an own account's: that account.
# 3. The other side's name. Which side that is follows from the bank
#    transaction code's family, which keeps the payment's roles on a return;
#    without a known family, from the sign.
# 4. A label: a batch transfer or direct debit names no single party, and the
#    bank's own entries (closing, fees) none at all.
#
# `kind_sql` says which rule gave it: "account", "name" or "label". Shown by
# Fin::CamtTransactionsHelper (#fin_party_cell, and the details' formatter).
module Fin::CamtParty
  # The families where we pay (the creditor is the other side) and where we
  # are paid (the debtor is).
  CREDITOR_FAMILIES = %w[ICDT IRCT RDDT].freeze
  DEBTOR_FAMILIES = %w[RCDT RRCT IDDT].freeze

  # The account name the account tabs show.
  ACCOUNT_NAME_SQL = "COALESCE(NULLIF(a.short_name, ''), a.account_identification)"

  module_function

  # `t`: the name or alias of the camt transactions table in the query.
  def party_sql(t) = "COALESCE(#{account_sql(t)}, #{name_sql(t)}, #{label_sql(t)})"

  # The columns `party`, `party_kind` and `party_iban` (the other side's IBAN
  # as the statement gives it).
  def select_sql(t) = "#{party_sql(t)} AS party, #{kind_sql(t)} AS party_kind, #{side_sql(t, "iban")} AS party_iban"

  def kind_sql(t)
    "CASE WHEN #{account_sql(t)} IS NOT NULL THEN 'account' WHEN #{name_sql(t)} IS NOT NULL THEN 'name' " \
      "WHEN #{label_sql(t)} IS NOT NULL THEN 'label' END"
  end

  # Rules 1 and 2: the own account on the other side.
  def account_sql(t)
    "COALESCE(#{transfer_account_sql("#{t}.internal_transfer_id", "#{t}.signed_base_amount")}, #{iban_account_sql(t)})"
  end

  # The names of the accounts holding the legs on the other side of a
  # transfer; NULL for a row that is no leg. Also used for Moss rows.
  def transfer_account_sql(transfer_id, amount)
    <<~SQL.squish
      (SELECT string_agg(DISTINCT #{ACCOUNT_NAME_SQL}, ', ') FROM (
        SELECT o.fin_account_id FROM wsjrdp_camt_transactions o
        WHERE o.internal_transfer_id = #{transfer_id} AND o.deleted_at IS NULL AND o.replaced_by_id IS NULL
          AND sign(o.signed_base_amount) = -sign(#{amount})
        UNION ALL
        SELECT m.fin_account_id FROM moss_transactions m
        WHERE m.internal_transfer_id = #{transfer_id} AND sign(m.signed_total_base_amount) = -sign(#{amount})
      ) legs JOIN wsjrdp_fin_accounts a ON a.id = legs.fin_account_id)
    SQL
  end

  def iban_account_sql(t)
    <<~SQL.squish
      (SELECT string_agg(#{ACCOUNT_NAME_SQL}, ', ') FROM wsjrdp_fin_accounts a
       WHERE a.deleted_at IS NULL AND a.id <> #{t}.fin_account_id
         AND #{side_sql(t, "iban")} IN (a.iban, a.top_up_iban))
    SQL
  end

  def name_sql(t) = side_sql(t, "name")

  def label_sql(t)
    "CASE WHEN #{t}.bank_transaction_family = 'ICDT' THEN 'Sammelüberweisung' " \
      "WHEN #{t}.bank_transaction_family = 'IDDT' THEN 'Sammellastschrift' " \
      "WHEN #{t}.bank_transaction_domain = 'ACMT' THEN 'Bank' END"
  end

  # The other side's `name` or `iban` column, blank as NULL.
  def side_sql(t, field)
    "NULLIF(CASE WHEN #{creditor_sql(t)} THEN #{t}.cdtr_#{field} ELSE #{t}.dbtr_#{field} END, '')"
  end

  def creditor_sql(t)
    "CASE WHEN #{t}.bank_transaction_family IN (#{quoted(CREDITOR_FAMILIES)}) THEN TRUE " \
      "WHEN #{t}.bank_transaction_family IN (#{quoted(DEBTOR_FAMILIES)}) THEN FALSE " \
      "ELSE #{t}.signed_base_amount < 0 END"
  end

  def quoted(values) = values.map { |v| "'#{v}'" }.join(", ")
end
