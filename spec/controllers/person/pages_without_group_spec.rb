# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The print, upload, unit, history, log and security pages belong to the
# person, as the status page does (status_controller_group_spec): they work
# without a group in the URL (in the primary group), in any group of the URL,
# and their tabs link the short URL in the primary group.
shared_examples "a person page without a group" do |page, action|
  let(:ul) { people(:ul_a_1) }
  let(:short_path) { "/people/#{ul.id}/#{page}" }

  # A role in the other group too: the core's history, log and security
  # pages find the person among the people of the URL's group.
  before_all { Fabricate(Group::Ist::Member.name.to_sym, person: people(:ul_a_1), group: groups(:ist_a)) }

  before { sign_in(people(:admin)) }

  context "rendered" do
    render_views

    it "shows the page at /people/:id/#{page} in the primary group, its tab at the short URL" do
      get action, params: {id: ul.id}

      expect(response).to have_http_status(:ok)
      expect(assigns(:group)).to eq(ul.primary_group)
      expect(Nokogiri::HTML(response.body).css("li.active > a").pluck("href")).to include(short_path)
    end
  end

  it "shows the page in the group of the URL" do
    get action, params: {group_id: groups(:ist_a).id, id: ul.id}

    expect(response).to have_http_status(:ok)
    expect(assigns(:group)).to eq(groups(:ist_a))
  end

  it "shows the page for a primary group without a role left" do
    ul.roles.where(group_id: ul.primary_group_id).delete_all

    get action, params: {id: ul.id}

    expect(response).to have_http_status(:ok)
  end

  it "shows the page in a group with a role for a person without a primary group" do
    ul.update_columns(primary_group_id: nil)

    get action, params: {id: ul.id}

    expect(response).to have_http_status(:ok)
    # One of the person's groups (the core's groups.first has no order).
    expect(ul.reload.groups.map(&:id)).to include(assigns(:group).id)
  end

  it "routes the short URL" do
    expect(get: short_path).to route_to("person/#{described_class.controller_path.split("/").last}##{action}",
      id: ul.id.to_s)
  end
end

describe Person::PrintController, type: :controller do
  before_all(setup_fixtures: true) {}

  it_behaves_like "a person page without a group", "print", :index

  context "rendered" do
    render_views

    it "links the print buttons and the form without the group in the primary group" do
      sign_in(people(:admin))
      ul = people(:ul_a_1)
      ul.update_columns(status: "printed", generated_registration_pdf: "/x/registration.pdf")
      get :index, params: {id: ul.id}

      page = Nokogiri::HTML(response.body)
      expect(page.at_css("form[action='/people/#{ul.id}/print']")).to be_present
      expect(page.at_css("a[href='/people/#{ul.id}/upload/show_registration_generated']")).to be_present
    end
  end
end

describe Person::UploadController, type: :controller do
  before_all(setup_fixtures: true) {}

  let(:ul) { people(:ul_a_1) }

  before do
    sign_in(people(:admin))
    ul.update_columns(status: "printed")
  end

  it_behaves_like "a person page without a group", "upload", :index

  context "rendered" do
    render_views

    it "posts the form to the short URL" do
      get :index, params: {id: ul.id}

      expect(Nokogiri::HTML(response.body).at_css("form[action='/people/#{ul.id}/upload']")).to be_present
    end
  end

  it "comes back to the short URL" do
    put :index, params: {id: ul.id}

    expect(response).to redirect_to("/people/#{ul.id}/upload")
  end

  it "routes the short form, delete and the generated registration" do
    expect(put: "/people/1/upload").to route_to("person/upload#index", id: "1")
    expect(delete: "/people/1/upload/delete/upload_sepa_pdf")
      .to route_to("person/upload#destroy", id: "1", what: "upload_sepa_pdf")
    expect(get: "/people/1/upload/show_registration_generated")
      .to route_to("person/upload#show_registration_generated", id: "1")
  end
end

describe Person::UnitController, type: :controller do
  before_all(setup_fixtures: true) {}

  it_behaves_like "a person page without a group", "unit", :show

  it "routes the cluster actions at the short URL" do
    expect(post: "/people/1/unit/fill_cluster_code").to route_to("person/unit#fill_cluster_code", id: "1")
    expect(post: "/people/1/unit/clear_cluster_code").to route_to("person/unit#clear_cluster_code", id: "1")
  end
end

describe Person::HistoryController, type: :controller do
  before_all(setup_fixtures: true) {}

  it_behaves_like "a person page without a group", "history", :index
end

describe Person::LogController, type: :controller do
  before_all(setup_fixtures: true) {}

  it_behaves_like "a person page without a group", "log", :index
end

describe Person::SecurityToolsController, type: :controller do
  before_all(setup_fixtures: true) {}

  it_behaves_like "a person page without a group", "security_tools", :index

  describe "blocking" do
    let(:ul) { people(:ul_a_1) }

    before do
      sign_in(people(:admin))
      Fabricate(Group::Ist::Member.name.to_sym, person: ul, group: groups(:ist_a))
    end

    it "comes back to the short URL in the primary group" do
      post :block_person, params: {group_id: ul.primary_group_id, id: ul.id}

      expect(response).to redirect_to("/people/#{ul.id}/security_tools")
    end

    it "comes back to the group's URL elsewhere" do
      post :unblock_person, params: {group_id: groups(:ist_a).id, id: ul.id}

      expect(response).to redirect_to("/groups/#{groups(:ist_a).id}/people/#{ul.id}/security_tools")
    end
  end
end
