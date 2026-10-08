# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A planned total fee reduction as the sub-row of its Fin::FeeReductionRow in
# the Reduktionen list: its values under the cells they would replace
# (Fin::FeeReductionsHelper#fee_reduction_plan_cell).
Fin::FeeReductionPlan = Data.define(:row) do
  def person = row.person

  # The fee once the plan is active, as the fee computation takes it.
  def fee_cents = person.total_fee_cents_with_reduction(person.planned_total_fee_reduction)
end
