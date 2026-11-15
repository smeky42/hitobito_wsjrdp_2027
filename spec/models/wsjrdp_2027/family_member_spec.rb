# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Wsjrdp2027::FamilyMember: the history of sibling links, and the backport of
# the core's safe deletion of the inverse link.
describe FamilyMember do
  let(:person) { people(:yp_a_1) }
  let(:other) { people(:admin) }

  def link! = FamilyMember.create!(person: person, other: other, kind: :sibling)

  def link_versions(event) = PaperTrail::Version.where(item_type: "FamilyMember", event: event)

  it "removes the inverse link along with a sibling link" do
    link = link!
    expect(FamilyMember.where(person: other, other: person)).to exist

    link.destroy!

    expect(FamilyMember.where(person: [person, other])).to be_empty
  end

  it "does not raise when the inverse link is missing" do
    link = link!
    link.update_column(:family_key, "someotherkey") # rubocop:disable Rails/SkipsModelValidations

    expect { link.destroy! }.not_to raise_error
    expect(FamilyMember.where(id: link.id)).to be_empty
  end

  describe "history", versioning: true do
    it "records linking and unlinking under both people" do
      link = link!
      expect(link_versions("create").pluck(:main_type, :main_id))
        .to contain_exactly(["Person", person.id], ["Person", other.id])

      link.destroy!
      expect(link_versions("destroy").pluck(:main_type, :main_id))
        .to contain_exactly(["Person", person.id], ["Person", other.id])
    end
  end

  describe "kinds" do
    let(:third) { people(:yp_a_2) }

    it "links a parent with the child as inverse, and unlinks both" do
      link = FamilyMember.create!(person: person, other: other, kind: "parent")

      expect(FamilyMember.find_by(person: other, other: person).kind).to eq("child")
      expect(link.kind_label).to eq("Elternteil")
      expect(FamilyMember.find_by(person: other, other: person).kind_label).to eq("Kind")

      link.destroy!
      expect(FamilyMember.where(person: [person, other])).to be_empty
    end

    %w[spouse partner relative].each do |kind|
      it "links #{kind} both ways with the same kind" do
        FamilyMember.create!(person: person, other: other, kind: kind)

        expect(FamilyMember.find_by(person: other, other: person).kind).to eq(kind)
      end
    end

    it "spreads siblings to the family, but nothing else" do
      FamilyMember.create!(person: person, other: other, kind: "parent")
      FamilyMember.create!(person: third, other: person, kind: "sibling")

      expect(FamilyMember.where(person: third).pluck(:other_id)).to eq([person.id])

      fourth = people(:ul_a_1)
      FamilyMember.create!(person: fourth, other: person, kind: "sibling")
      expect(FamilyMember.where(person: fourth).pluck(:other_id)).to contain_exactly(person.id, third.id)
    end

    it "keeps an own name per direction, else the kind's label" do
      link = FamilyMember.create!(person: person, other: other, kind: "relative", label: " Tante ", inverse_label: "Nichte")

      expect(link.label).to eq("Tante")
      expect(link.relation_label).to eq("Tante")
      expect(FamilyMember.find_by(person: other, other: person).relation_label).to eq("Nichte")

      link.update!(label: "  ")
      expect(link.reload.label).to be_nil
      expect(link.relation_label).to eq("Angehörige*r")
    end

    it "names a sibling, parent, child or spouse by the other person's gender, unless an own name is set" do
      sibling = FamilyMember.create!(person: person, other: other, kind: "sibling")
      other.update_columns(gender: "w")
      expect(sibling.reload.relation_label).to eq("Schwester")
      other.update_columns(gender: "m")
      expect(sibling.reload.relation_label).to eq("Bruder")
      other.update_columns(gender: nil)
      expect(sibling.reload.relation_label).to eq("Geschwister")

      sibling.destroy!
      parent = FamilyMember.create!(person: person, other: other, kind: "parent")
      other.update_columns(gender: "w")
      expect(parent.reload.relation_label).to eq("Mutter")
      parent.update!(label: "Stiefmutter")
      expect(parent.relation_label).to eq("Stiefmutter")

      child = FamilyMember.find_by(person: other, other: person)
      person.update_columns(gender: "m")
      expect(child.reload.relation_label).to eq("Sohn")
      person.update_columns(gender: "w")
      expect(child.reload.relation_label).to eq("Tochter")
      person.update_columns(gender: "d")
      expect(child.reload.relation_label).to eq("Kind")

      parent.destroy!
      spouse = FamilyMember.create!(person: person, other: other, kind: "spouse")
      other.update_columns(gender: "m")
      expect(spouse.reload.relation_label).to eq("Ehemann")
      other.update_columns(gender: "w")
      expect(spouse.reload.relation_label).to eq("Ehefrau")
      other.update_columns(gender: nil)
      expect(spouse.reload.relation_label).to eq("Ehepartner*in")
    end

    it "saves with the empty additional_info default, and with data in it" do
      link = FamilyMember.create!(person: person, other: other, kind: "sibling")
      expect(link.reload.additional_info).to eq({})

      link.update!(additional_info: nil)
      expect(link.reload.additional_info).to eq({})

      link.update!(additional_info: {"source" => "duplicates"})
      expect(link.reload.additional_info).to eq({"source" => "duplicates"})
      expect(FamilyMember.find_by(person: other, other: person).additional_info).to eq({})
    end

    it "finds the inverse link by the swapped people alone" do
      link = FamilyMember.create!(person: person, other: other, kind: "parent")
      inverse = FamilyMember.find_by(person: other, other: person)
      inverse.update_column(:family_key, "someotherkey") # rubocop:disable Rails/SkipsModelValidations

      expect(link.inverse_link).to eq(inverse)
      expect(inverse.inverse_link).to eq(link)
    end

    it "reads and changes the inverse label of an existing link" do
      link = FamilyMember.create!(person: person, other: other, kind: "relative", label: "Tante", inverse_label: "Nichte")
      expect(FamilyMember.find(link.id).inverse_label).to eq("Nichte")

      reloaded = FamilyMember.find(link.id)
      reloaded.update!(inverse_label: " Großnichte ")
      expect(link.inverse_link.label).to eq("Großnichte")
      expect(link.reload.label).to eq("Tante")

      FamilyMember.find(link.id).update!(inverse_label: "")
      expect(link.inverse_link.label).to be_nil
    end

    it "changes the inverse along with a changed kind" do
      link = FamilyMember.create!(person: person, other: other, kind: "sibling")
      link.update!(kind: "parent")

      expect(FamilyMember.find_by(person: other, other: person).kind).to eq("child")
      expect(FamilyMember.where(person: [person, other]).count).to eq(2)

      link.update!(kind: "spouse")
      expect(FamilyMember.find_by(person: other, other: person).kind).to eq("spouse")
    end

    it "refuses linking two existing families with an error instead of raising" do
      FamilyMember.create!(person: person, other: people(:ul_a_1), kind: "sibling")
      FamilyMember.create!(person: other, other: third, kind: "sibling")

      link = FamilyMember.new(person: person.reload, other: other.reload, kind: "spouse")
      expect(link).not_to be_valid
      expect(link.errors.full_messages.join).to include("gehören schon zu verschiedenen Familien")
      expect(FamilyMember.where(person: person, other: other)).to be_empty
    end

    it "clears the family_key of whoever has no link left" do
      link = FamilyMember.create!(person: person, other: other, kind: "sibling")
      FamilyMember.create!(person: person, other: third, kind: "sibling")
      expect([person, other, third].map { |p| p.reload.family_key }.uniq.size).to eq(1)

      FamilyMember.find_by(person: other, other: third)&.destroy!
      link.destroy!
      expect(other.reload.family_key).to be_nil
      expect(person.reload.family_key).to be_present
      expect(third.reload.family_key).to be_present

      FamilyMember.find_by(person: person, other: third).destroy!
      expect([person, third].map { |p| p.reload.family_key }).to eq([nil, nil])
    end

    it "rejects an unknown kind" do
      expect(FamilyMember.new(person: person, other: other, kind: "cousin")).not_to be_valid
    end

    it "offers every kind in the form's select" do
      expect(FamilyMember.kind_labels.keys.map(&:to_s)).to match_array(Wsjrdp2027::FamilyMember::KINDS)
    end
  end
end
