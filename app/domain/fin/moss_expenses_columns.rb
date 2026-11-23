# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# THE columns of the expenses table on a Moss transaction's page
# (fin/moss_transactions/_detail), described once (doc/wsjrdp/expandable_table.md).
module Fin::MossExpensesColumns
  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "mecol") do |c|
    c.column key: "expense_number", abbr: "nr", label: "Nr.", numeric: true, width: "3rem",
      sort: "moss_expenses.expense_number", default: true
    c.column key: "expense_name", abbr: "nm", label: "Bezeichnung", width: "10rem", grow: 1,
      sort: "moss_expenses.expense_name", default: true
    c.column key: "purchased_on", abbr: "pd", label: "Kaufdatum", width: "7rem",
      sort: "moss_expenses.purchased_on", default: true
    c.column key: "expense_posting_text", abbr: "txt", label: "Buchungstext", width: "10rem", grow: 1,
      default: true
    c.column key: "bookings_count", abbr: "nb", label: "Bu.", numeric: true, width: "3rem", default: true
    c.column key: "signed_expense_base_amount", abbr: "amt", label: "Betrag", numeric: true,
      sort_first: "desc", width: "6.5rem", sort: "moss_expenses.signed_expense_base_amount", default: true
    c.column key: "moss_expense_type", abbr: "typ", label: "Ausgabenart", width: "8rem",
      sort: "moss_expenses.moss_expense_type"
  end

  def self.codec = COLUMNS.codec

  def self.default_keys = COLUMNS.default_keys

  def self.sort_expressions = COLUMNS.sort_expressions
end
