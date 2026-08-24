# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Budget columns shared by WsjrdpCostCenter and WsjrdpSphere: one signed
# decimal per year (budget_2025..budget_2028, expenses negative -- the sign
# convention of datev_bookings.amount), an optional explicitly set
# `explicit_total_budget`, and the database-generated `effective_total_budget`
# (the yearly sum or the explicit total, whichever has the larger absolute
# value; read-only, see the AddWsjrdpCostCenters migration).
module WsjrdpBudgetable
  extend ActiveSupport::Concern

  # Year = calendar year = rdp fiscal year. Fixed for the project runtime;
  # extending it means a migration plus this constant.
  BUDGET_YEARS = (2025..2028)

  def budget_for(year)
    public_send(:"budget_#{year}") if BUDGET_YEARS.cover?(year)
  end

  # {year => budget} for the years that have a budget set (NULL years omitted).
  def budgets_by_year
    BUDGET_YEARS.index_with { |year| budget_for(year) }.compact
  end
end
