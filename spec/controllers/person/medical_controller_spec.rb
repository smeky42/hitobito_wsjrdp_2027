# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The medical page, as the status page: without a group in the primary
# group, in any group of the URL, with the person sheet and its tabs.
describe Person::MedicalController, type: :controller do
  render_views

  let(:ul) { people(:ul_a_1) }

  before { sign_in(people(:admin)) }

  def page = Nokogiri::HTML(response.body)

  it "shows the page at /people/:id/medical with the person's tabs" do
    get :show, params: {id: ul.id}

    expect(response).to have_http_status(:ok)
    expect(assigns(:group)).to eq(ul.primary_group)
    expect(page.css("li.active > a").map(&:text).map(&:strip)).to include("Personen", "Medizin")
    expect(page.at_css("a[href='#{medical_edit_person_path(ul)}']")).to be_present
  end

  it "links the group's URLs in another group" do
    get :show, params: {group_id: groups(:ist_a).id, id: ul.id}

    expect(page.at_css("a[href='#{medical_edit_group_person_path(groups(:ist_a), ul)}']")).to be_present
  end

  it "saves at the short URL and comes back there" do
    get :edit, params: {id: ul.id}
    expect(page.at_css("form[action='#{medical_person_path(ul)}']")).to be_present

    put :update, params: {id: ul.id, person: {medical_allergies: "Heuschnupfen"}}
    expect(response).to redirect_to(medical_person_path(ul))
    expect(ul.reload.medical_allergies).to eq("Heuschnupfen")
  end

  it "saves in another group and comes back to the group's URL" do
    put :update, params: {group_id: groups(:ist_a).id, id: ul.id, person: {medical_allergies: "keine"}}

    expect(response).to redirect_to(medical_group_person_path(groups(:ist_a), ul))
  end
end
