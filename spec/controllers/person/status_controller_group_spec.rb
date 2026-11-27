# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The status page belongs to the person: it works without a group in the URL
# (in the primary group), in any group of the URL, and for a primary group
# without a role left.
describe Person::StatusController, type: :controller do
  render_views
  before_all(setup_fixtures: true) do
    WsjrdpPaymentPlan.kept.find_or_create_by!(wsjrdp_role: people(:ul_a_1).wsjrdp_role, single_payment: false,
      payment_method: "direct_debit") { |plan| plan.raw_installments_eur = [2026, 100, 100] }
  end

  let(:ul) { people(:ul_a_1) }
  let(:ist_a) { groups(:ist_a) }

  before { sign_in(people(:admin)) }

  def page = Nokogiri::HTML(response.body)

  def link?(href) = page.at_css("a[href='#{href}']").present?

  it "shows the page at /people/:id/status in the primary group, linking without the group" do
    ul.update_columns(status: "in_review")

    get :show, params: {id: ul.id}

    aggregate_failures do
      expect(response).to have_http_status(:ok)
      expect(assigns(:group)).to eq(ul.primary_group)
      expect(link?(status_person_path(ul))).to be(true)
      expect(link?(status_edit_person_path(ul))).to be(true)
      expect(link?(status_primary_role_person_path(ul))).to be(true)
      expect(link?("/people/#{ul.id}/upload/show_contract")).to be(true)
      expect(link?("/people/#{ul.id}/status/approve_documents")).to be(true)
      expect(page.css("li.active > a").map(&:text).map(&:strip)).to include("Personen", "Status")
    end
  end

  it "shows the page in the group of the URL, linking with the group" do
    ul.update_columns(status: "in_review")

    get :show, params: {group_id: ist_a.id, id: ul.id}

    aggregate_failures do
      expect(response).to have_http_status(:ok)
      expect(assigns(:group)).to eq(ist_a)
      expect(link?(status_group_person_path(ist_a, ul))).to be(true)
      expect(link?(status_edit_group_person_path(ist_a, ul))).to be(true)
      expect(link?("/groups/#{ist_a.id}/people/#{ul.id}/upload/show_contract")).to be(true)
    end
  end

  it "links the edit form without the group where the URL names the primary group" do
    get :show, params: {group_id: ul.primary_group_id, id: ul.id}

    expect(link?(status_edit_person_path(ul))).to be(true)
  end

  it "shows the page for a primary group without a role left" do
    Fabricate(Group::Ist::Member.name.to_sym, person: ul, group: ist_a)
    ul.roles.where(group_id: ul.primary_group_id).delete_all
    get :show, params: {id: ul.id}

    expect(response).to have_http_status(:ok)
  end

  it "edits at /people/:id/status/edit" do
    get :edit, params: {id: ul.id}

    expect(response).to have_http_status(:ok)
    expect(page.at_css("form[action='#{status_person_path(ul)}']")).to be_present
  end

  it "saves at /people/:id/status and comes back to the short URL" do
    put :update, params: {id: ul.id, person: {unit_code: "X1"}}

    expect(response).to redirect_to(status_person_path(ul))
    expect(ul.reload.unit_code).to eq("X1")
  end

  it "approves the documents at the short URL and comes back there" do
    ul.update_columns(status: "in_review")
    post :approve_documents, params: {id: ul.id}

    expect(response).to redirect_to(status_person_path(ul))
    expect(ul.reload.status).to eq("reviewed")
  end

  it "routes the short URLs" do
    expect(get: "/people/#{ul.id}/status").to route_to("person/status#show", id: ul.id.to_s)
    expect(get: "/people/#{ul.id}/status/edit").to route_to("person/status#edit", id: ul.id.to_s)
    expect(put: "/people/#{ul.id}/status").to route_to("person/status#update", id: ul.id.to_s)
    expect(post: "/people/#{ul.id}/status/review_documents").to route_to("person/status#review_documents", id: ul.id.to_s)
    expect(get: "/people/#{ul.id}/upload/show_contract").to route_to("person/upload#show_contract", id: ul.id.to_s)
  end
end
