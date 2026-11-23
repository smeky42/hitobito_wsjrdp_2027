# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# One money movement of an own account, whatever recorded it: a bank
# transaction (camt) or a Moss transaction. The rows of the all-transactions page
# (Fin::AccountTransactionsController).
#
# There is no table: .all is a UNION ALL of both tables as a subquery, so
# filter, sort, sum and paging run in the database. The subquery borrows the
# name of wsjrdp_camt_transactions, as DatevBooking.legs does with its own, so
# Active Record has a schema to load rows with; a database view would not
# survive db:schema:load. Read-only.
class Fin::AccountTransaction < ActiveRecord::Base
  self.table_name = "wsjrdp_camt_transactions"
  self.inheritance_column = nil

  # The account's tab label (Fin::OverviewHelper#fin_account_label), so the
  # account column shows and sorts by it.
  ACCOUNT_NAME_SQL = Fin::CamtParty::ACCOUNT_NAME_SQL

  CAMT_SELECT = <<~SQL.squish
    SELECT 'camt' AS source, 'camt-' || c.id AS row_key, c.id, c.fin_account_id, #{ACCOUNT_NAME_SQL} AS account_name,
      #{Fin::AccountKinds.camt_sql("c")} AS kind, c.booking_date, c.value_date, c.signed_base_amount, c.description, c.comment,
      #{Fin::CamtParty.select_sql("c")}, #{Fin::TransactionPersons.camt_sql("c")} AS persons
    FROM wsjrdp_camt_transactions c LEFT JOIN wsjrdp_fin_accounts a ON a.id = c.fin_account_id
  SQL

  # The party of a Moss row: the other account of an internal transfer, else
  # the merchant of a card payment, the sender of a top-up, the recipient
  # otherwise.
  MOSS_TRANSFER_SQL = Fin::CamtParty.transfer_account_sql("t.internal_transfer_id", "t.signed_total_base_amount")
  MOSS_NAME_SQL = "CASE t.type WHEN 'MossCardTransaction' THEN t.merchant_name WHEN 'MossTopUp' THEN t.top_up_sender " \
    "ELSE COALESCE(NULLIF(t.recipient_name, ''), t.payout_user_name) END"

  MOSS_SELECT = <<~SQL.squish
    SELECT 'moss' AS source, 'moss-' || t.id AS row_key, t.id, t.fin_account_id, #{ACCOUNT_NAME_SQL} AS account_name,
      #{Fin::AccountKinds.moss_sql("t")} AS kind, t.booking_date, NULL::date AS value_date,
      t.signed_total_base_amount AS signed_base_amount,
      concat_ws(' – ', NULLIF(t.transaction_name, ''), NULLIF(t.transaction_posting_text, '')) AS description,
      t.comment,
      COALESCE(#{MOSS_TRANSFER_SQL}, #{MOSS_NAME_SQL}) AS party,
      CASE WHEN #{MOSS_TRANSFER_SQL} IS NOT NULL THEN 'account' ELSE 'name' END AS party_kind,
      NULL::varchar AS party_iban, #{Fin::TransactionPersons.moss_sql("t")} AS persons
    FROM moss_transactions t LEFT JOIN wsjrdp_fin_accounts a ON a.id = t.fin_account_id
  SQL

  # Inside a scope (a relation's own class methods, Kaminari's #page) .all is
  # that scope, which already reads from the union.
  def self.all
    scope = super
    return scope unless scope.from_clause.empty?

    scope.from(Arel.sql("(#{CAMT_SELECT} UNION ALL #{MOSS_SELECT}) AS wsjrdp_camt_transactions"))
  end

  def readonly? = true

  def camt? = source == "camt"
end
