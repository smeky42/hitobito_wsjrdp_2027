# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Person::PrimaryRoleController do
  render_views

  let(:ul) { people(:ul_a_1) }
  let(:group) { groups(:unit_a) }
  let(:ist_group) { groups(:ist_a) }
  let(:params) { {group_id: group.id, id: ul.id} }

  context "with access to the status page (:log)" do
    before { sign_in(people(:admin)) }

    it "opens the dialog in its turbo frame: groups under headings, the primary group preselected and marked" do
      get :show, params: params

      frame = Nokogiri::HTML(response.body).at_css("turbo-frame#primary_role_dialog")
      expect(frame).to be_present
      select = frame.at_css("select[name='primary_role_change[group_id]']")
      expect(select.css("optgroup").pluck("label")).to include("CMT", "ISTs", "Units")
      expect(select.at_css("option[selected]")).to be_nil
      expect(select["data-placeholder"]).to eq("bisherige Hauptgruppe: #{group.id} #{group.display_name}")
      expect(JSON.parse(select.at_css("option[value='#{group.id}']")["data-chips"])).to include("bisher")
      expect(frame.text).to include("Wähle neue Hauptgruppe und Rolle")
    end

    it "shows bisher and neu once group and role type are chosen" do
      get :show, params: params.merge(primary_role_change: {group_id: ist_group.id, role_type: "Group::Ist::Member"})

      frame = Nokogiri::HTML(response.body).at_css("turbo-frame#primary_role_dialog")
      expect(frame.text).to include("Bisher", "Neu", "Gruppen und Rollen", "neue Hauptgruppe")
      post_form = frame.at_css("form[method='post']")
      expect(post_form.at_css("input[type=hidden][name='primary_role_change[group_id]']")["value"]).to eq(ist_group.id.to_s)
      expect(post_form.at_css("input[type=hidden][name='primary_role_change[role_type]']")["value"]).to eq("Group::Ist::Member")
      expect(frame.css("[id='primary_role_change_group_id']").size).to eq(1)
    end

    it "sums up the change in a last step before saving, with a warning when the contract no longer fits" do
      ul.update_columns(status: "confirmed", contract_status: "confirmed", contract_confirmed_at: Time.zone.now)
      choice = {group_id: ist_group.id, role_type: "Group::Ist::Member"}
      get :show, params: params.merge(primary_role_change: choice)
      footer = Nokogiri::HTML(response.body).at_css(".modal-footer")
      expect(footer.at_css("button[data-wsjrdp-review]").text).to eq("Hauptgruppe/Rolle wechseln")
      expect(footer.at_css("input[type=submit]")).to be_nil

      get :show, params: params.merge(primary_role_change: choice, review: "1")
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("#primary-role-dialog.wsjrdp-reviewing")).to be_present
      expect(doc.at_css("#wsjrdp-review").text.squish).to include("Prüfen und wechseln", "Beitragsrolle UL → IST")
      expect(doc.at_css(".modal-footer button[data-wsjrdp-back]").text).to eq("Zurück")
      expect(doc.at_css(".modal-footer input[type=submit]")["value"]).to eq("Jetzt wechseln")

      get :show, params: params.merge(primary_role_change: choice.merge(contract: "keep"), review: "1")
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("#wsjrdp-review .alert-danger").text.squish).to include("Der Vertrag bleibt")
      expect(doc.at_css(".modal-footer input[type=submit]")["value"]).to eq("Trotzdem wechseln")
    end

    it "is a page of its own under the status tab, also without a group in the URL" do
      get :show, params: {id: ul.id}

      doc = Nokogiri::HTML(response.body)
      expect(assigns(:group)).to eq(ul.primary_group)
      expect(doc.css("li.active > a").map(&:text).map(&:strip)).to include("Status")
      expect(doc.at_css("script[src*='hitobito_wsjrdp_2027/turbo_stream_actions']")).to be_present
      expect(doc.at_css("form[method='post']")["action"]).to eq(status_primary_role_person_path(ul))
    end

    it "marks the current role among the role types of the primary group" do
      get :show, params: params.merge(primary_role_change: {group_id: group.id})

      option = Nokogiri::HTML(response.body).at_css("select[name='primary_role_change[role_type]'] option[value='Group::Unit::Leader']")
      expect(JSON.parse(option["data-chips"])).to include("bisher")
    end

    it "changes the primary role and sends the page back to the status page" do
      choice = {group_id: ist_group.id, role_type: "Group::Ist::Member", end_roles_chosen: "1",
                end_role_ids: [roles(:ul_a_1).id]}
      post :create, params: params.merge(primary_role_change: choice), format: :turbo_stream

      expect(response.body).to include('action="redirect_top"', status_person_path(ul))
      expect(ul.reload.primary_group).to eq(ist_group)
    end

    it "shows the dialog again with the errors" do
      post :create, params: params.merge(primary_role_change: {group_id: ist_group.id, role_type: "Group::Ist::Member",
                                                               contract: "maybe"})

      expect(response.status).to eq(422)
      expect(response.body).to include("Unbekannte Auswahl beim Vertrag.")
      expect(ul.reload.primary_group).to eq(group)
    end
  end

  context "as the manager of the unit, who may not create roles elsewhere" do
    let(:manager) { Fabricate(Group::Unit::Manager.name.to_sym, group: group).person }

    before { sign_in(manager) }

    it "offers only the groups where the manager may create a role" do
      get :show, params: params

      select = Nokogiri::HTML(response.body).at_css("select[name='primary_role_change[group_id]']")
      offered = select.css("option").pluck("value").compact_blank.map(&:to_i)
      expect(offered).to include(group.id)
      expect(offered).not_to include(ist_group.id)
    end

    it "refuses a change into a group where the manager may not create the role" do
      choice = {group_id: ist_group.id, role_type: "Group::Ist::Member", end_roles_chosen: "1"}

      expect { post :create, params: params.merge(primary_role_change: choice), format: :turbo_stream }
        .to raise_error(CanCan::AccessDenied)
      expect(ul.reload.primary_group).to eq(group)
    end
  end

  it "stays closed without access to the status page" do
    sign_in(people(:yp_a_1))

    expect { get :show, params: params }.to raise_error(CanCan::AccessDenied)
    expect { post :create, params: params }.to raise_error(CanCan::AccessDenied)
  end
end
