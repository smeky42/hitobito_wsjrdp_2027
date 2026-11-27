# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe WsjrdpAdminTabHelper do
  describe "#impersonate_delay_ms" do
    after { Rails.application.config.x.wsjrdp_impersonate_delay_ms = nil }

    def with_override(value)
      Rails.application.config.x.wsjrdp_impersonate_delay_ms = value
      helper.impersonate_delay_ms
    end

    it "is 3000 ms without the override, and follows it within bounds" do
      expect([nil, "sofort", 0, 999_999].map { with_override(_1) })
        .to eq([3000, 3000, 0, WsjrdpAdminTabHelper::MAX_IMPERSONATE_DELAY_MS])
    end
  end

  describe "#admin_tab?" do
    let(:admin) { double(root?: false, groups_with_permission: [:group]) }
    let(:other) { double(root?: false, groups_with_permission: []) }

    def shown?(mode, user: admin, origin: nil, bar: false)
      without_partial_double_verification do
        allow(helper).to receive_messages(admin_tab: mode, current_user: user, origin_user: origin,
          finance_tier_bar?: bar)
      end
      helper.admin_tab?
    end

    it "is shown with always and hidden with hidden, for an admin" do
      expect([shown?(:always), shown?(:hidden)]).to eq([true, false])
    end

    it "goes by whoever actually logged in" do
      expect(shown?(:always, user: other)).to be(false)
      expect(shown?(:always, user: other, origin: admin)).to be(true)
      expect(shown?(:always, user: admin, origin: other)).to be(false)
      expect(shown?(:always, user: double(root?: true))).to be(true)
    end

    it "shows on demand while one of the bars is missing" do
      expect(shown?(:ondemand)).to be(true)
      expect(shown?(:ondemand, user: other, origin: admin)).to be(true)
      expect(shown?(:ondemand, user: other, origin: admin, bar: true)).to be(false)
    end
  end
end
