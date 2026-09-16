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
  render_views

  let(:admin) { Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person }
  let(:cmt_leader) { people(:cmt_leader) }
  let(:um_a_1) { people(:um_a_1) }
  let(:ul_a_1) { people(:ul_a_1) }
  let(:unit_a) { groups(:unit_a) }
  let(:unit_b) { groups(:unit_b) }

  # A waiting list is recognised by its name and stays out of the area
  # (Group.finance_configurable).
  let(:waiting_list) { Group::Unit.create!(name: "YP Warteliste", parent: groups(:root)) }

  def body = Nokogiri::HTML(response.body)

  def option_labels(css) = body.css("#{css} option").map { |option| option.text.strip }

  def rows = body.css("#finance-groups-rows tr")

  before { sign_in(admin) }

  describe "index" do
    before { cmt_leader.update!(finance_group_ids: {unit_a.id.to_s => "show"}) }

    it "renders the area's two tabs" do
      get :index

      expect(response).to be_successful
      expect(response.body).to include(I18n.t("fin.tabs.finance_groups"))
      expect(response.body).to include(I18n.t("fin.tabs.group_cost_centers"))
    end

    # The path carries the fragment "groups", which is also what lights the
    # Gruppen main-nav section up; only Finanzen may be the active section here
    # (Wsjrdp2027::NavigationHelper, inactive_for fin/admin).
    it "belongs to the Finanzen section of the main nav alone" do
      get :index

      active = body.css("li.nav-left-section.active").map { |li| li.at_css("a").text.strip }
      expect(active).to eq([I18n.t("navigation.finance")])
    end

    it "lists one row per (person, group) entry" do
      get :index

      expect(rows.size).to eq(1)
      expect(rows.text).to include(cmt_leader.to_s).and include(unit_a.name)
      expect(rows.css("a").pluck("href")).to include(person_path(cmt_leader))
    end

    # The script edits locally, so every row states what the store holds: both
    # ids, the stored level and the two names a pending row is built from.
    it "carries the stored state of a row in its data attributes" do
      get :index

      row = rows.first
      expect(row["data-person-id"]).to eq(cmt_leader.id.to_s)
      expect(row["data-group-id"]).to eq(unit_a.id.to_s)
      expect(row["data-level"]).to eq("show")
      expect(row["data-person-name"]).to eq(cmt_leader.to_s)
      expect(row["data-group-name"]).to eq(unit_a.name)
    end

    # The row's two buttons carry the levels and submit nothing: the stored one
    # is marked, the other one sets a pending level change.
    it "offers the two levels as plain buttons with the stored one marked" do
      get :index

      buttons = rows.css("button[data-level]")
      expect(buttons.pluck("data-level")).to eq(["show", "show,update"])
      expect(buttons.pluck("type")).to all(eq("button"))
      expect(buttons.first["class"]).to include("active")
      expect(buttons.first["aria-pressed"]).to eq("true")
      expect(buttons.last["class"]).not_to include("active")
    end

    # Tokens the page has no level for are left alone: shown as raw text, with
    # neither button marked, so saving is a deliberate act.
    it "shows unknown tokens as raw text with neither button active" do
      cmt_leader.update!(finance_group_ids: {unit_a.id.to_s => "update"})

      get :index

      expect(rows.css("button[data-level].active")).to be_empty
      expect(rows.text).to include("update")
    end

    describe "the role marker" do
      # A unit manager holds :layer_and_below_full in their own unit's layer,
      # so they reach its finance pages without any entry.
      it "marks an entry the person already holds through a role" do
        um_a_1.update!(finance_group_ids: {unit_a.id.to_s => "show"})

        get :index

        marked = rows.find { |row| row.text.include?(um_a_1.to_s) }
        expect(marked.text).to include(I18n.t("fin.finance_groups.by_role",
          level: I18n.t("fin.finance_groups.levels.show,update")))
      end

      # The CMT leader's :layer_and_below_full sits in the ROOT layer, which
      # the group rules leave out -- the entry is the only thing that opens the
      # page for them.
      it "leaves the CMT leader's entry unmarked" do
        get :index

        expect(rows.size).to eq(1)
        expect(rows.text).not_to include("per Rolle")
      end
    end

    describe "filters" do
      before { um_a_1.update!(finance_group_ids: {unit_b.id.to_s => "show"}) }

      it "narrows the rows to one group" do
        get :index, params: {group_id: unit_b.id.to_s}

        expect(rows.size).to eq(1)
        expect(rows.text).to include(um_a_1.to_s)
        expect(rows.text).not_to include(unit_a.name)
      end

      it "narrows the rows to one person" do
        get :index, params: {person_id: cmt_leader.id.to_s}

        expect(rows.size).to eq(1)
        expect(rows.text).to include(cmt_leader.to_s)
      end

      it "makes both filter selects searchable" do
        get :index

        expect(body.at_css("#filter_group_id")["class"]).to include("tom-select")
        expect(body.at_css("#filter_person_id")["class"]).to include("tom-select")
      end
    end

    # The coarse filter in front of the other two: the unit families that
    # exist, the remaining units and the IST groups.
    describe "the family filter" do
      let(:a1) { Group::Unit.create!(name: "A1", parent: groups(:root)) }
      let(:b2) { Group::Unit.create!(name: "B2", parent: groups(:root)) }
      let(:ist_a) { groups(:ist_a) }

      before do
        cmt_leader.update!(finance_group_ids: {
          unit_a.id.to_s => "show", a1.id.to_s => "show",
          b2.id.to_s => "show", ist_a.id.to_s => "show"
        })
      end

      def family_links = body.css("#family-filter a")

      it "offers one entry per family there is" do
        get :index

        expect(family_links.map { |link| link.text.strip })
          .to eq(["Alle", "A-Units", "B-Units", "Sonstige Units", "IST-Gruppen"])
      end

      it "marks the active family" do
        get :index, params: {family: "unit:A"}

        expect(body.css("#family-filter a.active").map { |link| link.text.strip })
          .to eq(["A-Units"])
      end

      it "narrows the rows to one unit family" do
        get :index, params: {family: "unit:A"}

        expect(rows.size).to eq(1)
        expect(rows.text).to include(a1.name)
      end

      it "narrows the rows to the IST groups" do
        get :index, params: {family: "ist"}

        expect(rows.size).to eq(1)
        expect(rows.text).to include(ist_a.name)
      end

      # The fixture units are named "Unit A" / "Unit B", which is no family.
      it "narrows the rows to the units without a family" do
        get :index, params: {family: "unit:other"}

        expect(rows.size).to eq(1)
        expect(rows.text).to include(unit_a.name)
      end

      it "keeps the other filters in the family links" do
        get :index, params: {person_id: cmt_leader.id.to_s}

        hrefs = family_links.pluck("href")
        expect(hrefs).to all(include("person_id=#{cmt_leader.id}"))
        expect(hrefs.last).to include("family=ist")
      end
    end

    describe "the add form" do
      it "offers the candidate roles and no one else" do
        get :index

        labels = option_labels("#new_person_ids").join("\n")
        expect(labels).to include(cmt_leader.to_s)
          .and include(um_a_1.to_s)
          .and include(people(:mist_a_1).to_s)
        expect(labels).not_to include(ul_a_1.to_s)
        expect(labels).not_to include(people(:yp_a_1).to_s)
      end

      it "offers the units and IST groups, but not a waiting list" do
        waiting_list

        get :index

        labels = option_labels("#new_group_ids")
        expect(labels).to include(unit_a.name, unit_b.name, groups(:ist_a).name, groups(:ist_b).name)
        expect(labels).not_to include(waiting_list.name)
      end

      # Both fields take several values at once, rendered as chips by the
      # shared widget (the data attribute is all it takes).
      it "renders both fields as chips comboboxes" do
        get :index

        expect(body.css("select[multiple][data-chips-combobox]").pluck("id"))
          .to eq(["new_person_ids", "new_group_ids"])
      end

      it "offers the two levels as a radio pair with the first preselected" do
        get :index

        radios = body.css("input[type=radio][name=level]")
        expect(radios.pluck("value")).to eq(["show", "show,update"])
        expect(radios.first.key?("checked")).to be(true)
        expect(radios.last.key?("checked")).to be(false)
        expect(radios.pluck("class")).to all(include("btn-check"))
      end
    end

    describe "the pending round" do
      it "keeps the summary box hidden until something is pending" do
        get :index

        box = body.at_css("#finance-groups-pending")
        expect(box.key?("hidden")).to be(true)
        expect(box.css("button").map { |button| button.text.strip }).to eq([
          I18n.t("fin.finance_groups.pending.apply"),
          I18n.t("fin.finance_groups.pending.discard")
        ])
      end

      it "carries the hidden form the whole change list goes off in" do
        get :index

        form = body.at_css("#finance-groups-apply-form")
        expect(form["action"]).to eq(fin_admin_finance_groups_path)
        expect(form.at_css("input[name=_method]")["value"]).to eq("patch")
        expect(form.at_css("input[name=changes]")).to be_present
      end

      it "carries the blueprint of a pending row" do
        get :index

        template = body.at_css("#finance-group-row-template")
        expect(template.css("button[data-level]").pluck("data-level")).to eq(["show", "show,update"])
        expect(template.text).to include(I18n.t("fin.finance_groups.pending.new"))
      end

      it "carries the chips-combobox widget script once" do
        get :index

        expect(response.body.scan("window.WsjrdpChipsCombobox = ").size).to eq(1)
      end
    end
  end

  # The one write of the page: the whole round as a JSON change list, level nil
  # meaning the entry goes.
  describe "apply" do
    before do
      cmt_leader.update!(finance_group_ids: {unit_a.id.to_s => "show"})
      um_a_1.update!(finance_group_ids: {unit_b.id.to_s => "show"})
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
    let(:extern) { Group::Extern.create!(name: "Extern", parent: groups(:root)) }

    it "refuses the write tier" do
      sign_in(Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person)

      expect { get :index }.to raise_error(CanCan::AccessDenied)
    end

    it "refuses an external auditor" do
      sign_in(Fabricate(Group::Extern::FinanceAuditor.name.to_sym, group: extern).person)

      expect { get :index }.to raise_error(CanCan::AccessDenied)
    end

    it "refuses the write tier the writing action as well" do
      sign_in(Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person)

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
      sign_in(Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person)
      session[:max_finance_permission] = "finance_manage"

      get :index

      expect(response).to be_successful
    end

    it "refuses the same finance manager at the default tier" do
      sign_in(Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person)

      expect { get :index }.to raise_error(CanCan::AccessDenied)
    end
  end
end
