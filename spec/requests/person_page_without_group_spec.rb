# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The routing of the person's page at /people/:id: which formats and
# requests reach it, and which stay the core's.
RSpec.describe "The person's page without a group", type: :request do
  let(:admin) { people(:admin) }
  let(:ul) { people(:ul_a_1) }

  before do
    admin.confirm
    sign_in(admin)
  end

  it "routes a delete, a non-numeric id and the core's other /people/... paths" do
    routes = Rails.application.routes
    aggregate_failures do
      expect(routes.recognize_path("/people/#{ul.id}", method: :delete))
        .to include(controller: "people", action: "destroy", id: ul.id.to_s)
      expect(routes.recognize_path("/people/abc")).to include(controller: "person/top")
      expect(routes.recognize_path("/people/query")).to include(controller: "person/query")
    end
  end

  it "takes Turbo's form submission at the short URL" do
    patch "/people/#{ul.id}", params: {person: {nickname: "Turbo"}},
      headers: {"Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml"}

    expect(ul.reload.nickname).to eq("Turbo")
  end

  it "stays in the default group whatever group_id the query string names" do
    Fabricate(Group::Ist::Member.name.to_sym, person: ul, group: groups(:ist_a))

    get "/people/#{ul.id}?group_id=#{groups(:ist_a).id}"

    expect(response).to have_http_status(:ok)
    expect(controller.send(:parent)).to eq(ul.primary_group)
  end

  it "keeps the core's redirect for the format json" do
    get "/people/#{ul.id}.json"

    expect(response).to redirect_to("/groups/#{ul.primary_group_id}/people/#{ul.id}.json")
  end

  it "keeps the core's redirect for a client that asks for json" do
    get "/people/#{ul.id}", headers: {"Accept" => "application/json"}

    expect(response).to redirect_to("/groups/#{ul.primary_group_id}/people/#{ul.id}.json")
  end

  # curl, fetch and the like ask for */*; a client may also ask for a type
  # nobody registered. Neither must loop between the page and the core's
  # redirect.
  it "shows the page to a client that asks for */*, without a redirect" do
    get "/people/#{ul.id}", headers: {"Accept" => "*/*"}

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/html")
  end

  # One example each: the session is logged out after a raised request.
  it "refuses an unknown format at the short URL" do
    expect { get "/people/#{ul.id}", headers: {"Accept" => "foo/bar"} }
      .to raise_error(ActionController::UnknownFormat)
  end

  it "refuses an unknown format at the group's URL the same way" do
    expect { get "/groups/#{ul.primary_group_id}/people/#{ul.id}", headers: {"Accept" => "foo/bar"} }
      .to raise_error(ActionController::UnknownFormat)
  end

  it "sends a client that asks for */* from the start page to the group's URL, as before" do
    get "/", headers: {"Accept" => "*/*"}

    expect(response).to redirect_to("/groups/#{admin.primary_group_id}/people/#{admin.id}")
  end

  it "starts after the login at the short URL" do
    get "/"

    expect(response).to redirect_to("/people/#{admin.id}")
  end
end
