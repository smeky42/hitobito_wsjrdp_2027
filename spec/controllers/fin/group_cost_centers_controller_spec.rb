# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Gruppen-Kostenstellen, the second tab of the Verwaltung area
# (/fin/admin/group_cost_centers): the one editor of
# groups.additional_info["cost_center_numbers"]. The page is ONE form over every
# configurable group, saved in one request. All numbers and names below are
# invented.
describe Fin::GroupCostCentersController do
  render_views

  let(:admin) { Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person }
  let(:unit_a) { groups(:unit_a) }
  let(:unit_b) { groups(:unit_b) }
  let(:ist_a) { groups(:ist_a) }

  # Cost-center numbers are alphanumeric, never just digits.
  let!(:cc_a1) { WsjrdpCostCenter.create!(number: "A1", name: "Kostenstelle A1") }
  let!(:cc_a1_r) { WsjrdpCostCenter.create!(number: "A1-R", name: "Kostenstelle A1-R") }

  def body = Nokogiri::HTML(response.body)

  def rows = body.css("table tbody tr")

  def row(group) = rows.find { |tr| tr.css("td").first.text.strip == group.name }

  def group_version_count = PaperTrail::Version.where(main_type: "Group").count

  before { sign_in(admin) }

  describe "index" do
    it "renders the area's two tabs" do
      get :index

      expect(response).to be_successful
      expect(response.body).to include(I18n.t("fin.tabs.finance_groups"))
      expect(response.body).to include(I18n.t("fin.tabs.group_cost_centers"))
    end

    it "shows one row per unit and IST group, and none for a waiting list" do
      waiting_list = Group::Unit.create!(name: "YP Warteliste", parent: groups(:root))

      get :index

      names = rows.map { |tr| tr.css("td").first.text.strip }
      expect(names).to include(unit_a.name, unit_b.name, ist_a.name, groups(:ist_b).name)
      expect(names).not_to include(waiting_list.name)
    end

    # One multi-select per group, turned into chips by the shared
    # chips-combobox widget (the data attribute is all it takes).
    it "offers every cost center in one multi-select per group" do
      unit_a.update!(cost_center_numbers: ["A1"])

      get :index

      select = row(unit_a).at_css("select[multiple][data-chips-combobox]")
      expect(select).to be_present
      expect(select["name"]).to eq("cost_center_numbers[#{unit_a.id}][]")
      expect(select.css("option").pluck("value")).to include("A1", "A1-R")
      expect(select.css("option[selected]").pluck("value")).to eq(["A1"])
      expect(row(unit_a).text).to include(cc_a1.display_short_name)
      expect(row(unit_b).css("option[selected]")).to be_empty
    end

    # Every row asks for the same widget; both partials guard themselves, so the
    # page carries the script (and with it the keyboard hints) exactly once.
    it "carries the chips-combobox widget script once" do
      get :index

      expect(response.body.scan("window.WsjrdpChipsCombobox = ").size).to eq(1)
      expect(response.body).to include(
        "Tippen: suchen · ↑↓: markieren · ↵: auswählen, mit leerem Feld: " \
        "übernehmen · ⌫: letzte entfernen · Esc: abbrechen"
      )
    end

    # A cleared select posts nothing of its own, so the hidden field is what
    # carries the empty list.
    it "carries an empty list through a hidden field" do
      get :index

      hidden = row(unit_a).at_css("input[type=hidden]")
      expect(hidden["name"]).to eq("cost_center_numbers[#{unit_a.id}][]")
      expect(hidden["value"]).to eq("")
    end

    it "marks a cost center more than one group claims" do
      unit_a.update!(cost_center_numbers: ["A1"])
      unit_b.update!(cost_center_numbers: ["A1"])

      get :index

      expect(row(unit_a).text).to include(I18n.t("fin.group_cost_centers.also", groups: unit_b.name))
      expect(row(unit_b).text).to include(I18n.t("fin.group_cost_centers.also", groups: unit_a.name))
    end

    it "counts the cost centers no group claims" do
      unit_a.update!(cost_center_numbers: ["A1"])
      unassigned = WsjrdpCostCenter.count - 1

      get :index

      expect(response.body)
        .to include(I18n.t("fin.group_cost_centers.unassigned", count: unassigned))
    end

    it "saves the whole page with one button on one collection form" do
      get :index

      form = body.at_css("form#group-cost-centers-form")
      expect(form["action"]).to eq(fin_admin_group_cost_centers_path)
      expect(form.at_css("input[name=_method]")["value"]).to eq("patch")
      expect(form.css("button[type=submit]").size).to eq(1)
    end

    it "keeps the unsaved hint hidden above and below the table" do
      get :index

      hints = body.css(".group-cost-centers-hint")
      expect(hints.size).to eq(2)
      expect(hints.map { |hint| hint.key?("hidden") }).to eq([true, true])
      expect(hints.text).to include(I18n.t("fin.group_cost_centers.unsaved"))
    end
  end

  describe "update" do
    it "saves the groups whose list changed and leaves the others alone" do
      unit_b.update!(cost_center_numbers: ["A1-R"])

      with_versioning do
        expect do
          patch :update, params: {cost_center_numbers: {
            unit_a.id.to_s => ["", "A1"],
            unit_b.id.to_s => ["", "A1-R"],
            ist_a.id.to_s => ["", "A1-R"]
          }}
        end.to change { group_version_count }.by(2)
      end

      expect(response).to redirect_to(fin_admin_group_cost_centers_path)
      expect(flash[:notice]).to eq(I18n.t("fin.group_cost_centers.saved", count: 2))
      expect(unit_a.reload.cost_center_numbers).to eq(["A1"])
      expect(unit_b.reload.cost_center_numbers).to eq(["A1-R"])
      expect(ist_a.reload.cost_center_numbers).to eq(["A1-R"])
      expect(unit_a.versions.last.changeset).to have_key("cost_center_numbers")
    end

    it "drops blanks and duplicates" do
      patch :update, params: {cost_center_numbers: {unit_a.id.to_s => ["", "A1", " A1 ", "A1-R"]}}

      expect(unit_a.reload.cost_center_numbers).to eq(["A1", "A1-R"])
    end

    it "says so when nothing differs" do
      unit_a.update!(cost_center_numbers: ["A1"])

      with_versioning do
        expect do
          patch :update, params: {cost_center_numbers: {unit_a.id.to_s => ["", "A1"]}}
        end.not_to change { group_version_count }
      end

      expect(flash[:notice]).to eq(I18n.t("fin.group_cost_centers.unchanged"))
    end

    it "refuses an unknown number and saves nothing, not even the valid group" do
      patch :update, params: {cost_center_numbers: {
        unit_a.id.to_s => ["", "A1"],
        unit_b.id.to_s => ["", "Z9"]
      }}

      expect(flash[:alert])
        .to eq(I18n.t("fin.group_cost_centers.unknown_numbers", numbers: "Z9"))
      expect(unit_a.reload.cost_center_numbers).to be_nil
      expect(unit_b.reload.cost_center_numbers).to be_nil
    end

    it "removes the key on an empty selection" do
      unit_a.update!(cost_center_numbers: ["A1"])

      patch :update, params: {cost_center_numbers: {unit_a.id.to_s => [""]}}

      unit_a.reload
      expect(unit_a.cost_center_numbers).to be_nil
      expect(unit_a.additional_info).not_to have_key("cost_center_numbers")
    end

    it "refuses a group the area does not configure and saves nothing" do
      waiting_list = Group::Unit.create!(name: "YP Warteliste", parent: groups(:root))

      patch :update, params: {cost_center_numbers: {
        waiting_list.id.to_s => ["", "A1"],
        unit_a.id.to_s => ["", "A1"]
      }}

      expect(flash[:alert]).to eq(I18n.t("fin.group_cost_centers.unknown_group"))
      expect(waiting_list.reload.cost_center_numbers).to be_nil
      expect(unit_a.reload.cost_center_numbers).to be_nil
    end
  end

  describe "the gate" do
    it "refuses the write tier" do
      sign_in(Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person)

      expect { get :index }.to raise_error(CanCan::AccessDenied)
      expect do
        patch :update, params: {cost_center_numbers: {unit_a.id.to_s => ["", "A1"]}}
      end.to raise_error(CanCan::AccessDenied)
      expect(unit_a.reload.cost_center_numbers).to be_nil
    end
  end
end
