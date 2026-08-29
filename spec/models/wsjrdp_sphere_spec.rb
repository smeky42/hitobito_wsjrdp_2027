# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe WsjrdpSphere do
  describe "manager association" do
    let(:person) { people(:cmt_leader) }

    it "uses the manager_person_id column, not the derived manager_id" do
      expect(described_class.reflect_on_association(:manager).foreign_key.to_s)
        .to eq("manager_person_id")
    end

    it "reads and writes the manager" do
      sphere = described_class.create!(number: "9001", name: "Test-Sphäre", manager: person)

      expect(sphere.manager_person_id).to eq(person.id)
      expect(sphere.reload.manager).to eq(person)
      expect(person.managed_spheres).to include(sphere)
    end

    it "is optional" do
      expect(described_class.new(number: "9002")).to be_valid
    end
  end
end
