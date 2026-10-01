# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The cells of the Controlling page "Budget" (fin/budgets/index): IST and budget
# in whole euros -- in euros and cents in the Gesamt, Gesamtausgaben and
# Unit-Budget columns --, the share spent as a mini bar and in percent, colored
# by Fin::BudgetOverview::Cell#level: blue up to 80 %, orange above, red above
# 100 %, green where the cost center took money in (the bar then shows the
# share in absolute value, the percent stays negative), grey for IST without a
# budget. Each table ends in a sum row (t.footer).
module Fin::BudgetsHelper
  # The words under the bar per level: the percent, whole, with one decimal
  # below 1 % so a small share keeps its sign ("-0,1 %").
  def fin_budget_percent_label(cell)
    percent = cell.percent
    return(cell.actual.zero? ? nil : "ohne Budget") if percent.nil?

    precision = (percent.abs < 1 && !percent.zero?) ? 1 : 0
    "#{number_with_precision(percent, precision: precision, delimiter: ".", separator: ",")} %"
  end

  # The first cell of a row: the cost-center number in bold, the Bezeichnung
  # behind it, thin and muted.
  def fin_budget_name_cell(row)
    safe_join([
      content_tag(:span, row.number, class: "fw-bold"),
      (content_tag(:span, row.name, class: "fw-light text-muted ms-1") if row.name.present?)
    ].compact)
  end

  # The column configs of the cost-center table (Fin::BudgetColumns).
  def fin_budget_cost_center_columns
    cells = {"number" => ->(row) { fin_budget_name_cell(row) },
             "total" => ->(row) { fin_budget_cell(row.total, cents: true) }}
    Fin::BudgetOverview::YEARS.each { |year| cells["year_#{year}"] = ->(row) { fin_budget_cell(row.cells[year]) } }
    Fin::BudgetColumns::COST_CENTERS.map { |col| col.to_table_column(cell: cells.fetch(col.key)) }
  end

  # The sum row of the cost-center table, per visible column.
  def fin_budget_cost_center_footer(sum)
    lambda do |col|
      case col[:key]
      when "number" then "Summe"
      when "total" then fin_budget_cell(sum.total, cents: true)
      else fin_budget_cell(sum.cells[col[:key].delete_prefix("year_").to_i])
      end
    end
  end

  # The column configs of the unit table (Fin::BudgetColumns).
  def fin_budget_unit_columns
    cells = {"number" => ->(row) { fin_budget_name_cell(row) },
             "expenses" => ->(row) { fin_budget_euros(row.expenses, cents: true) },
             "unit_budget" => ->(row) { fin_budget_cell(row.unit_budget, cents: true) }}
    Fin::BudgetColumns::UNITS.map { |col| col.to_table_column(cell: cells.fetch(col.key)) }
  end

  # The sum row of the unit table, per visible column.
  def fin_budget_unit_footer(sum)
    lambda do |col|
      case col[:key]
      when "number" then "Summe"
      when "expenses" then fin_budget_euros(sum.expenses, cents: true)
      when "unit_budget" then fin_budget_cell(sum.unit_budget, cents: true)
      end
    end
  end

  # Whole euros with thousands points; with `cents:` two decimals.
  def fin_budget_euros(amount, cents: false)
    return number_with_delimiter(amount.round, delimiter: ".") unless cents

    number_with_precision(amount, precision: 2, delimiter: ".", separator: ",")
  end

  # IST / budget, the bar and the percent; nothing at all for a cell with
  # neither. IST and budget stand on one line, which breaks between the two
  # only where the column gets too narrow.
  def fin_budget_cell(cell, cents: false)
    return "" if cell.empty?

    width = cell.percent ? cell.percent.abs.clamp(0, 100).round(1) : 100
    budget = "/ #{cell.budget ? fin_budget_euros(cell.budget, cents: cents) : "–"}"
    safe_join([
      content_tag(:div, class: "fin-budget-amounts") do
        safe_join([content_tag(:span, fin_budget_euros(cell.actual, cents: cents), class: "text-nowrap"), " ",
          content_tag(:span, budget, class: "text-muted text-nowrap")])
      end,
      content_tag(:div, class: "fin-budget-bar") do
        content_tag(:div, "", class: "fin-budget-bar-fill fin-budget-#{cell.level}", style: "width: #{width}%")
      end,
      content_tag(:div, fin_budget_percent_label(cell), class: "fin-budget-percent fin-budget-#{cell.level}")
    ])
  end
end
