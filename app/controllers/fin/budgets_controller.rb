# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The Controlling page "Budget" at /fin/controlling/budget: budget and DATEV
# actuals per cost center and year (Fin::BudgetOverview), and the unit cost
# centers in a table of their own (Fin::UnitBudgetOverview). Both are the
# finance expandable table (doc/wsjrdp/expandable_table.md), array-backed,
# sortable, each row opening the cost center's detail. Renders under the
# Controlling sheet with its tabs (Sheet::Fin::Budget).
class Fin::BudgetsController < Fin::FinController
  include Wsjrdp::TableStateful

  before_action :authorize_action

  # Two tables on one page, so two prefixes (doc/wsjrdp/expandable_table.md §3).
  # Rows arrive by number; every row is shown.
  COST_CENTERS_POLICY = wsjrdp_expandable_table_policy prefix: "",
    columns: Fin::BudgetColumns::COST_CENTERS.codec,
    sort: {default: []},
    cols: {default: Fin::BudgetColumns::COST_CENTERS.default_keys},
    per_page: {default: :all}
  UNITS_POLICY = wsjrdp_expandable_table_policy prefix: "u",
    columns: Fin::BudgetColumns::UNITS.codec,
    sort: {default: []},
    cols: {default: Fin::BudgetColumns::UNITS.default_keys},
    per_page: {default: :all}

  helper_method :budget_overview, :unit_budget_overview, :budget_rows, :unit_budget_rows

  def index
  end

  private

  def budget_overview = @budget_overview ||= Fin::BudgetOverview.new

  def unit_budget_overview = @unit_budget_overview ||= Fin::UnitBudgetOverview.new

  def budget_rows
    @budget_rows ||= Wsjrdp::ExpandableTableRows.new(
      wsjrdp_expandable_table_state(COST_CENTERS_POLICY), budget_overview.rows,
      sort: Fin::BudgetColumns::COST_CENTERS.sort_expressions, tiebreaker: ->(row) { row.number }
    )
  end

  def unit_budget_rows
    @unit_budget_rows ||= Wsjrdp::ExpandableTableRows.new(
      wsjrdp_expandable_table_state(UNITS_POLICY), unit_budget_overview.rows,
      sort: Fin::BudgetColumns::UNITS.sort_expressions, tiebreaker: ->(row) { row.number }
    )
  end

  def authorize_action
    authorize!(:show, WsjrdpCostCenter)
    authorize!(:show, DatevBooking)
  end
end
