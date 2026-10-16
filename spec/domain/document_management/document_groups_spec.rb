# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe DocumentManagement::DocumentGroups do
  def slot(**values)
    {subject_type: "Person", subject_id: 42, key: "deregistration", secondary_key: ""}.merge(values)
  end

  {
    "person-42-deregistration" => {},
    "person-42-deregistration--signed_form" => {secondary_key: "signed_form"},
    "nil-nil-nil" => {subject_type: nil, subject_id: nil, key: "nil"}
  }.each do |param, values|
    it "writes and reads #{param}" do
      expect(described_class.param_for(slot(**values))).to eq(param)
      expect(described_class.slot_from_param(param)).to eq(slot(**values))
    end
  end

  it "has no parameter for a type that is no kind or a key of an older form" do
    expect(described_class.param_for(slot(subject_type: "Group"))).to be_nil
    expect(described_class.param_for(slot(key: "registration-generated"))).to be_nil
  end

  %w[person-42-deregistration-2 person-42-deregistration--signed_form-3 person-42-deregistration--
    Person-42-deregistration group-42-deregistration person-x-deregistration person-42 person-42-a--b--c
    person-042-deregistration].each do |param|
    it "reads no slot from #{param}" do
      expect(described_class.slot_from_param(param)).to be_nil
    end
  end

  it "says whether all, some or none of a group's combinations have a current document" do
    group = ->(current, combinations) { described_class::Group.new(current: current, combinations: combinations) }

    expect([group.call(2, 2), group.call(1, 3), group.call(0, 1)].map(&:current_state)).to eq(%i[all some none])
  end
end
