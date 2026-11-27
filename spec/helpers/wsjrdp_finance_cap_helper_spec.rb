# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe WsjrdpFinanceCapHelper do
  # A manager: the manage tier by roles, the write tier by default.
  def in_force(effective, pick: effective, bar: :ondemand)
    context = double(finance_tier_by_roles: :finance_manage, finance_tier_default: :finance, finance_tier: effective)
    without_partial_double_verification do
      allow(helper).to receive_messages(current_ability: double(user_context: context),
        max_finance_permission: pick, finance_tier_bar: bar)
    end
  end

  it "names the way the tier in force departs from the default" do
    expect(%i[finance_manage finance_read finance].map { |tier|
      in_force(tier)
      helper.finance_tier_direction
    }).to eq(%i[raised lowered same])
  end

  it "offers the tiers up to the roles' own" do
    in_force(:finance)

    expect(helper.selectable_finance_tiers).to eq(%i[finance_none finance_read finance_audit finance finance_manage])
  end

  it "knows no tiers for an ability without a user context" do
    without_partial_double_verification do
      allow(helper).to receive_messages(current_ability: double, max_finance_permission: nil, finance_tier_bar: :ondemand)
    end

    expect([helper.finance_tiers, helper.finance_tier_direction, helper.selectable_finance_tiers,
      helper.finance_tier_elevated?]).to eq([nil, :same, [], false])
  end

  describe "whether the bar shows" do
    it "always shows an elevated tier, whatever the mode" do
      in_force(:finance_manage, bar: :hidden)

      expect(helper.finance_tier_bar?).to be(true)
    end

    it "follows the modes always and hidden for a lowered tier" do
      in_force(:finance_read, bar: :always)
      expect(helper.finance_tier_bar?).to be(true)

      in_force(:finance_read, bar: :hidden)
      expect(helper.finance_tier_bar?).to be(false)
    end

    it "shows on demand while the tier departs from the default or a tier was picked" do
      in_force(:finance_read)
      expect(helper.finance_tier_bar?).to be(true)

      in_force(:finance)
      expect(helper.finance_tier_bar?).to be(true)

      in_force(:finance, pick: nil)
      expect(helper.finance_tier_bar?).to be(false)
    end
  end
end
