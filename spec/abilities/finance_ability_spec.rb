require "spec_helper"

# The finance tiers, as applied by Wsjrdp2027::VariousAbility /
# Wsjrdp2027::PersonAbility through the constraints in
# Wsjrdp2027::FinanceAccess:
#
#   :finance_read  -> :show, the person-level models excepted (Group::Root::FinanceReader)
#   :finance_audit -> + :log, the person-level models included (Group::Extern::FinanceAuditor)
#   :finance       -> + :create, :update             (Group::Root::Finance, ::Admin,
#                                                     Group::Extern::FinanceAccountant)
#   :finance_manage -> + :admin_finance, :manage, :destroy (Group::Root::FinanceManager)
#
# The finance actions are named after what they do, on the finance models as on
# a person: :update_finance from the write tier up (on a person, the SEPA
# mandate id on their form), :admin_finance and :destroy_finance at the manage
# tier.
#
# Four properties matter beyond the plain tier mapping and are covered below:
#   * the tiers are NOT bound to the root layer, so a Finance role in a nested
#     Group::Root ("CMT Warteliste") and an auditor on the Extern layer work;
#   * :log stays out of the READ tier -- it is this wagon's "privileged view"
#     gate, and on the finance models it is what guards the person-level fee
#     list (fin/person_fees);
#   * the person-level models stay out of the READ tier entirely -- a
#     Beitragsbuchung and a Vorabankündigung are one person's fee data, so
#     /fin/ae/:id is person-level in everything but its route;
#   * the AUDIT tier is read-only just the same, but it does get :log and the
#     person-level models -- that is what an external Kassenprüfer*in needs --
#     and still nothing at all on Person.
describe "finance abilities" do
  let(:fin_models) do
    [
      WsjrdpFinAccount,
      AccountingEntry,
      WsjrdpDirectDebitPreNotification,
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

  # A Beitragsbuchung and a Vorabankündigung are one person's fee data. Both
  # share the ladder of the other finance models, minus the read tier.
  let(:person_level_models) { [AccountingEntry, WsjrdpDirectDebitPreNotification] }

  # Not in the fixtures: a nested Group::Root (as "CMT Warteliste" is in
  # production) and an Extern layer for the auditor.
  let(:nested_root) { Group::Root.create!(name: "CMT Warteliste", parent: groups(:root)) }
  let(:extern) { Group::Extern.create!(name: "Extern", parent: groups(:root)) }

  subject(:ability) { Ability.new(person.reload) }

  shared_examples "a read tier" do
    it "may show every finance model but the person-level ones, so it reaches the section" do
      (fin_models - person_level_models).each do |model|
        is_expected.to be_able_to(:show, model)
        is_expected.to be_able_to(:show, model.new)
      end
    end

    # The Beitragsbuchung pages (/fin/ae/:id, the index, the new forms) are
    # person-level and stay closed -- Fin::AccountingEntriesController
    # authorizes exactly this. A Vorabankündigung is the announcement of one
    # person's collection and stays closed with it.
    it "may NOT show a Beitragsbuchung or a Vorabankündigung" do
      person_level_models.each do |model|
        is_expected.not_to be_able_to(:show, model)
        is_expected.not_to be_able_to(:show, model.new)
      end
    end

    it "may not log, create, update, administer or destroy" do
      is_expected.not_to be_able_to(:log, DatevBooking)
      is_expected.not_to be_able_to(:create, AccountingEntry.new)
      is_expected.not_to be_able_to(:update, AccountingEntry.new)
      is_expected.not_to be_able_to(:admin_finance, WsjrdpFinAccount)
      is_expected.not_to be_able_to(:destroy, AccountingEntry.new)
    end

    it "may not reach the person-level fee pages (:log gate) nor a person's finance data" do
      is_expected.not_to be_able_to(:log, WsjrdpFinAccount)
      is_expected.not_to be_able_to(:update_finance, people(:yp_a_1))
    end
  end

  # Read-only like the read tier, but with :log on the finance models -- which
  # is what opens fin/person_fees and the fee blocks -- and with the
  # Beitragsbuchungen. Still nothing on Person.
  shared_examples "an audit tier" do
    it "may show every finance model, the person-level ones included" do
      fin_models.each do |model|
        is_expected.to be_able_to(:show, model)
        is_expected.to be_able_to(:show, model.new)
      end
    end

    it "may log the finance models, so it reaches the person-level fee list" do
      is_expected.to be_able_to(:log, WsjrdpFinAccount)
      is_expected.to be_able_to(:log, DatevBooking)
      person_level_models.each { |model| is_expected.to be_able_to(:log, model.new) }
    end

    it "is read-only all the same" do
      is_expected.not_to be_able_to(:create, AccountingEntry.new)
      is_expected.not_to be_able_to(:update, AccountingEntry.new)
      is_expected.not_to be_able_to(:update, DatevBooking.new)
      is_expected.not_to be_able_to(:admin_finance, WsjrdpFinAccount)
      is_expected.not_to be_able_to(:destroy, AccountingEntry.new)
    end

    it "gets nothing on people" do
      is_expected.not_to be_able_to(:show, people(:yp_a_1))
      is_expected.not_to be_able_to(:log, people(:yp_a_1))
      is_expected.not_to be_able_to(:update_finance, people(:yp_a_1))
    end
  end

  shared_examples "a write tier" do
    it "may show, log, create and update" do
      is_expected.to be_able_to(:show, DatevBooking)
      is_expected.to be_able_to(:log, DatevBooking)
      is_expected.to be_able_to(:create, AccountingEntry.new)
      is_expected.to be_able_to(:update, AccountingEntry.new)
    end

    it "may reach the person-level fee pages and edit a person's finance data" do
      is_expected.to be_able_to(:log, WsjrdpFinAccount)
      is_expected.to be_able_to(:update_finance, people(:yp_a_1))
    end

    it "may NOT administer (:admin_finance / :destroy on the finance models)" do
      fin_models.each { |model| is_expected.not_to be_able_to(:admin_finance, model) }
      is_expected.not_to be_able_to(:destroy, AccountingEntry.new)
    end
  end

  context "with Group::Root::FinanceReader role (read tier)" do
    let(:person) { Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person }

    it_behaves_like "a read tier"
  end

  context "with Group::Extern::FinanceAuditor role (audit tier, EXTERN layer)" do
    let(:person) { Fabricate(Group::Extern::FinanceAuditor.name.to_sym, group: extern).person }

    # The decisive one: the tiers are not root-bound, so an auditor sitting on
    # the Extern layer is not locked out.
    it_behaves_like "an audit tier"
  end

  context "with Group::Extern::FinanceAccountant role (write tier, EXTERN layer)" do
    let(:person) { Fabricate(Group::Extern::FinanceAccountant.name.to_sym, group: extern).person }

    it_behaves_like "a write tier"

    # It carries :finance_audit as well, so the Beitragsbuchungen are open to
    # it -- which the write tier's own :show would grant anyway.
    it "sees the Beitragsbuchungen" do
      is_expected.to be_able_to(:show, AccountingEntry)
      is_expected.to be_able_to(:show, AccountingEntry.new)
    end
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

    it "may still edit a person's finance data (granted via the :admin permission)" do
      is_expected.to be_able_to(:update_finance, people(:yp_a_1))
    end
  end

  context "with Group::Root::FinanceManager role (manage tier)" do
    let(:person) { Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person }

    it "may administer every finance model (class and instance)" do
      fin_models.each do |model|
        is_expected.to be_able_to(:admin_finance, model)
        is_expected.to be_able_to(:admin_finance, model.new)
      end
    end

    it "may do everything the lower tiers may" do
      is_expected.to be_able_to(:show, DatevBooking)
      is_expected.to be_able_to(:log, DatevBooking)
      is_expected.to be_able_to(:update, AccountingEntry.new)
      is_expected.to be_able_to(:log, WsjrdpFinAccount)
      is_expected.to be_able_to(:update_finance, people(:yp_a_1))
    end

    # :manage is CanCan's wildcard, so the manage tier reaches every action --
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
        is_expected.not_to be_able_to(:admin_finance, model)
        is_expected.not_to be_able_to(:admin_finance, model.new)
      end
    end

    it "may not edit other people's finance data" do
      is_expected.not_to be_able_to(:update_finance, people(:yp_a_1))
    end
  end

  context "with Group::Root::Member role" do
    let(:person) { people(:cmt_member1) }

    it "may not touch the finance models" do
      is_expected.not_to be_able_to(:show, WsjrdpFinAccount)
      is_expected.not_to be_able_to(:admin_finance, AccountingEntry.new)
    end
  end

  context "with a unit leader role" do
    let(:person) { people(:ul_a_1) }

    it "may not touch the finance models" do
      is_expected.not_to be_able_to(:show, WsjrdpFinAccount)
      is_expected.not_to be_able_to(:admin_finance, WsjrdpCamtTransaction.new)
    end
  end
end
