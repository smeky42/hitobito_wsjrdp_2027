# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Only an admin manages API keys: those of the root group fully, those of
# every other layer shown and deleted only (Wsjrdp2027::ServiceTokenAbility,
# :index_service_tokens in Wsjrdp2027::GroupAbility). The :layer_full and
# :layer_and_below_full holders the core lets manage their layer's API keys
# get none of it.
describe ServiceTokenAbility do
  let(:actions) { %i[show new create edit update regenerate_token destroy] }
  let(:root) { groups(:root) }

  # An API key outside the root group, which the model refuses to make: it is
  # made in the root group and moved with update_column.
  def token_in(group)
    ServiceToken.create!(layer: root, name: "Skript #{SecureRandom.hex(4)}", people: true,
      permission: "layer_read").tap { |token| token.update_column(:layer_group_id, group.id) }
  end

  def allowed(person, token) = actions.select { |action| Ability.new(person.reload).can?(action, token) }

  def can_index?(person, group) = Ability.new(person.reload).can?(:index_service_tokens, group)

  context "admin" do
    let(:admin) { Fabricate(Group::Root::Admin.name.to_sym, group: root).person }

    it "manages the API keys of the root group" do
      expect(can_index?(admin, root)).to be(true)
      expect(allowed(admin, token_in(root))).to eq(actions)
      expect(allowed(admin, root.service_tokens.new)).to eq(actions)
    end

    it "shows and deletes, but neither makes nor edits, the API keys of another layer" do
      [groups(:unit_a), groups(:ist_a)].each do |group|
        expect(can_index?(admin, group)).to be(true), group.name
        expect(allowed(admin, token_in(group))).to eq(%i[show destroy]), group.name
        expect(allowed(admin, group.service_tokens.new)).to eq(%i[show destroy]), group.name
      end
    end

    # A Group::Root nested in the contingent is a root layer of its own, not
    # the root group.
    it "treats a nested root group like any other layer" do
      nested = Group::Root.create!(name: "CMT Warteliste", parent: root)
      expect(can_index?(admin, nested)).to be(true)
      expect(allowed(admin, token_in(nested))).to eq(%i[show destroy])
    end
  end

  # :layer_and_below_full on the root layer, without :admin.
  [Group::Root::Leader, Group::Root::Finance, Group::Root::FinanceManager].each do |role_class|
    context role_class.name do
      let(:person) { Fabricate(role_class.name.to_sym, group: root).person }

      it "manages no API key, not even of the root group" do
        expect(can_index?(person, root)).to be(false)
        expect(allowed(person, token_in(root))).to eq([])
        expect(allowed(person, root.service_tokens.new)).to eq([])
      end
    end
  end

  # The fixture `admin` is a Group::Root::Leader (spec/fixtures/roles.yml).
  it "gives the fixture admin, a Root::Leader, nothing" do
    expect(can_index?(people(:admin), root)).to be(false)
    expect(allowed(people(:admin), token_in(root))).to eq([])
  end

  # :layer_and_below_full on their unit layer.
  context "unit manager" do
    let(:um) { people(:um_a_1) }

    it "manages no API key of their unit nor of the root group" do
      expect(can_index?(um, groups(:unit_a))).to be(false)
      expect(allowed(um, token_in(groups(:unit_a)))).to eq([])
      expect(allowed(um, groups(:unit_a).service_tokens.new)).to eq([])
      expect(allowed(um, token_in(root))).to eq([])
    end
  end

  # :layer_and_below_full on their IST layer.
  context "IST leader" do
    let(:mist) { people(:mist_a_1) }

    it "manages no API key of their IST group nor of the root group" do
      expect(can_index?(mist, groups(:ist_a))).to be(false)
      expect(allowed(mist, token_in(groups(:ist_a)))).to eq([])
      expect(allowed(mist, groups(:ist_a).service_tokens.new)).to eq([])
      expect(can_index?(mist, root)).to be(false)
      expect(allowed(mist, token_in(root))).to eq([])
    end
  end
end
