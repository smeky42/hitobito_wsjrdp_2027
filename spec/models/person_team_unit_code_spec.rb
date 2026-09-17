# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Which team or unit a person belongs to, as the group spells itself. After a
# deregistration the role is over, so ended roles have to count -- and groups
# without a code (waiting lists, regional IST groups) are no answer at all.
describe "Person#team_unit_code" do
  let(:yp) { people(:yp_a_1) }
  let(:ist) { people(:ist_a_1) }

  before { groups(:unit_a).update!(additional_info: {"group_code" => "A1"}) }

  it "names the code of the group the person has a role in" do
    expect(yp.team_unit_code).to eq("A1")
  end

  it "keeps naming it after the role ended" do
    yp.roles.first.update!(start_on: Date.new(2026, 1, 1), end_on: Date.yesterday)

    expect(yp.reload.team_unit_code).to eq("A1")
  end

  # The uncoded group is skipped by construction, so it does not matter that
  # its role is the current one.
  it "prefers an ended role in a coded group over an active one in an uncoded" do
    Role.create!(person: ist, group: groups(:unit_a), type: "Group::Unit::Member",
      start_on: Date.new(2026, 1, 1), end_on: Date.yesterday)

    expect(ist.reload.team_unit_code).to eq("A1")
  end

  it "takes the most recent of two coded groups" do
    groups(:unit_b).update!(additional_info: {"group_code" => "B2"})
    yp.roles.first.update!(start_on: Date.new(2026, 1, 1))
    Role.create!(person: yp, group: groups(:unit_b), type: "Group::Unit::Member",
      start_on: Date.new(2026, 6, 1), end_on: Date.yesterday)

    expect(yp.reload.team_unit_code).to eq("B2")
  end

  it "falls back to the wsjrdp role without any coded group" do
    expect(ist.team_unit_code).to eq(ist.wsjrdp_role)
    expect(ist.team_unit_code).to eq("IST")
  end
end
