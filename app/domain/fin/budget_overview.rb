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
# * IST: the bookings assigned to this cost center in the budget
#   (DatevBooking::BUDGET_COST_CENTER_SQL, "Kostenstelle (Budget-Zuordnung)"):
#   those with it as primary cost center, plus a unit's bookings outside its
#   Unit-Budget that name it as secondary cost center -- with the sign turned,
#   so spending counts positive like the budget. Cell#secondary is the part
#   reached through the secondary cost center. The year is the year of the
#   booking date; Gesamt counts every booking, whatever its year.
# * Rows: every cost center with a budget or with bookings, plus a number that
#   only bookings carry; the placeholder number the Kostenstellen list pins out
#   (Fin::CostCentersController::HIDDEN_COST_CENTER_NUMBER) stays out here too.
#   The unit cost centers (is_unit_cost_center) have a table of their own
#   (Fin::UnitBudgetOverview).
# * Sums (#sums): "Alle Ausgaben" over the rows with a budget or whose Gesamt
#   IST is spending (zero included), "Alle Einnahmen" over the rest -- income
#   without a budget; per column the IST of those rows against the budgets
#   that are set. A budget is an expense budget, so a cost center with one
#   counts as spending even while its IST is income.
class Fin::BudgetOverview
  YEARS = WsjrdpBudgetable::BUDGET_YEARS

  # Where the share of the budget spent turns orange and red, in percent.
  WARN_PERCENT = 80
  OVER_PERCENT = 100

  # One budget against its IST. `budget` is nil when none is set; `secondary`
  # is the part of the IST assigned through the secondary cost center.
  Cell = Data.define(:budget, :actual, :secondary) do
    def initialize(budget:, actual:, secondary: BigDecimal(0))
      super
    end

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

    def +(other)
      budgets = [budget, other.budget].compact
      Cell.new(budget: budgets.empty? ? nil : budgets.sum, actual: actual + other.actual,
        secondary: secondary + other.secondary)
    end
  end

  # One cost center: its cells per year and its Gesamt. `cost_center` is nil for
  # a number that only bookings carry. A sum row has no number and a
  # `sum_label` instead.
  Row = Data.define(:number, :cost_center, :cells, :total, :sum_label) do
    def initialize(number:, cost_center:, cells:, total:, sum_label: nil)
      super
    end

    # The Bezeichnung; nil for a number that only bookings carry.
    def name = cost_center&.name.presence

    # Counted in "Alle Ausgaben": a budget in any column, or in sum spending
    # (zero included).
    def spending? = !total.actual.negative? || !total.budget.nil? || cells.values.any? { |cell| !cell.budget.nil? }
  end

  SPENDING_LABEL = "Alle Ausgaben"
  INCOME_LABEL = "Alle Einnahmen"

  EMPTY_CELL = Cell.new(budget: nil, actual: BigDecimal(0))

  # The sum row of `rows`, labelled `label`: per column the sum of every row's
  # cell.
  def self.sum_of(rows, label)
    cells = YEARS.index_with { |year| rows.map { |row| row.cells[year] }.reduce(EMPTY_CELL, :+) }
    total = rows.map(&:total).reduce(EMPTY_CELL, :+)
    Row.new(number: nil, cost_center: nil, cells: cells, total: total, sum_label: label)
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

  # The sum rows: "Alle Ausgaben" over the rows that are #spending?, "Alle
  # Einnahmen" over the others -- each only when it has rows.
  def sums
    spending, income = rows.partition(&:spending?)
    [[spending, SPENDING_LABEL], [income, INCOME_LABEL]]
      .filter_map { |part, label| self.class.sum_of(part, label) if part.any? }
  end

  private

  def row(number, cost_center)
    cells = YEARS.index_with do |year|
      actual, secondary = actuals.fetch([number, year], [0, 0])
      Cell.new(budget: cost_center&.budget_for(year), actual: actual.to_d, secondary: secondary.to_d)
    end
    own = actuals.select { |(key_number, _year), _sums| key_number == number }.values
    total = Cell.new(budget: cost_center&.effective_total_budget, actual: own.sum(&:first).to_d,
      secondary: own.sum(&:last).to_d)
    return nil if total.empty? && cells.values.all?(&:empty?)

    Row.new(number: number, cost_center: cost_center, cells: cells, total: total)
  end

  # {[number, year] => [IST, part through the secondary cost center]}: the
  # bookings' sum per budget cost center and booking year, sign turned
  # (spending positive).
  def actuals
    @actuals ||= begin
      assigned = "(#{DatevBooking::BUDGET_COST_CENTER_SQL})"
      DatevBooking.with_unit_budget_accounts
        .where(Arel.sql("#{assigned} IS NOT NULL"))
        .where(Arel::Nodes::NotIn.new(Arel.sql(assigned), @excluded_numbers.map { |n| Arel::Nodes.build_quoted(n) }))
        .group(Arel.sql(assigned), Arel.sql("EXTRACT(YEAR FROM datev_bookings.booking_date)::integer"))
        .pluck(Arel.sql(assigned), Arel.sql("EXTRACT(YEAR FROM datev_bookings.booking_date)::integer"),
          Arel.sql("-SUM(datev_bookings.signed_base_amount)"),
          Arel.sql("-COALESCE(SUM(datev_bookings.signed_base_amount) FILTER " \
                   "(WHERE #{assigned} IS DISTINCT FROM datev_bookings.cost_center_number), 0)"))
        .to_h { |number, year, actual, secondary| [[number, year], [actual, secondary]] }
    end
  end
end
