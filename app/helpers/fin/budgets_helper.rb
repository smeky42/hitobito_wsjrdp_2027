# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The cells of the Controlling page "Budget" (fin/budgets/index): IST and budget
# in whole euros, the share spent as a mini bar and in percent with one
# decimal. The bar's color follows the share on one scale
# (#fin_budget_scale_color): pale sand at 0 %, amber at 80 %, red at 100 %,
# bordeaux from 150 %; the percent takes the bar's color from 80 % on. Green
# where the cost center took money in (the bar then shows the share in
# absolute value, the percent stays negative), striped grey for IST without a
# budget (Fin::BudgetOverview::Cell#level). Every amount cell has a graphical
# tooltip (#fin_budget_tipped) that repeats the cell with cents and currency
# and names the part of the IST assigned through the secondary cost center
# (Fin::BudgetOverview::Cell#secondary). The sum rows ("Alle Ausgaben", in the
# cost-center table also "Alle Einnahmen") are sorted with the others and have
# no detail. The measure a
# column is sorted by (Fin::BudgetColumns.measures) is bold in each of its
# cells.
module Fin::BudgetsHelper
  # The stops of the color scale: [percent, color], interpolated in OKLCH
  # between neighbours; beyond the last stop its color holds.
  SCALE_STOPS = [[0, "#D9D2BF"], [80, "#E3A21A"], [100, "#BE1E2D"], [150, "#6E0D18"]].freeze

  # The CSS color of the scale at `percent`: a color-mix of the two stops
  # around it.
  def fin_budget_scale_color(percent)
    percent = percent.to_f.clamp(SCALE_STOPS.first[0], SCALE_STOPS.last[0])
    (from_pct, from), (to_pct, to) = SCALE_STOPS.each_cons(2).find { |(_, _), (to_pct, _)| percent <= to_pct }
    share = ((percent - from_pct) * 100 / (to_pct - from_pct)).round
    "color-mix(in oklch, #{to} #{share}%, #{from})"
  end

  # The scale as a CSS gradient from its first to its last stop, for the
  # legend.
  def fin_budget_scale_gradient
    top = SCALE_STOPS.last[0].to_f
    stops = (0..top.to_i).step(5).map { |pct| "#{fin_budget_scale_color(pct)} #{(pct * 100 / top).round(1)}%" }
    "linear-gradient(to right, #{stops.join(", ")})"
  end

  # The words under the bar per level: the percent with one decimal.
  def fin_budget_percent_label(cell)
    percent = cell.percent
    return(cell.actual.zero? ? nil : "ohne Budget") if percent.nil?

    "#{number_with_precision(percent, precision: 1, delimiter: ".", separator: ",")} %"
  end

  # A sum row of a table (number nil): its label in the first column, no detail.
  def fin_budget_sum_row?(row) = row.number.nil?

  # The first cell of a row: the cost-center number, the Bezeichnung behind it,
  # thin and muted; the label for a sum row.
  def fin_budget_name_cell(row)
    return row.sum_label if fin_budget_sum_row?(row)

    safe_join([
      content_tag(:span, row.number),
      (content_tag(:span, row.name, class: "fw-light text-muted ms-1") if row.name.present?)
    ].compact)
  end

  # The measures ("ist", "soll", "pct") column `column_key` is sorted by.
  def fin_budget_sorted_measures(state, column_key)
    state.sort_list.filter_map do |key, _dir|
      key.delete_prefix("#{column_key}__") if state.sort_column_for(key) == column_key && key != column_key
    end
  end

  # The column configs of the cost-center table (Fin::BudgetColumns); `state`
  # says which measures to set in bold.
  def fin_budget_cost_center_columns(state)
    total = fin_budget_sorted_measures(state, "total")
    cells = {"number" => ->(row) { fin_budget_name_cell(row) },
             "total" => ->(row) { fin_budget_cell(row.total, sorted: total, heading: fin_budget_tip_heading(row, "Gesamt")) }}
    Fin::BudgetOverview::YEARS.each do |year|
      sorted = fin_budget_sorted_measures(state, "year_#{year}")
      cells["year_#{year}"] = lambda do |row|
        fin_budget_cell(row.cells[year], sorted: sorted, heading: fin_budget_tip_heading(row, year.to_s))
      end
    end
    Fin::BudgetColumns::COST_CENTERS.map { |col| col.to_table_column(cell: cells.fetch(col.key)) }
  end

  # The column configs of the unit table (Fin::BudgetColumns); `state` says
  # which measures to set in bold.
  def fin_budget_unit_columns(state)
    unit_budget = fin_budget_sorted_measures(state, "unit_budget")
    cells = {"number" => ->(row) { fin_budget_name_cell(row) },
             "expenses" => ->(row) { fin_budget_amount_cell(row.expenses, heading: fin_budget_tip_heading(row, "Gesamtausgaben")) },
             "unit_budget" => lambda do |row|
               fin_budget_cell(row.unit_budget, sorted: unit_budget, heading: fin_budget_tip_heading(row, "Unit-Budget"))
             end}
    Fin::BudgetColumns::UNITS.map { |col| col.to_table_column(cell: cells.fetch(col.key)) }
  end

  # Whole euros with thousands points; with `cents:` two decimals and the
  # currency.
  def fin_budget_euros(amount, cents: false)
    return number_with_delimiter(amount.round, delimiter: ".") unless cents

    "#{number_with_precision(amount, precision: 2, delimiter: ".", separator: ",")} €"
  end

  # The tooltip heading of a cell: the row (number and Bezeichnung, or the sum
  # row's label)
  # and the column.
  def fin_budget_tip_heading(row, column_label)
    row_label = fin_budget_sum_row?(row) ? row.sum_label : [row.number, row.name].compact.join(" ")
    "#{row_label} · #{column_label}"
  end

  # `content` with a graphical tooltip: `tip` (HTML) rides along in a
  # <template>, which the page's script (fin/budgets/index) shows in a floating
  # box while the pointer is over the content. The content itself looks no
  # different.
  def fin_budget_tipped(content, tip)
    content_tag(:div, class: "fin-budget-tipped") do
      safe_join([content, content_tag(:template, tip, class: "fin-budget-tip-content")])
    end
  end

  # An amount in whole euros; the exact amount with its currency in a tooltip
  # headed `heading`.
  def fin_budget_amount_cell(amount, heading:)
    fin_budget_tipped(content_tag(:span, fin_budget_euros(amount), class: "text-nowrap"),
      safe_join([content_tag(:div, heading, class: "fin-budget-tip-heading"),
        content_tag(:div, fin_budget_euros(amount, cents: true), class: "fin-budget-amounts")]))
  end

  # IST / budget, the bar and the percent; nothing at all for a cell with
  # neither. In the table in whole euros, IST and budget on one line, which
  # breaks between the two only where the column gets too narrow; `sorted`
  # names the measures the column is sorted by, which are bold. The
  # tooltip, headed `heading`, shows the same with cents and currency, plus the
  # part of the IST assigned through the secondary cost center.
  def fin_budget_cell(cell, heading:, sorted: [])
    return "" if cell.empty?

    tip = safe_join([
      content_tag(:div, heading, class: "fin-budget-tip-heading"),
      fin_budget_cell_parts(cell, cents: true),
      (unless cell.secondary.zero?
         content_tag(:div, "davon #{fin_budget_euros(cell.secondary, cents: true)} über sekundäre Kostenstelle",
           class: "fin-budget-tip-note")
       end)
    ].compact)
    fin_budget_tipped(fin_budget_cell_parts(cell, sorted: sorted), tip)
  end

  # The amounts line, the bar and the percent of a cell.
  def fin_budget_cell_parts(cell, cents: false, sorted: [])
    bold = ->(text, measure) { sorted.include?(measure) ? content_tag(:span, text, class: "fin-budget-sorted") : text }
    width = cell.percent ? cell.percent.abs.clamp(0, 100).round(1) : 100
    actual = content_tag(:span, bold.call(fin_budget_euros(cell.actual, cents: cents), "ist"), class: "text-nowrap")
    budget = cell.budget ? bold.call(fin_budget_euros(cell.budget, cents: cents), "soll") : "–"
    percent = fin_budget_percent_label(cell)
    percent = bold.call(percent, "pct") if percent
    color = fin_budget_scale_color(cell.percent) if %i[ok warn over].include?(cell.level)
    safe_join([
      content_tag(:div, class: "fin-budget-amounts") do
        safe_join([actual, " ", content_tag(:span, safe_join(["/ ", budget]), class: "text-muted text-nowrap")])
      end,
      content_tag(:div, class: "fin-budget-bar") do
        content_tag(:div, "", class: "fin-budget-bar-fill fin-budget-#{cell.level}",
          style: ["width: #{width}%", ("background-color: #{color}" if color)].compact.join("; "))
      end,
      content_tag(:div, percent, class: "fin-budget-percent fin-budget-#{cell.level}",
        style: ("color: #{color}" if color && cell.level != :ok))
    ])
  end
end
