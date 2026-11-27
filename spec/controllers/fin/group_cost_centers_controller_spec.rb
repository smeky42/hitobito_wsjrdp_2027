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
  before_all(setup_fixtures: true) {}

  let_it_be(:admin) { Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person }
  let(:unit_a) { groups(:unit_a) }
  let(:unit_b) { groups(:unit_b) }
  let(:ist_a) { groups(:ist_a) }

  # Cost-center numbers are alphanumeric, never just digits.
  before_all do
    WsjrdpCostCenter.create!(number: "A1", name: "Kostenstelle A1")
    WsjrdpCostCenter.create!(number: "A1-R", name: "Kostenstelle A1-R")
  end

  def group_version_count = PaperTrail::Version.where(main_type: "Group").count

  before { sign_in(admin) }

  describe "index" do
    it "shows one row per unit and IST group, and none for a waiting list" do
      waiting_list = Group::Unit.create!(name: "YP Warteliste", parent: groups(:root))

      get :index

      expect(controller.send(:groups)).to include(unit_a, unit_b, ist_a, groups(:ist_b))
      expect(controller.send(:groups)).not_to include(waiting_list)
    end

    it "offers every cost center, the stored ones of a group, the shared ones marked, the rest counted" do
      unit_a.update!(cost_center_numbers: ["A1"])
      unit_b.update!(cost_center_numbers: ["A1"])

      get :index

      expect(controller.send(:cost_center_options).map(&:last)).to include("A1", "A1-R")
      expect(controller.send(:shared_numbers_of, unit_a)).to eq([["A1", [unit_b]]])
      expect(controller.send(:shared_numbers_of, ist_a)).to eq([])
      expect(controller.send(:unassigned_cost_center_count)).to eq(WsjrdpCostCenter.count - 1)
    end

    describe "rendered" do
      render_views

      def row(group) = Nokogiri::HTML(response.body).css("table tbody tr").find { |tr| tr.css("td").first.text.strip == group.name }

      # A cleared select posts nothing of its own, so the hidden field is what
      # carries the empty list.
      it "names each select by its group, the stored numbers selected, an empty list carried by a hidden field" do
        unit_a.update!(cost_center_numbers: ["A1"])

        get :index

        select = row(unit_a).at_css("select[multiple][data-chips-combobox]")
        expect(select["name"]).to eq("cost_center_numbers[#{unit_a.id}][]")
        expect(select.css("option[selected]").pluck("value")).to eq(["A1"])
        hidden = row(unit_a).at_css("input[type=hidden]")
        expect(hidden.to_h).to include("name" => "cost_center_numbers[#{unit_a.id}][]", "value" => "")
        expect(response.body.scan("window.WsjrdpChipsCombobox = ").size).to eq(1)
      end
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
