# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Wsjrdp2027::PeopleHelper do
  let(:person) { people(:ul_a_1) }

  it "shows the sleeve length and the uniform order as in the form, the preset while not answered" do
    person.uniform_long_sleeve = false
    person.uniform_order = false
    expect(helper.format_attr(person, :uniform_long_sleeve)).to eq("Kurzarm")
    expect(helper.format_attr(person, :uniform_order)).to eq("Nein")

    person.uniform_long_sleeve = true
    person.uniform_order = true
    expect(helper.format_attr(person, :uniform_long_sleeve)).to eq("Langarm")
    expect(helper.format_attr(person, :uniform_order)).to eq("Ja")

    person.uniform_long_sleeve = nil
    person.uniform_order = nil
    expect(helper.format_attr(person, :uniform_long_sleeve)).to include("nicht gewählt (=Langarm)", "text-muted")
    expect(helper.format_attr(person, :uniform_order)).to include("nicht gewählt (=Ja)", "text-muted")
  end
end
