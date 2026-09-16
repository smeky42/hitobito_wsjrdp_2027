# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# additional_info["finance_group_ids"] maps a group id to the finance actions a
# person may take on that group's page (doc/roles.md -> "Finance on a group's
# page"). The ability rules read it through #finance_group_actions.
describe Person do
  let(:person) { people(:cmt_leader) }
  let(:unit_a) { groups(:unit_a) }
  let(:unit_b) { groups(:unit_b) }

  describe "#finance_group_actions" do
    it "is empty without any entry" do
      expect(person.finance_group_actions(unit_a)).to eq([])
    end

    it "is empty for a group that is not listed" do
      person.finance_group_ids = {unit_a.id.to_s => "show"}

      expect(person.finance_group_actions(unit_b)).to eq([])
    end

    it "is empty for an empty token list" do
      person.finance_group_ids = {unit_a.id.to_s => ""}

      expect(person.finance_group_actions(unit_a)).to eq([])
    end

    it "reads a single token" do
      person.finance_group_ids = {unit_a.id.to_s => "show"}

      expect(person.finance_group_actions(unit_a)).to eq(["show"])
    end

    it "reads comma-separated tokens" do
      person.finance_group_ids = {unit_a.id.to_s => "show,update"}

      expect(person.finance_group_actions(unit_a)).to eq(["show", "update"])
    end

    it "tolerates whitespace around the tokens" do
      person.finance_group_ids = {unit_a.id.to_s => " show , update "}

      expect(person.finance_group_actions(unit_a)).to eq(["show", "update"])
    end

    it "survives a round trip through the database" do
      person.update!(finance_group_ids: {unit_a.id.to_s => "show,update"})

      expect(Person.find(person.id).finance_group_actions(unit_a)).to eq(["show", "update"])
    end
  end

  describe "#finance_group_ids=" do
    it "stores the hash under the finance_group_ids key" do
      person.finance_group_ids = {unit_a.id.to_s => "show"}

      expect(person.additional_info["finance_group_ids"]).to eq(unit_a.id.to_s => "show")
    end

    it "removes the key again on an empty hash (delete_on_blank)" do
      person.finance_group_ids = {unit_a.id.to_s => "show"}
      person.finance_group_ids = {}

      expect(person.additional_info).not_to have_key("finance_group_ids")
      expect(person.finance_group_ids).to be_nil
    end
  end

  # The key is not among the paper-trail-skipped WSJRDP_INTERNAL_ATTRS, so the
  # wagon's Wsjrdp2027::PaperTrail::Events::Base puts the store key into the
  # version's changes like a column of its own.
  describe "versioning" do
    with_versioning do
      it "records a change of finance_group_ids in the version" do
        expect do
          person.update!(finance_group_ids: {unit_a.id.to_s => "show"})
        end.to change { person.versions.count }.by(1)

        expect(person.versions.last.changeset).to have_key("finance_group_ids")
      end
    end
  end
end
