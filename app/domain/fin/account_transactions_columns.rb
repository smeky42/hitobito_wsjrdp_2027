# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The columns of the all-transactions page: every account's transactions,
# Fin::AccountTransaction (doc/wsjrdp/expandable_table.md).
module Fin::AccountTransactionsColumns
  TABLE = "wsjrdp_camt_transactions"

  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "atcol") do |c|
    # The one date every row has; on a phone the description shows it.
    # Like the Moss list's: wider where the table has room, "Buchung" in the
    # header while it is too narrow for the full word.
    c.column key: "booking_date", abbr: "d", label: "Buchungstag", short_label: "Buchung", width: "7rem",
      target_width: "8.5rem", sort: "#{TABLE}.booking_date", default: true, mobile: false
    # A bank row's own (Moss has none to match); never a column of the table
    # (cols: never:), the description shows it where it differs.
    c.column key: "value_date", abbr: "vd", label: "Valuta", width: "6.5rem", sort: "#{TABLE}.value_date"
    # Account, kind and party are hidden by default: the description shows them.
    c.column key: "account", abbr: "acc", label: "Konto", width: "9rem", sort: "#{TABLE}.account_name"
    c.column key: "kind", abbr: "k", label: "Art", width: "7rem", sort: "#{TABLE}.kind"
    c.column key: "party", abbr: "pty", label: "Gegenseite", width: "10rem", sort: "#{TABLE}.party"
    c.column key: "description", abbr: "dsc", label: "Beschreibung", width: "12rem", grow: 1, default: true
    c.column key: "persons", abbr: "per", label: "Person", width: "10rem", sort: "#{TABLE}.persons"
    c.column key: "comment", abbr: "cmt", label: "Kommentar", width: "10rem", sort: "LOWER(#{TABLE}.comment)"
    # Last, next to the page link.
    c.column key: "signed_base_amount", abbr: "amt", label: "Betrag", numeric: true, sort_first: "desc",
      width: "7rem", sort: "#{TABLE}.signed_base_amount", default: true
  end

  def self.codec = COLUMNS.codec

  def self.default_keys = COLUMNS.default_keys

  def self.sort_expressions = COLUMNS.sort_expressions
end
