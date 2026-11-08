# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The rights on an Umbuchung (WsjrdpInternalTransfer), Wsjrdp2027::VariousAbility:
# the read tiers see it, the write tier may do everything the manage tier may,
# destroying one included. A CMT admin gets that through its :finance permission.
describe "internal transfer abilities" do
  let(:transfer) { WsjrdpInternalTransfer.new }
  let(:extern) { Group::Extern.create!(name: "Extern", parent: groups(:root)) }

  subject(:ability) { Ability.new(person.reload) }

  shared_examples "full rights" do
    it "may do everything with an Umbuchung" do
      %i[show log create update destroy].each do |action|
        is_expected.to be_able_to(action, transfer)
        is_expected.to be_able_to(action, WsjrdpInternalTransfer)
      end
    end
  end

  context "with Group::Root::FinanceReader role (read tier)" do
    let(:person) { Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person }

    it "may only show" do
      is_expected.to be_able_to(:show, transfer)
      %i[log create update destroy].each { |action| is_expected.not_to be_able_to(action, transfer) }
    end
  end

  context "with Group::Extern::FinanceAuditor role (audit tier)" do
    let(:person) { Fabricate(Group::Extern::FinanceAuditor.name.to_sym, group: extern).person }

    it "may show and log, nothing more" do
      is_expected.to be_able_to(:show, transfer)
      is_expected.to be_able_to(:log, transfer)
      %i[create update destroy].each { |action| is_expected.not_to be_able_to(action, transfer) }
    end
  end

  context "with Group::Root::Finance role (write tier)" do
    let(:person) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

    it_behaves_like "full rights"
  end

  context "with Group::Extern::FinanceAccountant role (write tier, extern layer)" do
    let(:person) { Fabricate(Group::Extern::FinanceAccountant.name.to_sym, group: extern).person }

    it_behaves_like "full rights"
  end

  context "with Group::Root::FinanceManager role (manage tier)" do
    let(:person) { Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person }

    it_behaves_like "full rights"
  end

  context "with Group::Root::Admin role (carries :finance)" do
    let(:person) { Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person }

    it_behaves_like "full rights"

    it "sees an Umbuchung only, once capped to the read tier for the session" do
      capped = Ability.new(person.reload, max_finance_permission: :finance_read)
      expect(capped).to be_able_to(:show, transfer)
      expect(capped).not_to be_able_to(:update, transfer)
    end
  end

  context "without a finance permission" do
    let(:person) { people(:cmt_leader) }

    it "may not even show" do
      is_expected.not_to be_able_to(:show, transfer)
    end
  end

  describe "a service token" do
    def finance_token(scopes, acting_person:)
      ServiceToken.create!(layer: groups(:root), name: "Skript #{SecureRandom.hex(4)}",
        permission: "layer_and_below_read", scopes: scopes, acting_person: acting_person)
    end

    def token_ability(token) = Wsjrdp2027::ActingPersonTokenAbility.new(token)

    def person_with(role_class)
      people(:cmt_member1).tap { |member| role_class.create!(person: member, group: groups(:root)) }
    end

    it "may link transfers with finance:write and a write-tier acting person" do
      a = token_ability(finance_token(%w[finance:write], acting_person: person_with(Group::Root::Finance)))
      %i[show create update destroy].each { |action| expect(a.can?(action, transfer)).to be(true) }
    end

    it "only shows with finance:read, whatever the acting person may" do
      a = token_ability(finance_token(%w[finance:read], acting_person: person_with(Group::Root::Finance)))
      expect(a.can?(:show, transfer)).to be(true)
      expect(a.can?(:create, transfer)).to be(false)
    end

    it "is capped by a read-tier acting person" do
      a = token_ability(finance_token(%w[finance:write], acting_person: person_with(Group::Root::FinanceReader)))
      expect(a.can?(:show, transfer)).to be(true)
      expect(a.can?(:create, transfer)).to be(false)
    end
  end
end
