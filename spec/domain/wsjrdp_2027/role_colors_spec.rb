# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Wsjrdp2027::RoleColors do
  it "keys a role by its short name, anything unknown as EXT" do
    expect(described_class.key_for("YP")).to eq "YP"
    expect(described_class.key_for("JPT / JDT")).to eq "JPT"
    expect(described_class.key_for("???")).to eq "EXT"
    expect(described_class.key_for(nil)).to eq "EXT"
  end

  it "has a css class per colour" do
    expect(described_class.css_class("BMT")).to eq "wsjrdp-role-bmt"
    expect(described_class.css).to include(".wsjrdp-role-cmt { background-color: #FED7AA; color: #7C2D12; }")
  end
end
