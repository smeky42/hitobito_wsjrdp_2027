require "spec_helper"

# The action lists are literal. Their source is the core
# app/abilities/group_ability.rb together with this wagon's revocations and
# grants in app/abilities/wsjrdp_2027/group_ability.rb; deriving them from the
# ability store would only restate the implementation.

# What :layer_and_below_full (plus the implied :layer_and_below_read) grants on
# the LAYER GROUP the role sits in. The finance actions are added per context.
LAYER_AND_BELOW_FULL_ON_OWN_LAYER = [
  :read, :show_details, :show_statistics, :update, :reactivate, :log,
  :index_people, :index_local_people, :index_full_people, :index_deep_full_people,
  :index_deleted_people, :index_events, :"index_event/courses", :index_mailing_lists,
  :index_notes, :index_calendars, :index_service_tokens,
  :index_person_add_requests, :activate_person_add_requests, :deactivate_person_add_requests,
  :export_events, :"export_event/courses", :export_subgroups,
  :deleted_subgroups, :manage_person_tags, :manage_person_duplicates
].freeze

# The same permission on a layer BELOW the role's own one: what is bound to the
# role's own layer (in_same_layer) drops out -- the local people, the calendars,
# the service tokens, the add requests, the person duplicates -- and what only
# applies further down (:create, :destroy, :modify_superior) comes in.
LAYER_AND_BELOW_FULL_BELOW = [
  :read, :show_details, :show_statistics, :update, :reactivate, :log,
  :create, :destroy, :modify_superior,
  :index_people, :index_full_people, :index_deep_full_people, :index_deleted_people,
  :index_events, :"index_event/courses", :index_mailing_lists, :index_notes,
  :index_person_add_requests,
  :export_events, :"export_event/courses", :export_subgroups,
  :deleted_subgroups, :manage_person_tags
].freeze

