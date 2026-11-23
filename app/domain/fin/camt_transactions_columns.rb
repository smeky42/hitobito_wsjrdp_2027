# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The columns of a bank account's statement (fin/wsjrdp_fin_accounts/_camt_statement):
# one row per camt transaction (doc/wsjrdp/expandable_table.md).
module Fin::CamtTransactionsColumns
  T = "wsjrdp_camt_transactions"

  # The other side (Fin::CamtParty), the kind (Fin::AccountKinds), the linked
  # persons (Fin::TransactionPersons) and the processing status of a return,
  # in SQL; the rows select them (SELECT_SQL) as `party`, `party_kind`,
  # `party_iban`, `account_kind`, `persons` and `return_state`.
  PARTY_SQL = Fin::CamtParty.party_sql(T)
  KIND_SQL = Fin::AccountKinds.camt_sql(T)
  PERSONS_SQL = Fin::TransactionPersons.camt_sql(T)
  RETURN_STATE_SQL = "CASE WHEN #{T}.return_reason IS NOT NULL THEN #{Fin::PaymentReturnsColumns::STATUS_SQL} END"
  SELECT_SQL = "#{T}.*, #{Fin::CamtParty.select_sql(T)}, #{KIND_SQL} AS account_kind, " \
    "#{PERSONS_SQL} AS persons, #{RETURN_STATE_SQL} AS return_state"

  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "ctcol") do |c|
    # The booking day is the date; on a phone the description shows it. The
    # value date is hidden by default, the description shows it where it
    # differs.
    c.column key: "booking_date", abbr: "bd", label: "Buchungstag", short_label: "Buchung", width: "7rem",
      target_width: "8.5rem", sort: "#{T}.booking_date", default: true, mobile: false
    c.column key: "value_date", abbr: "vd", label: "Valuta", width: "6.5rem", sort: "#{T}.value_date"
    # Kind and party are hidden by default: the description shows them.
    c.column key: "kind", abbr: "k", label: "Art", width: "7rem", sort: KIND_SQL
    c.column key: "party", abbr: "pty", label: "Gegenseite", width: "10rem", sort: PARTY_SQL
    # The description and the comment, the linked persons and the buttons that
    # link one.
    c.column key: "description", abbr: "dsc", label: "Beschreibung", width: "12rem", grow: 1, default: true
    c.column key: "persons", abbr: "per", label: "Person", width: "10rem", sort: PERSONS_SQL
    c.column key: "comment", abbr: "cmt", label: "Kommentar", width: "10rem", sort: "LOWER(#{T}.comment)"
    c.column key: "endtoend_id", abbr: "e2e", label: "Kundenreferenz", width: "10rem", sort: "#{T}.endtoend_id"
    c.column key: "mandate_id", abbr: "mdt", label: "Mandatsreferenz", width: "10rem", sort: "#{T}.mandate_id"
    c.column key: "bank_transaction_code", abbr: "btc", label: "ISO-Buchungscode", width: "9rem",
      sort: "#{T}.bank_transaction_code"
    c.column key: "bank_transaction_code_dk", abbr: "dk", label: "DK-Buchungscode", width: "8rem",
      sort: "#{T}.bank_transaction_code_dk"
    c.column key: "status", abbr: "st", label: "Status", width: "5rem", sort: "#{T}.status"
    c.column key: "return_reason", abbr: "rr", label: "Rückgabe-Grund", width: "10rem", sort: "#{T}.return_reason"
    c.column key: "return_state", abbr: "rs", label: "Retoure-Status", width: "9rem", sort: RETURN_STATE_SQL
    # Last, next to the page link.
    c.column key: "signed_base_amount", abbr: "amt", label: "Betrag", numeric: true, sort_first: "desc",
      width: "7rem", sort: "#{T}.signed_base_amount", default: true
  end

  # What the cells read per row.
  ROW_PRELOADS = [:subject, {accounting_entries: :subject}].freeze

  def self.codec = COLUMNS.codec

  def self.default_keys = COLUMNS.default_keys

  def self.sort_expressions = COLUMNS.sort_expressions
end
