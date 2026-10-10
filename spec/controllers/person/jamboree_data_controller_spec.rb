# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Zusatzdaten page, as the status page: without a group in the primary
# group, in any group of the URL, with the person sheet and its tabs.
describe Person::JamboreeDataController, type: :controller do
  render_views

  let(:ul) { people(:ul_a_1) }

  before { sign_in(people(:admin)) }

  def page = Nokogiri::HTML(response.body)

  it "shows the page at /people/:id/jamboree_data with the person's tabs" do
    get :show, params: {id: ul.id}

    expect(response).to have_http_status(:ok)
    expect(assigns(:group)).to eq(ul.primary_group)
    expect(page.css("li.active > a").map(&:text).map(&:strip)).to include("Personen", "WSJ 2027 Zusatzdaten")
    expect(page.at_css("a[href='#{jamboree_data_edit_person_path(ul)}']")).to be_present
  end

  it "links the group's URLs in another group" do
    get :show, params: {group_id: groups(:ist_a).id, id: ul.id}

    expect(page.at_css("a[href='#{jamboree_data_edit_group_person_path(groups(:ist_a), ul)}']")).to be_present
  end

  it "saves at the short URL and comes back there" do
    get :edit, params: {id: ul.id}
    expect(page.at_css("form[action='#{jamboree_data_person_path(ul)}']")).to be_present

    put :update, params: {id: ul.id, person: {nationality: "deutsch"}}
    expect(response).to redirect_to(jamboree_data_person_path(ul))
    expect(ul.reload.nationality).to eq("deutsch")
  end

  it "offers the selects with an empty choice and German labels" do
    get :edit, params: {id: ul.id}

    select = page.at_css("select#person_travel_document_type")
    expect(select.css("option").map(&:text)).to start_with("", "Reisepass")
    expect(page.at_css("input[type=hidden][name='person[medical_equipment_needs][]'][value='']")).to be_present
  end

  it "chooses Nein for the visa and Keine for each language level when nothing is stored" do
    ul.update_columns(jamboree_data: {})
    get :edit, params: {id: ul.id}

    expect(page.at_css("select#person_visa_needed option[selected]")&.text).to eq("Nein")
    expect(page.css("select#person_visa_needed option").map(&:text)).not_to include("")
    expect(page.at_css("input#person_english_reading_none")["checked"]).to be_present
    expect(page.css("input[type=radio][name^='person['][checked]").size).to eq(16)
  end

  it "routes the short URLs" do
    expect(get: "/people/#{ul.id}/jamboree_data").to route_to("person/jamboree_data#show", id: ul.id.to_s)
    expect(get: "/people/#{ul.id}/jamboree_data/edit").to route_to("person/jamboree_data#edit", id: ul.id.to_s)
    expect(put: "/people/#{ul.id}/jamboree_data").to route_to("person/jamboree_data#update", id: ul.id.to_s)
  end
end
