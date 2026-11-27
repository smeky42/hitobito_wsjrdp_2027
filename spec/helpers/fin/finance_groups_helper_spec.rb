# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Fin::FinanceGroupsHelper do
  describe "#finance_by_role" do
    # A unit manager holds :layer_and_below_full in their own unit's layer.
    it "names what a role already grants on the group, ignoring the entry" do
      person = people(:um_a_1)
      person.update!(finance_group_ids: {groups(:unit_a).id.to_s => "show"})

      expect(helper.finance_by_role(person, groups(:unit_a))).to eq(%w[show update])
      expect(person.finance_group_ids).to eq(groups(:unit_a).id.to_s => "show")
    end

    # The CMT leader's :layer_and_below_full sits in the root layer, which the
    # group rules leave out.
    it "names nothing where only the entry opens the group" do
      person = people(:cmt_leader)
      person.update!(finance_group_ids: {groups(:unit_a).id.to_s => "show"})

      expect(helper.finance_by_role(person, groups(:unit_a))).to eq([])
    end
  end

  it "labels the two levels and nothing else" do
    expect(helper.finance_group_level_label(%w[show update])).to be_present
    expect(helper.finance_group_level_label(%w[update])).to be_nil
  end
end
