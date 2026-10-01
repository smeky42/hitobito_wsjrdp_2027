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
# sorts through a ->(row){ comparable } extractor; a money column sorts by its
# IST. Every column is shown by default but 2028, which the column menu offers.
module Fin::BudgetColumns
  COST_CENTERS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "budcol") do |c|
    c.column key: "number", abbr: "nr", label: "Kostenstelle", width: "14rem",
      sort: ->(row) { row.number }, default: true
    Fin::BudgetOverview::YEARS.each do |year|
      c.column key: "year_#{year}", abbr: year.to_s[-2..], label: year.to_s, numeric: true,
        width: "8rem", sort: ->(row) { row.cells[year].actual }, default: year != 2028
    end
    c.column key: "total", abbr: "ges", label: "Gesamt", numeric: true, width: "9.5rem",
      sort: ->(row) { row.total.actual }, default: true
  end

  UNITS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "budcol") do |c|
    c.column key: "number", abbr: "nr", label: "Kostenstelle", width: "10rem",
      sort: ->(row) { row.number }, default: true
    c.column key: "expenses", abbr: "aus", label: "Gesamtausgaben", numeric: true,
      width: "9rem", sort: ->(row) { row.expenses }, default: true
    c.column key: "unit_budget", abbr: "ub", label: "Unit-Budget", numeric: true,
      width: "16rem", sort: ->(row) { row.unit_budget.actual }, default: true
  end
end
