# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# THE columns of the two tables of the Controlling page "Budget"
# (Fin::BudgetsController): the cost centers by year (rows are
# Fin::BudgetOverview::Row) and the unit cost centers (rows are
# Fin::UnitBudgetOverview::Row). Both tables are array-backed, so every column
# sorts through a ->(row){ comparable } extractor. A budget cell
# (Fin::BudgetOverview::Cell) sorts by each of its three measures -- IST, budget
# and share spent --, one sort variant each (the header's chips "ist", "soll",
# "%"), largest first; a cell without a budget sorts last by budget and share
# in either direction. Every column is shown by default but 2028, which the
# column menu offers.
module Fin::BudgetColumns
  # The sort variants of a budget column whose cell `cell` picks from a row.
  def self.measures(&cell)
    [{name: "ist", label: "ist", title: "IST", sort: ->(row) { cell.call(row).actual }},
      {name: "soll", label: "soll", title: "Budget", sort: ->(row) { cell.call(row).budget }},
      {name: "pct", label: "%", title: "Ausschöpfung", sort: ->(row) { cell.call(row).percent }}]
  end

  COST_CENTERS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "budcol") do |c|
    c.column key: "number", abbr: "nr", label: "Kostenstelle", width: "14rem",
      sort: ->(row) { row.number }, default: true
    Fin::BudgetOverview::YEARS.each do |year|
      c.column key: "year_#{year}", abbr: year.to_s[-2..], label: year.to_s, numeric: true,
        width: "8rem", sort_first: "desc", sort_variants: measures { |row| row.cells[year] },
        default: year != 2028
    end
    c.column key: "total", abbr: "ges", label: "Gesamt", numeric: true, width: "9.5rem",
      sort_first: "desc", sort_variants: measures(&:total), default: true
  end

  UNITS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "budcol") do |c|
    c.column key: "number", abbr: "nr", label: "Kostenstelle", width: "10rem",
      sort: ->(row) { row.number }, default: true
    c.column key: "expenses", abbr: "aus", label: "Gesamtausgaben", numeric: true,
      width: "9rem", sort: ->(row) { row.expenses }, sort_first: "desc", default: true
    c.column key: "unit_budget", abbr: "ub", label: "Unit-Budget", numeric: true,
      width: "16rem", sort_first: "desc", sort_variants: measures(&:unit_budget), default: true
  end
end
