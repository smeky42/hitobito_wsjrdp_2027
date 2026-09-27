# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The wagon's scopes in TokenAbility: :log per area (people:log, ...) and the
# finance permissions of the finance scopes; the extras only with an acting
# person.
describe TokenAbility do
  let(:person) { people(:yp_a_1) }
  let(:group) { groups(:root) }
  let(:event) { events(:event_unit_a) }

  def token(scopes, permission: "layer_and_below_full", acting_person: people(:admin))
    ServiceToken.create!(layer: groups(:root), name: "Skript #{SecureRandom.hex(4)}", permission: permission,
      scopes: scopes, acting_person: acting_person)
  end

  describe ":log" do
    it "is granted per area by its :log scope" do
      ability = TokenAbility.new(token(%w[people people:log groups events events:log]))
      expect(ability.can?(:log, person)).to be(true)
      expect(ability.can?(:log, group)).to be(false)
      expect(ability.can?(:log, event)).to be(true)
    end

    it "is not granted without a :log scope" do
      ability = TokenAbility.new(token(%w[people groups events]))
      expect(ability.can?(:log, person)).to be(false)
      expect(ability.can?(:log, group)).to be(false)
    end

    it "is not granted without an acting person" do
      ability = TokenAbility.new(token(%w[people:log groups:log], acting_person: nil))
      expect(ability.can?(:log, person)).to be(false)
      expect(ability.can?(:log, group)).to be(false)
    end

    it "is not granted where the Zugriffsbereich does not allow it" do
      ability = TokenAbility.new(token(%w[people:log groups:log], permission: "layer_and_below_read"))
      expect(ability.can?(:log, person)).to be(false)
      expect(ability.can?(:log, group)).to be(false)
    end

    it "keeps within an acting person's rights" do
      t = token(%w[people:log], acting_person: people(:yp_a_2))
      expect(Wsjrdp2027::ActingPersonTokenAbility.new(t).can?(:log, person)).to be(false)
      t.update!(acting_person: people(:admin))
      expect(Wsjrdp2027::ActingPersonTokenAbility.new(t).can?(:log, person)).to be(true)
    end
  end

  describe "finance" do
    let(:cost_center) { WsjrdpCostCenter.new }
    let(:entry) { AccountingEntry.new }

    def finance_token(scopes, acting_person: nil)
      token(scopes, permission: "layer_and_below_read", acting_person: acting_person)
    end

    def ability(token) = token.acting_person ? Wsjrdp2027::ActingPersonTokenAbility.new(token) : TokenAbility.new(token)

    def person_with(role_class)
      people(:cmt_member1).tap { |person| role_class.create!(person: person, group: groups(:root)) }
    end

    it "grants nothing without a finance scope" do
      expect(ability(finance_token(%w[people])).can?(:show, cost_center)).to be(false)
    end

    it "grants show with finance:read alone, also without an acting person; no :log, no accounting entries" do
      a = ability(finance_token(%w[finance:read]))
      expect(a.can?(:show, cost_center)).to be(true)
      expect(a.can?(:log, cost_center)).to be(false)
      expect(a.can?(:show, entry)).to be(false)
    end

    it "ignores the finance extras without an acting person" do
      a = ability(finance_token(%w[finance:read finance:audit finance:write]))
      expect(a.can?(:log, cost_center)).to be(false)
      expect(a.can?(:update, cost_center)).to be(false)
    end

    it "grants the actions of every finance scope held, within the acting person's tier" do
      finance = person_with(Group::Root::Finance)
      a = ability(finance_token(%w[finance:audit finance:write], acting_person: finance))
      expect(a.can?(:show, entry)).to be(true)
      expect(a.can?(:update, cost_center)).to be(true)
      expect(a.can?(:update_finance, people(:yp_a_1))).to be(true)
      expect(a.can?(:destroy, cost_center)).to be(false)
    end

    it "is capped by the acting person's tier" do
      reader = person_with(Group::Root::FinanceReader)
      a = ability(finance_token(%w[finance:write], acting_person: reader))
      expect(a.can?(:show, cost_center)).to be(true)
      expect(a.can?(:update, cost_center)).to be(false)
    end

    it "caps the acting person at its highest finance scope" do
      manager = person_with(Group::Root::FinanceManager)
      a = ability(finance_token(%w[finance:audit], acting_person: manager))
      expect(a.can?(:show, entry)).to be(true)
      expect(a.can?(:update, cost_center)).to be(false)
    end

    it "manages with finance:manage and a manager as acting person" do
      manager = person_with(Group::Root::FinanceManager)
      a = ability(finance_token(%w[finance:manage], acting_person: manager))
      expect(a.can?(:destroy, cost_center)).to be(true)
      expect(a.can?(:admin_finance, entry)).to be(true)
    end
  end
end
