# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# additional_info["cost_center_numbers"] on a group: the cost centers its
# Buchhaltung tab shows, assigned on /fin/admin/group_cost_centers. All numbers
# and names below are invented.
describe Group do
  let(:unit_a) { groups(:unit_a) }

  let!(:cc_a1) { WsjrdpCostCenter.create!(number: "A1", name: "Kostenstelle A1") }
  let!(:cc_a1_r) { WsjrdpCostCenter.create!(number: "A1-R", name: "Kostenstelle A1-R") }

  describe "#cost_center_numbers" do
    it "stores the list under the cost_center_numbers key" do
      unit_a.cost_center_numbers = ["A1", "A1-R"]

      expect(unit_a.additional_info["cost_center_numbers"]).to eq(["A1", "A1-R"])
    end

    it "survives a round trip through the database" do
      unit_a.update!(cost_center_numbers: ["A1-R", "A1"])

      expect(Group.find(unit_a.id).cost_center_numbers).to eq(["A1-R", "A1"])
    end

    it "removes the key again on an empty list (delete_on_blank)" do
      unit_a.update!(cost_center_numbers: ["A1"])
      unit_a.update!(cost_center_numbers: [])

      unit_a.reload
      expect(unit_a.additional_info).not_to have_key("cost_center_numbers")
      expect(unit_a.cost_center_numbers).to be_nil
    end
  end

  describe "#cost_centers" do
    it "is empty without any number" do
      expect(unit_a.cost_centers).to be_empty
    end

    it "reads the records by number, ordered by number" do
      unit_a.cost_center_numbers = ["A1-R", "A1"]

      expect(unit_a.cost_centers.to_a).to eq([cc_a1, cc_a1_r])
    end

    # A number without a master record simply has no row.
    it "skips a number no cost center carries" do
      unit_a.cost_center_numbers = ["A1", "Z9"]

      expect(unit_a.cost_centers.to_a).to eq([cc_a1])
    end
  end

  describe ".finance_configurable" do
    it "holds the units and IST groups of the fixtures" do
      expect(Group.finance_configurable).to include(groups(:unit_a), groups(:unit_b),
        groups(:ist_a), groups(:ist_b), groups(:empty_unit))
    end

    it "leaves the root group out" do
      expect(Group.finance_configurable).not_to include(groups(:root))
    end

    it "leaves an Extern group out" do
      extern = Group::Extern.create!(name: "Extern", parent: groups(:root))

      expect(Group.finance_configurable).not_to include(extern)
    end

    # A waiting list is told apart by its NAME; there is no flag for it.
    it "leaves a waiting list out, whichever kind it is" do
      lists = ["UL Warteliste", "YP Warteliste"].map do |name|
        Group::Unit.create!(name: name, parent: groups(:root))
      end
      lists << Group::Ist.create!(name: "IST Warteliste", parent: groups(:root))

      expect(Group.finance_configurable).not_to include(*lists)
    end
  end

  # The key is not among the paper-trail-skipped attributes of the group, so
  # Wsjrdp2027::PaperTrail::Events::Base lifts the store key into the version's
  # changes like a column of its own -- the same mechanism the person's
  # finance_group_ids uses.
  describe "versioning" do
    with_versioning do
      it "records a change of cost_center_numbers in the version" do
        expect do
          unit_a.update!(cost_center_numbers: ["A1"])
        end.to change { unit_a.versions.count }.by(1)

        expect(unit_a.versions.last.changeset).to have_key("cost_center_numbers")
      end
    end
  end
end
