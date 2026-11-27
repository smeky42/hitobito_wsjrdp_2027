# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Gruppen-Finanzzugriff, the first tab of the Verwaltung area
# (/fin/admin/finance_groups): the one editor of
# people.additional_info["finance_group_ids"]. A two-stage editor -- the page
# edits locally and hands the round over as one change list (#apply). Gated on
# :configure_finance on Group -- Admin or the picked manage tier, nobody else.
describe Fin::FinanceGroupsController do
  before_all(setup_fixtures: true) {}

  let_it_be(:admin) { Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person }
  let(:cmt_leader) { people(:cmt_leader) }
  let(:um_a_1) { people(:um_a_1) }
  let(:ul_a_1) { people(:ul_a_1) }
  let(:unit_a) { groups(:unit_a) }
  let(:unit_b) { groups(:unit_b) }

  # A waiting list is recognised by its name and stays out of the area
  # (Group.finance_configurable).
  let(:waiting_list) { Group::Unit.create!(name: "YP Warteliste", parent: groups(:root)) }

  def entries = controller.send(:entries).map { |entry| [entry.person, entry.group_id, entry.tokens] }

  before { sign_in(admin) }

  describe "index" do
    before_all { people(:cmt_leader).reload.update!(finance_group_ids: {groups(:unit_a).id.to_s => "show"}) }

    describe "rendered" do
      render_views

      # The path carries the fragment "groups", which would also light the
      # Gruppen main-nav section up.
      it "belongs to the Finanzen section of the main nav alone, the widget script once" do
        get :index

        active = Nokogiri::HTML(response.body).css("li.nav-left-section.active").map { |li| li.at_css("a").text.strip }
        expect(active).to eq([I18n.t("navigation.finance")])
        expect(response.body.scan("window.WsjrdpChipsCombobox = ").size).to eq(1)
      end
    end

    it "lists one row per (person, group) entry with its stored tokens" do
      get :index

      expect(entries).to eq([[cmt_leader, unit_a.id.to_s, ["show"]]])
    end

    it "offers the candidate roles and no one else in the add form" do
      get :index

      expect(controller.send(:candidates)).to include(cmt_leader, um_a_1, people(:mist_a_1))
      expect(controller.send(:candidates)).not_to include(ul_a_1, people(:yp_a_1))
    end

    describe "filters" do
      before_all { people(:um_a_1).reload.update!(finance_group_ids: {groups(:unit_b).id.to_s => "show"}) }

      it "narrows the rows to one group" do
        get :index, params: {group_id: unit_b.id.to_s}

        expect(entries).to eq([[um_a_1, unit_b.id.to_s, ["show"]]])
      end

      it "narrows the rows to one person" do
        get :index, params: {person_id: cmt_leader.id.to_s}

        expect(entries.map(&:first)).to eq([cmt_leader])
      end
    end

    # The coarse filter in front of the other two: the unit families that
    # exist, the remaining units and the IST groups.
    describe "the family filter" do
      let_it_be(:a1) { Group::Unit.create!(name: "A1", parent: groups(:root)) }
      let_it_be(:b2) { Group::Unit.create!(name: "B2", parent: groups(:root)) }
      let(:ist_a) { groups(:ist_a) }

      before_all do
        people(:cmt_leader).reload.update!(finance_group_ids: {
          groups(:unit_a).id.to_s => "show", a1.id.to_s => "show",
          b2.id.to_s => "show", groups(:ist_a).id.to_s => "show"
        })
      end

      def listed_group_ids = entries.map(&:second)

      it "offers one entry per family there is, keeping the other filters in its links" do
        get :index, params: {person_id: cmt_leader.id.to_s}

        expect(controller.send(:families).map(&:last)).to eq([nil, "unit:A", "unit:B", "unit:other", "ist"])
        expect(controller.send(:family_filter_params, "ist"))
          .to eq(person_id: cmt_leader.id.to_s, family: "ist")
      end

      it "narrows the rows to one unit family" do
        get :index, params: {family: "unit:A"}

        expect(listed_group_ids).to eq([a1.id.to_s])
      end

      it "narrows the rows to the IST groups" do
        get :index, params: {family: "ist"}

        expect(listed_group_ids).to eq([ist_a.id.to_s])
      end

      # The fixture units are named "Unit A" / "Unit B", which is no family.
      it "narrows the rows to the units without a family" do
        get :index, params: {family: "unit:other"}

        expect(listed_group_ids).to eq([unit_a.id.to_s])
      end
    end
  end

  # The one write of the page: the whole round as a JSON change list, level nil
  # meaning the entry goes.
  describe "apply" do
    before_all do
      people(:cmt_leader).reload.update!(finance_group_ids: {groups(:unit_a).id.to_s => "show"})
      people(:um_a_1).reload.update!(finance_group_ids: {groups(:unit_b).id.to_s => "show"})
    end

    def apply(changes) = patch(:apply, params: {changes: changes.to_json})

    it "writes an add, a change and a removal with one version per person" do
      with_versioning do
        apply([
          {person_id: cmt_leader.id, group_id: unit_a.id, level: "show,update"},
          {person_id: cmt_leader.id, group_id: unit_b.id, level: "show"},
          {person_id: um_a_1.id, group_id: unit_b.id, level: nil}
        ])

        expect(cmt_leader.versions.count).to eq(1)
        expect(um_a_1.versions.count).to eq(1)
      end

      expect(response).to redirect_to(fin_admin_finance_groups_path)
      expect(flash[:notice])
        .to eq(I18n.t("fin.finance_groups.applied", added: 1, changed: 1, removed: 1))
      expect(cmt_leader.reload.finance_group_ids)
        .to eq(unit_a.id.to_s => "show,update", unit_b.id.to_s => "show")
      # The last entry gone takes the key with it (delete_on_blank).
      expect(um_a_1.reload.finance_group_ids).to be_nil
    end

    it "counts a change to the stored level as nothing and writes no version" do
      with_versioning do
        apply([{person_id: cmt_leader.id, group_id: unit_a.id, level: "show"}])

        expect(cmt_leader.versions.count).to eq(0)
      end

      expect(flash[:notice]).to eq(I18n.t("fin.finance_groups.unchanged"))
      expect(cmt_leader.reload.finance_group_ids).to eq(unit_a.id.to_s => "show")
    end

    # One bad change leaves the WHOLE list unsaved -- the valid one of the same
    # request included.
    it "rejects an unknown level and saves nothing of the request" do
      apply([
        {person_id: cmt_leader.id, group_id: unit_b.id, level: "show"},
        {person_id: cmt_leader.id, group_id: unit_a.id, level: "destroy"}
      ])

      expect(flash[:alert]).to eq(I18n.t("fin.finance_groups.rejected_level"))
      expect(cmt_leader.reload.finance_group_ids).to eq(unit_a.id.to_s => "show")
    end

    it "rejects a group the area does not configure" do
      apply([{person_id: cmt_leader.id, group_id: waiting_list.id, level: "show"}])

      expect(flash[:alert]).to eq(I18n.t("fin.finance_groups.rejected_group"))
      expect(cmt_leader.reload.finance_group_ids).to eq(unit_a.id.to_s => "show")
    end

    it "rejects an added entry for a person the field does not work for" do
      apply([{person_id: ul_a_1.id, group_id: unit_a.id, level: "show"}])

      expect(flash[:alert]).to eq(I18n.t("fin.finance_groups.rejected_person"))
      expect(ul_a_1.reload.finance_group_ids).to be_nil
    end

    # A removal only asks that the person exist, so an entry somebody outside
    # the candidates still carries can be cleared out here.
    it "removes an entry of a person the field does not work for" do
      ul_a_1.update!(finance_group_ids: {unit_a.id.to_s => "show"})

      apply([{person_id: ul_a_1.id, group_id: unit_a.id, level: nil}])

      expect(flash[:notice])
        .to eq(I18n.t("fin.finance_groups.applied", added: 0, changed: 0, removed: 1))
      expect(ul_a_1.reload.finance_group_ids).to be_nil
    end

    it "rejects a change list that is no JSON array" do
      patch :apply, params: {changes: "{oops"}

      expect(flash[:alert]).to eq(I18n.t("fin.finance_groups.rejected_format"))
      expect(cmt_leader.reload.finance_group_ids).to eq(unit_a.id.to_s => "show")
    end
  end

  # The finance tiers below manage configure nothing, whatever else they may
  # read in the section.
  describe "the gate" do
    let_it_be(:finance) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
    let_it_be(:manager) { Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person }
    let(:extern) { Group::Extern.create!(name: "Extern", parent: groups(:root)) }

    it "refuses the write tier" do
      sign_in(finance)

      expect { get :index }.to raise_error(CanCan::AccessDenied)
    end

    it "refuses an external auditor" do
      sign_in(Fabricate(Group::Extern::FinanceAuditor.name.to_sym, group: extern).person)

      expect { get :index }.to raise_error(CanCan::AccessDenied)
    end

    it "refuses the write tier the writing action as well" do
      sign_in(finance)

      expect do
        patch :apply, params: {changes: [
          {person_id: cmt_leader.id, group_id: unit_b.id, level: "show"}
        ].to_json}
      end.to raise_error(CanCan::AccessDenied)
      expect(cmt_leader.reload.finance_group_ids).to be_nil
    end

    # A FinanceManager works at the write tier until the manage tier is picked
    # for the session (doc/roles.md -> "The finance cap").
    it "opens for a finance manager once the manage tier is picked" do
      sign_in(manager)
      session[:max_finance_permission] = "finance_manage"

      get :index

      expect(response).to be_successful
    end

    it "refuses the same finance manager at the default tier" do
      sign_in(manager)

      expect { get :index }.to raise_error(CanCan::AccessDenied)
    end
  end
end
