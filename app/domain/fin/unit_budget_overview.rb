# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The unit table of the Controlling page "Budget" (Fin::BudgetsController): per
# unit cost center (is_unit_cost_center) the figures of the group's finance
# tiles (Fin::GroupBookkeepingFigures), without a split by year:
#
# * Gesamtausgaben: every booking with the cost center as primary OR secondary
#   cost center -- all costs the unit caused --, spending positive.
# * Unit-Budget: the part of those bookings that counts against the unit's
#   budget (DatevBooking::EFFECTIVE_IS_UNIT_BUDGET_SQL, doc/fin/unit_budget.md),
#   measured against the cost center's Gesamtbudget (effective_total_budget).
#
# A booking whose primary and secondary cost center are the same unit counts
# once. Two grouped queries, one per cost-center column, serve all units.
class Fin::UnitBudgetOverview
  # One unit cost center. `unit_budget` is a Fin::BudgetOverview::Cell: the
  # Unit-Budget spending against the Gesamtbudget.
  Row = Data.define(:cost_center, :expenses, :unit_budget) do
    def number = cost_center&.number

    def name = cost_center&.name.presence
  end

  # The unit rows, by number.
  def rows
    @rows ||= unit_cost_centers.map do |cost_center|
      expenses, unit_budget = sums.fetch(cost_center.number, [0, 0])
      Row.new(cost_center: cost_center, expenses: expenses.to_d,
        unit_budget: Fin::BudgetOverview::Cell.new(budget: cost_center.effective_total_budget,
          actual: unit_budget.to_d))
    end
  end

  # The sum over the rows: the spending of all units, and the Unit-Budget
  # spending of the units with a budget against their budgets.
  def sum
    cell = rows.map { |row| row.unit_budget.budgeted }.reduce(Fin::BudgetOverview::EMPTY_CELL, :+)
    Row.new(cost_center: nil, expenses: rows.sum(&:expenses), unit_budget: cell)
  end

  private

  def unit_cost_centers
    @unit_cost_centers ||= WsjrdpCostCenter.where(is_unit_cost_center: true).order(:number).to_a
  end

  # {number => [Gesamtausgaben, Unit-Budget-Ausgaben]}, spending positive.
  def sums
    @sums ||= begin
      numbers = unit_cost_centers.map(&:number)
      scope = DatevBooking.with_unit_budget_accounts
      primary = scope.where(cost_center_number: numbers)
      secondary = scope.where(secondary_cost_center_number: numbers)
        .where("datev_bookings.secondary_cost_center_number IS DISTINCT FROM datev_bookings.cost_center_number")
      [aggregate(primary, :cost_center_number), aggregate(secondary, :secondary_cost_center_number)]
        .reduce({}) { |acc, part| acc.merge(part) { |_number, a, b| [a[0] + b[0], a[1] + b[1]] } }
    end
  end

  def aggregate(relation, column)
    relation.group("datev_bookings.#{column}").pluck(
      Arel.sql("datev_bookings.#{column}"),
      Arel.sql("-COALESCE(SUM(datev_bookings.signed_base_amount), 0)"),
      Arel.sql("-COALESCE(SUM(datev_bookings.signed_base_amount) " \
               "FILTER (WHERE #{DatevBooking::EFFECTIVE_IS_UNIT_BUDGET_SQL}), 0)")
    ).to_h { |number, expenses, unit_budget| [number, [expenses, unit_budget]] }
  end
end
