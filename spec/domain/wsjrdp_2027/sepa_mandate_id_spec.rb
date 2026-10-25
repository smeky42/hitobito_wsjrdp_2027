# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Standalone: a pure module, no Rails boot.
module Wsjrdp2027; end
require_relative "../../../app/domain/wsjrdp_2027/sepa_mandate_id"

describe Wsjrdp2027::SepaMandateId do
  {
    "wsjrdp20271143" => 1143,
    "wsjrdp2027-1143" => 1143,
    "wsjrdp2027-01143-b" => 1143,
    "wsjrdp20271143b" => 1143,
    "WSJRDP20271143B" => 1143,
    "wsjrdp202711431" => 11_431,
    "foo1143" => nil,
    "" => nil
  }.each do |mandate_id, person_id|
    it "reads #{mandate_id.inspect} as #{person_id.inspect}, as the scripts do" do
      expect(described_class.person_id(mandate_id)).to eq(person_id)
    end
  end

  it "takes only a reference of the person in SEPA characters" do
    expect(described_class.valid_for?("wsjrdp20271143b", 1143)).to be(true)
    expect(described_class.valid_for?("wsjrdp202711431", 1143)).to be(false)
    expect(described_class.valid_for?("wsjrdp20271143_b", 1143)).to be(false)
    expect(described_class.valid_for?("wsjrdp20271143#{"x" * 30}", 1143)).to be(false)
  end
end
