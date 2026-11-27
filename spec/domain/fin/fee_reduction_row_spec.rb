# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Fin::FeeReductionRow do
  let(:yp) { people(:yp_a_1) }
  let(:planner) { people(:ul_a_1) }
  let(:author) { people(:admin) }

  it "dates an active reduction by the person version that set its amount, with its author" do
    with_versioning do
      PaperTrail.request(whodunnit: author.id.to_s) { yp.update!(wsjrdp_total_fee_reduction: 300) }
    end

    row = described_class.for([yp]).first
    expect(row).to have_attributes(activated_by: author, planned?: false)
    expect(row.activated_at).to be_within(1.minute).of(Time.zone.now)
  end

  it "has no activation for a planned reduction alone" do
    planner.update!(planned_total_fee_reduction: "400")

    expect(described_class.for([planner]).first).to have_attributes(activated_at: nil, activated_by: nil,
      planned?: true)
  end
end
