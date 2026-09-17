# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The name a field with a hard length can still hold: the full name if it fits,
# otherwise the short one, the last name behind an initial, and finally the
# initials -- cut, if even those are too long.
describe "Person#name_within" do
  let(:person) { people(:yp_a_1) }

  context "with two first names" do
    before { person.attributes = {first_name: "Kim Alex", last_name: "Muster-Beispiel"} }

    it "gives the full name all the room it needs" do
      expect(person.name_within(80)).to eq("Kim Alex Muster-Beispiel")
      expect(person.name_within(24)).to eq("Kim Alex Muster-Beispiel")
    end

    it "drops the second first name next" do
      expect(person.name_within(23)).to eq("Kim Muster-Beispiel")
      expect(person.name_within(19)).to eq("Kim Muster-Beispiel")
    end

    it "puts the first name behind its initial next" do
      expect(person.name_within(18)).to eq("K. Muster-Beispiel")
    end

    it "falls back to the initials" do
      expect(person.name_within(17)).to eq("K. M.")
      expect(person.name_within(5)).to eq("K. M.")
    end

    it "cuts the initials when even they are too long" do
      expect(person.name_within(4)).to eq("K. M")
      expect(person.name_within(2)).to eq("K.")
      expect(person.name_within(0)).to eq("")
    end
  end

  context "with one first name" do
    it "skips the short name, which is the full name here" do
      expect(person.name_within(9)).to eq("YP1 UnitA")
      expect(person.name_within(8)).to eq("Y. UnitA")
      expect(person.name_within(7)).to eq("Y. U.")
    end
  end

  context "without a first name" do
    before { person.attributes = {first_name: "", last_name: "Muster"} }

    it "leaves the last name standing on its own" do
      expect(person.name_within(10)).to eq("Muster")
      expect(person.name_within(5)).to eq("M.")
      expect(person.name_within(1)).to eq("M")
    end
  end
end
