# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Fin::CostCentersHelper do
  let(:group) { groups(:root) }

  it "leads a unit's cost center to the Buchhaltung of the group that carries it, no other" do
    group.update!(cost_center_numbers: ["K300"])
    unit = WsjrdpCostCenter.new(number: "K300", is_unit_cost_center: true)

    expect(helper.fin_unit_group_bookkeeping_path(unit)).to eq(group_finance_bookkeeping_path(group))
    expect(helper.fin_unit_group_bookkeeping_path(WsjrdpCostCenter.new(number: "K300"))).to be_nil
    expect(helper.fin_unit_group_bookkeeping_path(WsjrdpCostCenter.new(number: "K9", is_unit_cost_center: true)))
      .to be_nil
  end
end
