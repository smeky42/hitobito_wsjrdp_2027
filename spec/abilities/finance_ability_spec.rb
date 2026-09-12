require "spec_helper"

# The three finance tiers (doc/roles.md), as applied by
# Wsjrdp2027::VariousAbility / Wsjrdp2027::PersonAbility through the
# constraints in Wsjrdp2027::FinanceAccess:
#
#   :finance_read  -> :show, AccountingEntry excepted (Group::Root::FinanceRead,
#                                                     Group::Extern::FinanceAuditor)
#   :finance       -> + :log, :create, :update       (Group::Root::Finance, ::Admin)
#   :finance_admin -> + :fin_admin, :manage, :destroy (Group::Root::FinanceAdmin)
#
# Three properties matter beyond the plain tier mapping and are covered below:
#   * the tiers are NOT bound to the root layer, so a Finance role in a nested
#     Group::Root ("CMT Warteliste") and an auditor on the Extern layer work;
#   * :log stays out of the read tier -- it is this wagon's "privileged view"
#     gate, and it also guards the person-level fee pages (fin/fees,
#     fin/person_fees);
#   * AccountingEntry stays out of the read tier entirely -- a Beitragsbuchung
#     is one person's fee data, so /fin/ae/:id is person-level in everything
#     but its route.
describe "finance abilities" do
  let(:fin_models) do
    [
      WsjrdpFinAccount,
      AccountingEntry,
      WsjrdpCamtTransaction,
      WsjrdpPaymentPlan,
      MossTransaction,
      MossExpense,
      MossBooking,
      DatevBooking,
      DatevBookingBatch,
      WsjrdpLedgerAccount,
      WsjrdpCostCenter,
      WsjrdpPersonalAccount
    ]
  end

  # Not in the fixtures: a nested Group::Root (as "CMT Warteliste" is in
  # production) and an Extern layer for the auditor.
  let(:nested_root) { Group::Root.create!(name: "CMT Warteliste", parent: groups(:root)) }
  let(:extern) { Group::Extern.create!(name: "Extern", parent: groups(:root)) }

  subject(:ability) { Ability.new(person.reload) }

  shared_examples "a read tier" do
    it "may show every finance model but AccountingEntry, so it reaches the section" do
      (fin_models - [AccountingEntry]).each do |model|
        is_expected.to be_able_to(:show, model)
        is_expected.to be_able_to(:show, model.new)
      end
    end

    # The Beitragsbuchung pages (/fin/ae/:id, the index, the new forms) are
    # person-level and stay closed -- Fin::AccountingEntriesController
    # authorizes exactly this.
    it "may NOT show a Beitragsbuchung" do
      is_expected.not_to be_able_to(:show, AccountingEntry)
      is_expected.not_to be_able_to(:show, AccountingEntry.new)
    end

    it "may not log, create, update, fin_admin or destroy" do
      is_expected.not_to be_able_to(:log, DatevBooking)
      is_expected.not_to be_able_to(:create, AccountingEntry.new)
      is_expected.not_to be_able_to(:update, AccountingEntry.new)
      is_expected.not_to be_able_to(:fin_admin, WsjrdpFinAccount)
      is_expected.not_to be_able_to(:destroy, AccountingEntry.new)
    end

    it "may not reach the person-level fee pages (:log gate) nor fin_admin a person" do
      is_expected.not_to be_able_to(:log, WsjrdpFinAccount)
      is_expected.not_to be_able_to(:fin_admin, people(:yp_a_1))
    end
  end

  shared_examples "a write tier" do
    it "may show, log, create and update" do
      is_expected.to be_able_to(:show, DatevBooking)
      is_expected.to be_able_to(:log, DatevBooking)
      is_expected.to be_able_to(:create, AccountingEntry.new)
      is_expected.to be_able_to(:update, AccountingEntry.new)
    end

    it "may reach the person-level fee pages and fin_admin a person" do
      is_expected.to be_able_to(:log, WsjrdpFinAccount)
      is_expected.to be_able_to(:fin_admin, people(:yp_a_1))
    end

    it "may NOT administer (fin_admin / destroy on the finance models)" do
      fin_models.each { |model| is_expected.not_to be_able_to(:fin_admin, model) }
      is_expected.not_to be_able_to(:destroy, AccountingEntry.new)
    end
  end

  context "with Group::Root::FinanceRead role (read tier)" do
    let(:person) { Fabricate(Group::Root::FinanceRead.name.to_sym, group: groups(:root)).person }

    it_behaves_like "a read tier"
  end

  context "with Group::Extern::FinanceAuditor role (read tier, EXTERN layer)" do
    let(:person) { Fabricate(Group::Extern::FinanceAuditor.name.to_sym, group: extern).person }

    # The decisive one: the tier is not root-bound, so an auditor sitting on the
    # Extern layer is not locked out.
    it_behaves_like "a read tier"
  end

  context "with Group::Root::Finance role (write tier)" do
    let(:person) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

    it_behaves_like "a write tier"
  end

  context "with Group::Root::Finance role in a NESTED Group::Root (write tier)" do
    let(:person) { Fabricate(Group::Root::Finance.name.to_sym, group: nested_root).person }

    # Holds :finance on the nested layer, never on the root layer -- must still
    # pass, which a root-bound constraint would not allow.
    it_behaves_like "a write tier"
  end

  context "with Group::Root::Admin role (carries :finance, so write tier)" do
    let(:person) { Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person }

    it_behaves_like "a write tier"

    it "may still fin_admin people (granted via the :admin permission)" do
      is_expected.to be_able_to(:fin_admin, people(:yp_a_1))
    end
  end

  context "with Group::Root::FinanceAdmin role (admin tier)" do
    let(:person) { Fabricate(Group::Root::FinanceAdmin.name.to_sym, group: groups(:root)).person }

    it "may fin_admin every finance model (class and instance)" do
      fin_models.each do |model|
        is_expected.to be_able_to(:fin_admin, model)
        is_expected.to be_able_to(:fin_admin, model.new)
      end
    end

    it "may do everything the lower tiers may" do
      is_expected.to be_able_to(:show, DatevBooking)
      is_expected.to be_able_to(:log, DatevBooking)
      is_expected.to be_able_to(:update, AccountingEntry.new)
      is_expected.to be_able_to(:log, WsjrdpFinAccount)
      is_expected.to be_able_to(:fin_admin, people(:yp_a_1))
    end

    # :manage is CanCan's wildcard, so the admin tier reaches every action --
    # :destroy included -- on all finance models.
    it "may destroy finance records" do
      is_expected.to be_able_to(:destroy, AccountingEntry.new)
      is_expected.to be_able_to(:destroy, DatevBooking.new)
    end
  end

  context "with Group::Root::Leader role (no finance permission)" do
    let(:person) { people(:cmt_leader) }

    it "may not touch the finance models at all" do
      fin_models.each do |model|
        is_expected.not_to be_able_to(:show, model)
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

    it "may not touch the finance models" do
      is_expected.not_to be_able_to(:show, WsjrdpFinAccount)
      is_expected.not_to be_able_to(:fin_admin, AccountingEntry.new)
    end
  end

  context "with a unit leader role" do
    let(:person) { people(:ul_a_1) }

    it "may not touch the finance models" do
      is_expected.not_to be_able_to(:show, WsjrdpFinAccount)
      is_expected.not_to be_able_to(:fin_admin, WsjrdpCamtTransaction.new)
    end
  end
end