describe GroupAbility do
  context "youth participant" do
    let(:yp) { people(:yp_a_1) }

    subject { Ability.new(yp.reload) }

    context "on their own unit" do
      it_behaves_like "only allow group actions", {allowed: [:read, :index_events]} do
        let(:group) { groups(:unit_a) }
      end
    end

    context "on other unit" do
      it_behaves_like "only allow group actions", {allowed: [:read]} do
        let(:group) { groups(:unit_b) }
      end
    end

    context "on contingent" do
      it_behaves_like "only allow group actions", {allowed: [:read]} do
        let(:group) { groups(:root) }
      end
    end

    context "on IST group" do
      it_behaves_like "only allow group actions", {allowed: [:read]} do
        let(:group) { groups(:ist_a) }
      end
    end

    # finance_group_ids counts only for holders of :layer_and_below_full, which
    # a youth participant is not.
    context "on their own unit with an entry in finance_group_ids" do
      before { yp.update!(finance_group_ids: {groups(:unit_a).id.to_s => "show,update"}) }

      it_behaves_like "only allow group actions", {allowed: [:read, :index_events]} do
        let(:group) { groups(:unit_a) }
      end
    end
  end

  context "unit leader" do
    let(:ul) { people(:ul_a_1) }

    subject { Ability.new(ul.reload) }

    context "on their own unit" do
      it_behaves_like "only allow group actions", {allowed: [:read, :show_details, :index_people,
        :index_local_people, :show_statistics, :index_mailing_lists, :index_events,
        :show_finance, :update_finance]} do
        let(:group) { groups(:unit_a) }
      end
    end

    context "on other unit" do
      it_behaves_like "only allow group actions", {allowed: [:read]} do
        let(:group) { groups(:unit_b) }
      end
    end

    context "on contingent" do
      it_behaves_like "only allow group actions", {allowed: [:read]} do
        let(:group) { groups(:root) }
      end
    end

    context "on IST group" do
      it_behaves_like "only allow group actions", {allowed: [:read]} do
        let(:group) { groups(:ist_a) }
      end
    end

    # A unit leader holds :group_full, not :layer_and_below_full, so an entry in
    # finance_group_ids opens nothing for them.
    context "on other unit with an entry in finance_group_ids for it" do
      before { ul.update!(finance_group_ids: {groups(:unit_b).id.to_s => "show,update"}) }

      it_behaves_like "only allow group actions", {allowed: [:read]} do
        let(:group) { groups(:unit_b) }
      end
    end
  end

  context "IST member" do
    let(:ist) { people(:ist_a_1) }

    subject { Ability.new(ist.reload) }

    context "on their own IST group" do
      it_behaves_like "only allow group actions", {allowed: [:read, :index_events]} do
        let(:group) { groups(:ist_a) }
      end
    end

    context "on other IST group" do
      it_behaves_like "only allow group actions", {allowed: [:read]} do
        let(:group) { groups(:ist_b) }
      end
    end

    context "on unit" do
      it_behaves_like "only allow group actions", {allowed: [:read]} do
        let(:group) { groups(:unit_a) }
      end
    end

    context "on contingent" do
      it_behaves_like "only allow group actions", {allowed: [:read]} do
        let(:group) { groups(:root) }
      end
    end
  end

  # Group::Root::Leader: :layer_and_below_full on the root layer, so every
  # group of the contingent -- except for the finance actions, which the layer
  # rule does not grant from the root layer. The CMT leader reaches a group's
  # finance pages through an entry for it in finance_group_ids.
  context "CMT leader" do
    let(:cmt_leader) { people(:cmt_leader) }

    subject { Ability.new(cmt_leader.reload) }

    context "without an entry in finance_group_ids" do
      context "on contingent" do
        it_behaves_like "only allow group actions", {allowed: LAYER_AND_BELOW_FULL_ON_OWN_LAYER} do
          let(:group) { groups(:root) }
        end
      end

      context "on a unit" do
        it_behaves_like "only allow group actions", {allowed: LAYER_AND_BELOW_FULL_BELOW} do
          let(:group) { groups(:unit_a) }
        end
      end

      context "on an IST group" do
        it_behaves_like "only allow group actions", {allowed: LAYER_AND_BELOW_FULL_BELOW} do
          let(:group) { groups(:ist_a) }
        end
      end
    end

    context "with a show entry for a unit" do
      before { cmt_leader.update!(finance_group_ids: {groups(:unit_a).id.to_s => "show"}) }

      context "on that unit" do
        it_behaves_like "only allow group actions",
          {allowed: LAYER_AND_BELOW_FULL_BELOW + [:show_finance]} do
          let(:group) { groups(:unit_a) }
        end
      end

      context "on another unit" do
        it_behaves_like "only allow group actions", {allowed: LAYER_AND_BELOW_FULL_BELOW} do
          let(:group) { groups(:unit_b) }
        end
      end
    end

    context "with a show,update entry for a unit" do
      before { cmt_leader.update!(finance_group_ids: {groups(:unit_a).id.to_s => "show,update"}) }

      it_behaves_like "only allow group actions",
        {allowed: LAYER_AND_BELOW_FULL_BELOW + [:show_finance, :update_finance]} do
        let(:group) { groups(:unit_a) }
      end
    end

    # An update without a show is a valid entry and opens nothing: every page is
    # gated on :show_finance.
    context "with an update entry for a unit" do
      before { cmt_leader.update!(finance_group_ids: {groups(:unit_a).id.to_s => "update"}) }

      it_behaves_like "only allow group actions",
        {allowed: LAYER_AND_BELOW_FULL_BELOW + [:update_finance]} do
        let(:group) { groups(:unit_a) }
      end
    end

    context "with whitespace around the tokens" do
      before do
        cmt_leader.update!(finance_group_ids: {groups(:unit_a).id.to_s => " show , update "})
      end

      it_behaves_like "only allow group actions",
        {allowed: LAYER_AND_BELOW_FULL_BELOW + [:show_finance, :update_finance]} do
        let(:group) { groups(:unit_a) }
      end
    end
  end

  # A Group::Root nested in the contingent ("CMT Warteliste") is a root layer of
  # its own, and the layer rule passes over it as it does over the contingent.
  context "leader of a nested root group" do
    let(:nested_root) { Group::Root.create!(name: "CMT Warteliste", parent: groups(:root)) }
    let(:nested_leader) { Fabricate(Group::Root::Leader.name.to_sym, group: nested_root).person }

    subject { Ability.new(nested_leader.reload) }

    context "on the nested root group" do
      it_behaves_like "only allow group actions", {allowed: LAYER_AND_BELOW_FULL_ON_OWN_LAYER} do
        let(:group) { nested_root }
      end
    end

    context "on a unit" do
      it_behaves_like "only allow group actions", {allowed: [:read]} do
        let(:group) { groups(:unit_a) }
      end
    end
  end

  # Group::Unit::Manager: :layer_and_below_full on their own unit layer only.
  context "unit manager" do
    let(:um) { people(:um_a_1) }

    subject { Ability.new(um.reload) }

    context "on their own unit" do
      it_behaves_like "only allow group actions",
        {allowed: LAYER_AND_BELOW_FULL_ON_OWN_LAYER + [:show_finance, :update_finance]} do
        let(:group) { groups(:unit_a) }
      end
    end

    context "on other unit" do
      it_behaves_like "only allow group actions", {allowed: [:read]} do
        let(:group) { groups(:unit_b) }
      end
    end

    context "on contingent" do
      it_behaves_like "only allow group actions", {allowed: [:read]} do
        let(:group) { groups(:root) }
      end
    end

    # A unit manager holds :layer_and_below_full, so an entry in their
    # finance_group_ids counts, for the group it names and the action it lists.
    context "with a show entry for the other unit" do
      before { um.update!(finance_group_ids: {groups(:unit_b).id.to_s => "show"}) }

      context "on that unit" do
        it_behaves_like "only allow group actions", {allowed: [:read, :show_finance]} do
          let(:group) { groups(:unit_b) }
        end
      end

      context "on their own unit" do
        it_behaves_like "only allow group actions",
          {allowed: LAYER_AND_BELOW_FULL_ON_OWN_LAYER + [:show_finance, :update_finance]} do
          let(:group) { groups(:unit_a) }
        end
      end
    end
  end

  # Group::Ist::Leader: :layer_and_below_full on their IST layer, which
  # includes the IST groups nested beneath it.
  context "IST leader" do
    let(:mist) { people(:mist_a_1) }

    subject { Ability.new(mist.reload) }

    context "on their own IST group" do
      it_behaves_like "only allow group actions",
        {allowed: LAYER_AND_BELOW_FULL_ON_OWN_LAYER + [:show_finance, :update_finance]} do
        let(:group) { groups(:ist_a) }
      end
    end

    context "on an IST group nested in their own" do
      it_behaves_like "only allow group actions",
        {allowed: LAYER_AND_BELOW_FULL_BELOW + [:show_finance, :update_finance]} do
        let(:group) { Group::Ist.create!(name: "IST nested", parent: groups(:ist_a)) }
      end
    end

    context "on other IST group" do
      it_behaves_like "only allow group actions", {allowed: [:read]} do
        let(:group) { groups(:ist_b) }
      end
    end

    context "on a unit" do
      it_behaves_like "only allow group actions", {allowed: [:read]} do
        let(:group) { groups(:unit_a) }
      end
    end

    context "on contingent" do
      it_behaves_like "only allow group actions", {allowed: [:read]} do
        let(:group) { groups(:root) }
      end
    end
  end

  # The finance tiers are not layer-bound, so they answer the same on every
  # group. The read tier is not among them: it grants nothing on a group.
  context "finance tiers" do
    let(:extern) { Group::Extern.create!(name: "Extern", parent: groups(:root)) }

    context "read tier (Group::Root::FinanceReader)" do
      let(:reader) { Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person }

      subject { Ability.new(reader.reload) }

      context "on a unit" do
        it_behaves_like "only allow group actions", {allowed: [:read]} do
          let(:group) { groups(:unit_a) }
        end
      end

      # The role sits in the root group, so the member-of-group grant of
      # :index_events applies there and nowhere else.
      context "on contingent" do
        it_behaves_like "only allow group actions", {allowed: [:read, :index_events]} do
          let(:group) { groups(:root) }
        end
      end
    end

    context "audit tier (Group::Extern::FinanceAuditor)" do
      let(:auditor) { Fabricate(Group::Extern::FinanceAuditor.name.to_sym, group: extern).person }

      subject { Ability.new(auditor.reload) }

      context "on a unit" do
        it_behaves_like "only allow group actions", {allowed: [:read, :show_finance]} do
          let(:group) { groups(:unit_a) }
        end
      end

      context "on contingent" do
        it_behaves_like "only allow group actions", {allowed: [:read, :show_finance]} do
          let(:group) { groups(:root) }
        end
      end
    end

    context "write tier (Group::Extern::FinanceAccountant)" do
      let(:accountant) { Fabricate(Group::Extern::FinanceAccountant.name.to_sym, group: extern).person }

      subject { Ability.new(accountant.reload) }

      context "on a unit" do
        it_behaves_like "only allow group actions",
          {allowed: [:read, :show_finance, :update_finance]} do
          let(:group) { groups(:unit_a) }
        end
      end

      context "on contingent" do
        it_behaves_like "only allow group actions",
          {allowed: [:read, :show_finance, :update_finance]} do
          let(:group) { groups(:root) }
        end
      end
    end

    # Group::Root::Finance and Group::Root::FinanceManager carry
    # :layer_and_below_full on the root layer on top of their tier, and the
    # core's own :finance permission adds :create_invoices_from_list below it.
    context "write tier on the root layer (Group::Root::Finance)" do
      let(:finance) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

      subject { Ability.new(finance.reload) }

      it_behaves_like "only allow group actions",
        {allowed: LAYER_AND_BELOW_FULL_BELOW +
          [:create_invoices_from_list, :show_finance, :update_finance]} do
        let(:group) { groups(:unit_b) }
      end
    end

    context "manage tier on the root layer (Group::Root::FinanceManager)" do
      let(:manager) { Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person }

      subject { Ability.new(manager.reload) }

      it_behaves_like "only allow group actions",
        {allowed: LAYER_AND_BELOW_FULL_BELOW +
          [:create_invoices_from_list, :show_finance, :update_finance]} do
        let(:group) { groups(:unit_b) }
      end
    end

    # The session's finance cap takes the tiers above it out of the permission
    # set, so the accountant reads the page and may no longer edit on it.
    context "write tier capped at the audit tier" do
      let(:accountant) { Fabricate(Group::Extern::FinanceAccountant.name.to_sym, group: extern).person }

      subject { Ability.new(accountant.reload, max_finance_permission: :finance_audit) }

      it_behaves_like "only allow group actions", {allowed: [:read, :show_finance]} do
        let(:group) { groups(:unit_a) }
      end
    end
  end

  # The Verwaltung area of the Finanzen section: a CLASS-SIDE action, so it is
  # asked of Group itself and no constraint on a single group applies. Admin or
  # the manage tier, and the manage tier only once it is picked for the session
  # (doc/roles.md -> "The finance cap").
  describe "class side :configure_finance" do
    let(:extern) { Group::Extern.create!(name: "Extern", parent: groups(:root)) }

    # Without the keyword the ability is not a session's and keeps every tier
    # the roles grant; passing it (nil included) is what makes the cap resolve.
    def can_configure?(person, **options)
      Ability.new(person.reload, **options).can?(:configure_finance, Group)
    end

    it "is held by a CMT admin" do
      admin = Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person

      expect(can_configure?(admin)).to be(true)
    end

    # The fixture `admin` is a Group::Root::Leader (spec/fixtures/roles.yml):
    # :layer_and_below_full and nothing else.
    it "is not held by the fixture admin, who is a Root::Leader" do
      expect(can_configure?(people(:admin))).to be(false)
    end

    it "is held by a finance manager once the manage tier is picked" do
      manager = Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person

      expect(can_configure?(manager, max_finance_permission: :finance_manage)).to be(true)
    end

    # Without a pick a FinanceManager works at the write tier, which does not
    # hold it.
    it "is not held by a finance manager at the default tier" do
      manager = Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person

      expect(can_configure?(manager, max_finance_permission: nil)).to be(false)
    end

    it "is not held by the write tier" do
      finance = Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person

      expect(can_configure?(finance)).to be(false)
    end

    it "is not held by an external accountant" do
      accountant = Fabricate(Group::Extern::FinanceAccountant.name.to_sym, group: extern).person

      expect(can_configure?(accountant)).to be(false)
    end

    it "is not held by the CMT leader" do
      expect(can_configure?(people(:cmt_leader))).to be(false)
    end
  end
end
