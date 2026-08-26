require "spec_helper"

# Covers the :fin_admin gate used by every Fin:: controller
# (authorize!(:fin_admin, WsjrdpFinAccount)) and the person-level
# :fin_admin grant. Both rule sets constrain on if_finance_on_root
# (finance permission on the root layer), defined in
# Wsjrdp2027::VariousAbility and Wsjrdp2027::PersonAbility.
describe "finance abilities" do
  let(:fin_models) do
    [
      WsjrdpFinAccount,
      AccountingEntry,
      WsjrdpCamtTransaction,
      WsjrdpPaymentPlan,
      MossBalanceMovement,
      DatevBooking,
      DatevBookingBatch,
      WsjrdpLedgerAccount,
      WsjrdpCostCenter,
      WsjrdpPersonalAccount,
      MossCardTransaction
    ]
  end

  subject(:ability) { Ability.new(person.reload) }

  context "with Group::Root::Finance role" do
    let(:person) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

    it "may fin_admin every finance model (class and instance)" do
      fin_models.each do |model|
        is_expected.to be_able_to(:fin_admin, model)
        is_expected.to be_able_to(:fin_admin, model.new)
      end
    end

    it "may show and update finance records" do
      is_expected.to be_able_to(:show, WsjrdpFinAccount.new)
      is_expected.to be_able_to(:update, AccountingEntry.new)
    end

    it "may fin_admin other people" do
      is_expected.to be_able_to(:fin_admin, people(:yp_a_1))
    end
  end

  context "with Group::Root::Admin role" do
    let(:person) { Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person }

    it "may fin_admin finance models (admin role carries the finance permission)" do
      is_expected.to be_able_to(:fin_admin, WsjrdpFinAccount)
      is_expected.to be_able_to(:fin_admin, AccountingEntry.new)
    end

    it "may fin_admin other people" do
      is_expected.to be_able_to(:fin_admin, people(:yp_a_1))
    end
  end

  context "with Group::Root::Leader role (no finance permission)" do
    let(:person) { people(:cmt_leader) }

    it "may not fin_admin finance models" do
      fin_models.each do |model|
        is_expected.not_to be_able_to(:fin_admin, model)
        is_expected.not_to be_able_to(:fin_admin, model.new)
      end
    end

    it "may not fin_admin other people" do
      is_expected.not_to be_able_to(:fin_admin, people(:yp_a_1))
    end
  end

  context "with Group::Root::Member role" do
    let(:person) { people(:cmt_member1) }

    it "may not fin_admin finance models" do
      is_expected.not_to be_able_to(:fin_admin, WsjrdpFinAccount)
      is_expected.not_to be_able_to(:fin_admin, AccountingEntry.new)
    end
  end

  context "with a unit leader role" do
    let(:person) { people(:ul_a_1) }

    it "may not fin_admin finance models" do
      is_expected.not_to be_able_to(:fin_admin, WsjrdpFinAccount)
      is_expected.not_to be_able_to(:fin_admin, WsjrdpCamtTransaction.new)
    end
  end
end
