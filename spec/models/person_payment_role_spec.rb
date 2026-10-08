# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# payment_role, derived from the roles in the person's primary group while it
# is fluid (status registered): the EarlyPayer/RegularPayer prefix from
# early_payer, the payment role type from
# WSJRDP_ROLE_TYPE_TO_PAYMENT_ROLE_TYPE_MAP. Never half a value, and rebuilt
# after every change of a role (Wsjrdp2027::Role), so that a person added to
# a group gets it with the role.
describe Person, "payment role" do
  let(:unit) { groups(:unit_a) }
  let(:ist) { groups(:ist_a) }
  let(:root) { groups(:root) }
  let(:extern) { Group::Extern.create!(name: "Externe", parent: root) }
  let(:yp) { people(:yp_a_1) }

  def add_role(person, type, group)
    Fabricate(type.name.to_sym, person: person, group: group)
  end

  describe "#build_payment_role" do
    it "maps every role type with a fee, leaders of the IST and of the CMT paying as members" do
      table = {
        [Group::Unit::Member, unit] => "Group::Unit::Member",
        [Group::Unit::Leader, unit] => "Group::Unit::Leader",
        [Group::Unit::UnapprovedLeader, unit] => "Group::Unit::Leader",
        [Group::Ist::Member, ist] => "Group::Ist::Member",
        [Group::Ist::Leader, ist] => "Group::Ist::Member",
        [Group::Root::Member, root] => "Group::Root::Member",
        [Group::Root::Leader, root] => "Group::Root::Member",
        [Group::Extern::Member, extern] => "Group::Extern::Member"
      }
      expect(table.keys.map { |type, _| type.name }).to match_array(Person::WSJRDP_ROLE_TYPE_TO_PAYMENT_ROLE_TYPE_MAP.keys)

      table.each do |(type, group), payment_role_type|
        person = Fabricate(:person)
        add_role(person, type, group)
        expect(person.reload.build_payment_role).to eq("RegularPayer::#{payment_role_type}"), type.name
      end
    end

    it "takes the prefix from early_payer" do
      yp.early_payer = true
      expect(yp.build_payment_role).to eq("EarlyPayer::Group::Unit::Member")
    end

    it "is nil, not half a value, when the primary group holds no role with a fee" do
      expect(Fabricate(:person).build_payment_role).to be_nil

      reader = Fabricate(:person)
      add_role(reader, Group::Root::FinanceReader, root)
      expect(reader.reload.build_payment_role).to be_nil
    end

    it "gives the leaders of the IST and of the CMT the members' wsj role" do
      expect(Person::WSJRDP_ROLE_TYPE_TO_WSJ_ROLE_MAP.keys).to match_array(Person::WSJRDP_ROLE_TYPE_TO_PAYMENT_ROLE_TYPE_MAP.keys)
      expect(Person::WSJRDP_ROLE_TYPE_TO_WSJ_ROLE_MAP.values_at("Group::Ist::Leader", "Group::Root::Leader")).to eq(%w[IST CMT])
    end
  end

  describe "#ensure_payment_role" do
    it "keeps the stored value when the roles say nothing, through a save as well" do
      person = Fabricate(:person)
      person.update_columns(payment_role: "RegularPayer::Group::Extern::Member", status: "registered")

      expect(person.ensure_payment_role(rebuild: true)).to eq("RegularPayer::Group::Extern::Member")
      person.first_name = "Changed"
      person.save!
      expect(person.reload.payment_role).to eq("RegularPayer::Group::Extern::Member")
    end

    it "replaces the stored value when the roles say otherwise" do
      yp.update_columns(payment_role: "RegularPayer::Group::Unit::Leader")

      expect(yp.ensure_payment_role(rebuild: true)).to eq("RegularPayer::Group::Unit::Member")
    end
  end

  describe "after a change of a role" do
    it "gives a person added to a group the payment role with the role, logged" do
      person = Fabricate(:person) # saved without a role, as RolesController does
      expect(person.payment_role).to be_nil

      with_versioning { add_role(person, Group::Unit::Member, unit) }

      person.reload
      expect(person.primary_group).to eq(unit)
      expect(person.payment_role).to eq("RegularPayer::Group::Unit::Member")
      expect(person.versions.reorder(:id).last.changeset)
        .to include("payment_role" => [nil, "RegularPayer::Group::Unit::Member"])
    end

    it "follows a change of role" do
      add_role(yp, Group::Unit::UnapprovedLeader, unit)
      roles(:yp_a_1).destroy

      expect(yp.reload.payment_role).to eq("RegularPayer::Group::Unit::Leader")
    end

    it "follows a move to another group" do
      add_role(yp, Group::Ist::Member, ist)
      roles(:yp_a_1).destroy

      yp.reload
      expect(yp.primary_group).to eq(ist)
      expect(yp.payment_role).to eq("RegularPayer::Group::Ist::Member")
    end

    it "keeps the payment role when the last role with a fee goes" do
      yp.update_columns(payment_role: "RegularPayer::Group::Unit::Member")
      roles(:yp_a_1).destroy

      expect(yp.reload.payment_role).to eq("RegularPayer::Group::Unit::Member")
    end

    it "leaves a person alone once the contract is printed" do
      yp.update_columns(status: "printed", payment_role: "RegularPayer::Group::Unit::Member")
      add_role(yp, Group::Ist::Member, ist)
      roles(:yp_a_1).destroy

      expect(yp.reload.payment_role).to eq("RegularPayer::Group::Unit::Member")
    end
  end

  describe "the role predicates" do
    it "answer false without a payment role, not with an error" do
      person = Fabricate(:person)

      expect([person.cmt?, person.ul?, person.yp?, person.ist?, person.single_payment_contract?]).to all(be(false))
      expect(person.short_payment_role).to eq("???")
    end
  end
end
