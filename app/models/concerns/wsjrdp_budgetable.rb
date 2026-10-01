# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Budget columns shared by WsjrdpCostCenter, WsjrdpSubCostCenter and
# WsjrdpSphere: one decimal per year (budget_2025..budget_2028), an optional
# explicitly set `explicit_total_budget`, and the database-generated
# `effective_total_budget` (the yearly sum or the explicit total, whichever has
# the larger absolute value; read-only, see the AddWsjrdpCostCenters
# migration). Budgets are EXPENSE budgets and stored positive -- unlike a
# booking's signed amount, where an expense is negative
# (doc/fin/unit_budget.md); the generated total compares by absolute value and
# is indifferent to the sign.
#
# The writers of the five writable budget columns read German text as the
# detail kit's amount input sends it ("1.234,56", Fin::MoneyInput.normalize);
# text they cannot read stays as typed and fails the numericality validation
# instead of being cast to a wrong number.
module WsjrdpBudgetable
  extend ActiveSupport::Concern

  # Year = calendar year = rdp financial year. Fixed for the project runtime;
  # extending it means a migration plus this constant.
  BUDGET_YEARS = (2025..2028)

  # The writable budget columns; effective_total_budget is generated.
  BUDGET_ATTRIBUTES = [*BUDGET_YEARS.map { |year| :"budget_#{year}" }, :explicit_total_budget].freeze

  included do
    validates(*BUDGET_ATTRIBUTES, numericality: {allow_nil: true})
  end

  BUDGET_ATTRIBUTES.each do |attr|
    define_method(:"#{attr}=") { |value| super(Fin::MoneyInput.normalize(value)) }
  end

  def budget_for(year)
    public_send(:"budget_#{year}") if BUDGET_YEARS.cover?(year)
  end

  # {year => budget} for the years that have a budget set (NULL years omitted).
  def budgets_by_year
    BUDGET_YEARS.index_with { |year| budget_for(year) }.compact
  end
end
