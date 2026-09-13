# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The finance cap (Wsjrdp2027::FinanceCap, ::Ability, ::UserContext): which
# finance tier a person exercises in one session. Four properties carry it:
#   * it only SUBTRACTS -- a pick can never grant a tier the roles do not hold;
#   * it touches nothing but the finance tiers;
#   * it is scoped to the one Ability it was passed the keyword for;
#   * without a pick the DEFAULT tier applies, which is never an elevated one.
describe "finance cap" do
  let(:manager) { Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person }
  let(:reader) { Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person }
  let(:writer) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

  # Passing the keyword is what marks an ability as a session's. Passing nil
  # means "no pick", not "no rule".
  def ability(person, cap) = Ability.new(person.reload, max_finance_permission: cap)

  it "leaves an ability built without the keyword exactly as it was" do
    untouched = Ability.new(manager.reload)

    expect(untouched.user_context.all_permissions)
      .to match_array(%i[layer_and_below_full layer_and_below_read finance_read finance_audit finance finance_manage])
    expect(untouched).to be_able_to(:fin_admin, DatevBooking)
    expect(untouched.identifier).to eq("user-#{manager.id}")
    expect(untouched.user_context.finance_tier_in_force).to be_nil
  end

  # The manage tier has to be asked for. Without a pick a manager works at
  # the highest tier below it, which is the write tier.
  it "drops an elevated tier when there is no pick" do
    session_ability = ability(manager, nil)

    expect(session_ability.user_context.finance_tier).to eq(:finance)
    expect(session_ability.user_context.finance_tier_default).to eq(:finance)
    expect(session_ability.user_context.finance_tier_by_roles).to eq(:finance_manage)
    expect(session_ability).to be_able_to(:update, DatevBooking)
    expect(session_ability).not_to be_able_to(:fin_admin, DatevBooking)
  end

  it "hands the elevated tier back once it is picked" do
    raised = ability(manager, :finance_manage)

    expect(raised.user_context.finance_tier).to eq(:finance_manage)
    expect(raised).to be_able_to(:fin_admin, DatevBooking)
  end

  # Everybody whose ceiling is not an elevated tier keeps what their roles
  # grant, with or without a pick.
  it "changes nothing for tiers that need no asking" do
    [[reader, :finance_read], [writer, :finance]].each do |person, tier|
      context = ability(person, nil).user_context

      expect(context.finance_tier_by_roles).to eq(tier)
      expect(context.finance_tier_default).to eq(tier)
      expect(context.finance_tier).to eq(tier)
    end
  end

  it "takes every tier above the cap out, and nothing else" do
    capped = ability(manager, :finance)

    expect(capped.user_context.all_permissions)
      .to match_array(%i[layer_and_below_full layer_and_below_read finance_read finance_audit finance])
    expect(capped).to be_able_to(:update, DatevBooking)
    expect(capped).not_to be_able_to(:fin_admin, DatevBooking)
    # the layer permission is untouched: still :log on people below the root
    expect(capped).to be_able_to(:log, people(:yp_a_1))
  end

  it "caps down to the read tier, which then reads like a reader" do
    capped = ability(manager, :finance_read)

    expect(capped.user_context.all_permissions & Wsjrdp2027::FinanceCap::TIERS).to eq([:finance_read])
    expect(capped).to be_able_to(:show, DatevBooking)
    expect(capped).not_to be_able_to(:show, AccountingEntry)
    expect(capped).not_to be_able_to(:update, DatevBooking)
    expect(capped).not_to be_able_to(:log, WsjrdpFinAccount)
    # the layer lookup follows the cap
    expect(capped.user_context.permission_layer_ids(:finance)).to eq([])
  end

  it "never grants: a reader capped at the top stays a reader" do
    capped = ability(reader, :finance_manage)

    expect(capped.user_context.all_permissions).to eq([:finance_read])
    expect(capped).not_to be_able_to(:update, DatevBooking)
  end

  it "tells the three tiers apart" do
    context = ability(manager, :finance_audit).user_context
    expect(context.finance_tier_by_roles).to eq(:finance_manage)
    expect(context.finance_tier_default).to eq(:finance)
    expect(context.finance_tier).to eq(:finance_audit)

    # No finance permission is a tier of its own, not a missing answer.
    leader = Ability.new(people(:cmt_leader)).user_context
    expect(leader.finance_tier).to eq(:finance_none)
    expect(leader.finance_tier_by_roles).to eq(:finance_none)
    expect(leader.finance_tier_default).to eq(:finance_none)
  end

  # The lowest tier takes everything away, which is how somebody with finance
  # rights looks at the section the way a person without them sees it.
  it "leaves no finance permission at all when capped at :finance_none" do
    capped = ability(manager, :finance_none)

    expect(capped.user_context.all_permissions & Wsjrdp2027::FinanceAccess::FINANCE_TIERS).to be_empty
    expect(capped.user_context.finance_tier).to eq(:finance_none)
    expect(capped.user_context.finance_tier_by_roles).to eq(:finance_manage)
    expect(capped).not_to be_able_to(:show, DatevBooking)
    expect(capped).not_to be_able_to(:update, DatevBooking)
    expect(Wsjrdp2027::FinanceCap.valid?("finance_none")).to be(true)
  end

  it "keys the cache identifier on the tier in force, not on the pick" do
    expect(ability(manager, :finance_read).identifier).to eq("user-#{manager.id}-fin-finance_read")
    # no pick, so the default tier -- and a different set of rights than the
    # keyword-less ability above, which must not share its cache key
    expect(ability(manager, nil).identifier).to eq("user-#{manager.id}-fin-finance")
    # a pick above the ceiling is resolved to the ceiling
    expect(ability(reader, :finance_manage).identifier).to eq("user-#{reader.id}-fin-finance_read")
  end

  it "does not leak into an ability built elsewhere" do
    ability(manager, :finance_read)
    expect(Wsjrdp2027::FinanceCap.current).to be_nil
    expect(Ability.new(manager)).to be_able_to(:fin_admin, DatevBooking)
  end

  describe Wsjrdp2027::FinanceCap do
    it "knows the tiers in rank order" do
      expect(described_class.removed_by(:finance_audit)).to eq(%i[finance finance_manage])
      expect(described_class.removed_by(:finance_manage)).to eq([])
      expect(described_class.removed_by(nil)).to eq([])
    end

    it "validates strings as they come from the session" do
      expect(described_class).to be_valid("finance_read")
      expect(described_class).not_to be_valid("admin")
      expect(described_class).not_to be_valid("")
    end

    it "names the default of every ceiling: the highest tier nobody has to ask for" do
      expect(described_class.default_for(:finance_manage)).to eq(:finance)
      expect(described_class.default_for(:finance)).to eq(:finance)
      expect(described_class.default_for(:finance_audit)).to eq(:finance_audit)
      expect(described_class.default_for(:finance_read)).to eq(:finance_read)
      expect(described_class.default_for(:finance_none)).to eq(:finance_none)
    end

    it "resolves a pick against the ceiling, and UNSET not at all" do
      expect(described_class.resolve(manager, described_class::UNSET)).to be_nil
      expect(described_class.resolve(manager, nil)).to eq(:finance)
      expect(described_class.resolve(manager, "finance_manage")).to eq(:finance_manage)
      expect(described_class.resolve(manager, "finance_read")).to eq(:finance_read)
      expect(described_class.resolve(reader, "finance_manage")).to eq(:finance_read)
      expect(described_class.resolve(reader, "quatsch")).to eq(:finance_read)
      expect(described_class.resolve(nil, nil)).to eq(:finance_none)
    end

    it "reads the ceiling off the roles, without building an ability" do
      expect(described_class.granted_for(manager)).to eq(:finance_manage)
      expect(described_class.granted_for(people(:cmt_leader))).to eq(:finance_none)
      expect(described_class.granted_for(nil)).to eq(:finance_none)
    end

    it "spots a pick that asks for more than the roles grant" do
      expect(described_class.exceeds?("finance_manage", reader)).to be(true)
      expect(described_class.exceeds?("finance_read", reader)).to be(false)
      expect(described_class.exceeds?("finance_manage", manager)).to be(false)
      expect(described_class.exceeds?("quatsch", reader)).to be(false) # invalid, dropped elsewhere
    end

    # granted_for reads the role permissions directly, the user context reads
    # them through the core, which expands Role::PermissionImplications. The
    # two only agree as long as no finance tier is implied by another
    # permission.
    it "may read the ceiling straight from the roles: no finance tier is implied" do
      implied = Role::PermissionImplications.to_a.flatten
      expect(implied & described_class::TIERS).to be_empty
      expect(described_class.granted_for(manager))
        .to eq(Ability.new(manager.reload).user_context.finance_tier_by_roles)
    end
  end
end
