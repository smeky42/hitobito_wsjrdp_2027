# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The finance cap (Wsjrdp2027::FinanceCap, ::Ability, ::UserContext): a
# session-chosen ceiling on the finance tier a person exercises. Three
# properties carry it:
#   * it only SUBTRACTS -- a cap can never grant a tier the roles do not hold;
#   * it touches nothing but the finance tiers;
#   * it is scoped to the one Ability it was passed to.
describe "finance cap" do
  let(:manager) { Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person }
  let(:reader) { Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person }

  def ability(person, cap) = Ability.new(person.reload, max_finance_permission: cap)

  it "leaves an uncapped ability exactly as it was" do
    expect(ability(manager, nil).user_context.all_permissions)
      .to match_array(%i[layer_and_below_full layer_and_below_read finance_read finance_audit finance finance_manage])
    expect(ability(manager, nil)).to be_able_to(:fin_admin, DatevBooking)
    expect(Ability.new(manager).identifier).to eq("user-#{manager.id}")
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

  it "tells the tier in force apart from the tier the roles grant" do
    context = ability(manager, :finance_audit).user_context
    expect(context.finance_tier_by_roles).to eq(:finance_manage)
    expect(context.finance_tier).to eq(:finance_audit)

    uncapped = ability(manager, nil).user_context
    expect(uncapped.finance_tier).to eq(:finance_manage)
    expect(uncapped.finance_tier_by_roles).to eq(:finance_manage)

    # No finance permission is a tier of its own, not a missing answer.
    leader = Ability.new(people(:cmt_leader)).user_context
    expect(leader.finance_tier).to eq(:finance_none)
    expect(leader.finance_tier_by_roles).to eq(:finance_none)
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

  it "keys the cache identifier on the cap" do
    expect(ability(manager, :finance_read).identifier).to eq("user-#{manager.id}-fin-finance_read")
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
  end
end
