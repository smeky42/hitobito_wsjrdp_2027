# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The figures of the Controlling page "Budget" (Fin::BudgetsController): per
# cost center and year the budget and the actual spending (IST) from the DATEV
# bookings, plus the whole period ("Gesamt").
#
# * Budget: budget_<year> of the cost center; Gesamt is its
#   effective_total_budget (WsjrdpBudgetable). Budgets are expense budgets,
#   stored positive.
# * IST: the bookings whose PRIMARY cost center is this one -- the "Summe" of the
#   Kostenstellen list (WsjrdpCostCenter.with_booking_summary) -- with the sign
#   turned, so spending counts positive like the budget. The year is the year of
#   the booking date; Gesamt counts every booking, whatever its year.
# * Rows: every cost center with a budget or with bookings, plus a number that
#   only bookings carry; the placeholder number the Kostenstellen list pins out
#   (Fin::CostCentersController::HIDDEN_COST_CENTER_NUMBER) stays out here too.
#   The unit cost centers (is_unit_cost_center) have a table of their own
#   (Fin::UnitBudgetOverview).
# * Sum: per column only the cells with a budget, so the IST of the sum is
#   comparable with its budget -- the income cost centers, which carry no
#   budget, would otherwise turn it negative.
class Fin::BudgetOverview
  YEARS = WsjrdpBudgetable::BUDGET_YEARS

  # Where the share of the budget spent turns orange and red, in percent.
  WARN_PERCENT = 80
  OVER_PERCENT = 100

  # One budget against its IST. `budget` is nil when none is set.
  Cell = Data.define(:budget, :actual) do
    # The IST as a share of the budget in percent; nil without a positive budget.
    def percent = budget&.positive? ? actual * 100 / budget : nil

    # :income (the IST is negative: the cost center took money in), :ok, :warn
    # (over WARN_PERCENT), :over (over OVER_PERCENT), :unbudgeted (IST without a
    # budget) or :empty (neither).
    def level
      p = percent
      if actual.negative? then :income
      elsif p.nil?
        actual.zero? ? :empty : :unbudgeted
      elsif p > OVER_PERCENT then :over
      elsif p > WARN_PERCENT then :warn
      else
        :ok
      end
    end

    def empty? = budget.nil? && actual.zero?

    # The cell as a sum counts it: itself with a budget, else nothing.
    def budgeted = budget ? self : EMPTY_CELL

    def +(other)
      budgets = [budget, other.budget].compact
      Cell.new(budget: budgets.empty? ? nil : budgets.sum, actual: actual + other.actual)
    end
  end

  # One cost center: its cells per year and its Gesamt. `cost_center` is nil for
  # a number that only bookings carry.
  Row = Data.define(:number, :cost_center, :cells, :total) do
    # The Bezeichnung; nil for a number that only bookings carry.
    def name = cost_center&.name.presence
  end

  EMPTY_CELL = Cell.new(budget: nil, actual: BigDecimal(0))

  # The sum row of `rows`: per column the cells with a budget (Cell#budgeted).
  def self.sum_of(rows)
    cells = YEARS.index_with { |year| rows.map { |row| row.cells[year].budgeted }.reduce(EMPTY_CELL, :+) }
    total = rows.map { |row| row.total.budgeted }.reduce(EMPTY_CELL, :+)
    Row.new(number: nil, cost_center: nil, cells: cells, total: total)
  end

  def initialize(excluded_numbers: [Fin::CostCentersController::HIDDEN_COST_CENTER_NUMBER])
    @excluded_numbers = excluded_numbers
  end

  # The rows, by number: every cost center but the units' with a budget or
  # bookings.
  def rows
    @rows ||= begin
      cost_centers = WsjrdpCostCenter.where.not(number: @excluded_numbers).index_by(&:number)
      units = cost_centers.select { |_number, cost_center| cost_center.is_unit_cost_center }.keys
      numbers = (cost_centers.keys + actuals.keys.map(&:first)).uniq.sort - units
      numbers.filter_map { |number| row(number, cost_centers[number]) }
    end
  end

  # The sum over the rows.
  def sum = self.class.sum_of(rows)

  private

  def row(number, cost_center)
    cells = YEARS.index_with do |year|
      Cell.new(budget: cost_center&.budget_for(year), actual: actuals.fetch([number, year], 0).to_d)
    end
    total_actual = actuals.sum { |(key_number, _year), amount| (key_number == number) ? amount : 0 }
    total = Cell.new(budget: cost_center&.effective_total_budget, actual: total_actual.to_d)
    return nil if total.empty? && cells.values.all?(&:empty?)

    Row.new(number: number, cost_center: cost_center, cells: cells, total: total)
  end

  # {[number, year] => IST}: the bookings' sum per primary cost center and
  # booking year, sign turned (spending positive).
  def actuals
    @actuals ||= DatevBooking
      .where.not(cost_center_number: nil)
      .where.not(cost_center_number: @excluded_numbers)
      .group(:cost_center_number, Arel.sql("EXTRACT(YEAR FROM booking_date)::integer"))
      .sum(:signed_base_amount)
      .transform_values { |sum| -sum }
  end
end
