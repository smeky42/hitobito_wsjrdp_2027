# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Fin::FeeReductionsFilterSchema do
  let(:yp) { people(:yp_a_1) }
  let(:planner) { people(:ul_a_1) }

  # yp: an active reduction, confirmed; planner: a planned one only.
  before do
    yp.update!(wsjrdp_total_fee_reduction: 250, wsjrdp_total_fee_reduction_hint: "Härtefall",
      wsjrdp_total_fee_reduction_comment: "Nachweis liegt vor", status: "confirmed")
    planner.update!(planned_total_fee_reduction: "400", planned_total_fee_reduction_comment: "Härtefall laut Antrag")
  end

  def found(tree)
    Wsjrdp::Filtering::Compiler.new(described_class.bound)
      .apply(Wsjrdp::Filtering::Query.parse(tree)).where(id: [yp.id, planner.id]).to_a
  end

  it "tells a planned reduction" do
    expect(found([[["planned", "in", "ja"]]])).to eq [planner]
    expect(found([[["planned", "in", "nein"]]])).to eq [yp]
  end

  it "searches names, hint and comment, the planned ones too" do
    expect(found([[["search", "contains", "Nachweis"]]])).to eq [yp]
    expect(found([[["search", "contains", "laut Antrag"]]])).to eq [planner]
    expect(found([[["search", "contains", yp.first_name]]])).to eq [yp]
  end

  it "tells a confirmed person" do
    expect(found([[["confirmed", "in", "ja"]]])).to eq [yp]
    expect(found([[["confirmed", "in", "nein"]]])).to eq [planner]
  end

  it "narrows by the contract as stored, its quick filter counting an ended one as none" do
    yp.update_columns(contract_status: "confirmed", contract_confirmed_at: 1.month.ago)
    planner.update_columns(contract_status: "ended", contract_ended_at: 1.day.ago)
    none_value = Fin::PersonStatusFilter::CONTRACT_PRESET[:members].last[:value]

    expect(found([[["contract_status", "in", "confirmed"]]])).to eq [yp]
    expect(found([[["contract_status", "in", *none_value]]])).to eq [planner]
  end
end
