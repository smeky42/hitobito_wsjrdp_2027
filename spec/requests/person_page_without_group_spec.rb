# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The person's page at /people/:id: shown there in the default group (no
# redirect), and the links to a person's page in the primary group lead there
# (Wsjrdp2027::GroupPersonPaths).
RSpec.describe "The person's page without a group", type: :request do
  let(:admin) { people(:admin) }
  let(:ul) { people(:ul_a_1) }

  before do
    admin.confirm
    sign_in(admin)
  end

  def html = Nokogiri::HTML(response.body)

  it "shows the page at /people/:id in the primary group, without a redirect" do
    get "/people/#{ul.id}"

    expect(response).to have_http_status(:ok)
    expect(html.css("li.active > a").pluck("href")).to include("/people/#{ul.id}")
    expect(response.body).to include(ul.primary_group.to_s)
  end

  it "builds the page's links that take the group from the URL with the default group (tags)" do
    ul.tag_list.add("Beispiel-Tag")
    ul.save!

    get "/people/#{ul.id}"

    expect(response).to have_http_status(:ok)
    expect(html.at_css("a.person-tag-remove[href^='/groups/#{ul.primary_group_id}/people/#{ul.id}/tags']"))
      .to be_present
  end

  it "sends the edit form to the short URL, saves there and comes back to the page" do
    get "/groups/#{ul.primary_group_id}/people/#{ul.id}/edit"
    expect(html.at_css("form[action='/people/#{ul.id}'] input[name='_method'][value='patch']")).to be_present

    patch "/people/#{ul.id}", params: {person: {nickname: "Kurz"}}

    expect(response).to redirect_to("/people/#{ul.id}")
    expect(ul.reload.nickname).to eq("Kurz")
  end

  it "takes Turbo's form submission at the short URL" do
    patch "/people/#{ul.id}", params: {person: {nickname: "Turbo"}},
      headers: {"Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml"}

    expect(ul.reload.nickname).to eq("Turbo")
  end

  # Deleting a person with roles is refused, at the short URL as at the
  # group's (CanCan): the delete reaches the same action either way.
  it "routes a delete at the short URL to the person's destroy" do
    expect(Rails.application.routes.recognize_path("/people/#{ul.id}", method: :delete))
      .to include(controller: "people", action: "destroy", id: ul.id.to_s)
  end

  it "refuses a delete at the short URL as at the group's URL" do
    expect { delete "/people/#{ul.id}" }.to raise_error(CanCan::AccessDenied)
    expect(Person.exists?(ul.id)).to be(true)
  end

  it "refuses a delete at the group's URL" do
    expect { delete "/groups/#{ul.primary_group_id}/people/#{ul.id}" }.to raise_error(CanCan::AccessDenied)
  end

  describe "who sees it" do
    def sign_in_as(person)
      sign_out(admin)
      person.confirm
      sign_in(person)
    end

    it "shows a person's own page" do
      yp = people(:yp_a_1)
      sign_in_as(yp)

      get "/people/#{yp.id}"

      expect(response).to have_http_status(:ok)
    end

    it "shows a unit leader the page of a participant of the unit" do
      sign_in_as(ul)

      get "/people/#{people(:yp_a_1).id}"

      expect(response).to have_http_status(:ok)
    end

    it "sends who is not logged in to the login, and back afterwards" do
      sign_out(admin)

      get "/people/#{ul.id}"

      expect(response).to redirect_to(new_person_session_path)
    end
  end

  it "shows the form again at the short URL when saving fails" do
    patch "/people/#{ul.id}", params: {person: {first_name: "", last_name: "", nickname: "", company_name: ""}}

    expect(response).to have_http_status(422)
    expect(html.at_css("form[action='/people/#{ul.id}']")).to be_present
  end

  it "answers an unknown id as not found and leaves a non-numeric one to the core" do
    expect { get "/people/0" }.to raise_error(ActiveRecord::RecordNotFound)
    expect(Rails.application.routes.recognize_path("/people/abc")).to include(controller: "person/top")
  end

  it "keeps the actions of the page (tags, primary group, roles) at the primary group's URL" do
    ul.tag_list.add("Beispiel-Tag")
    ul.save!

    get "/people/#{ul.id}"

    actions = html.css("a[data-method], form").map { |e| e["href"] || e["action"] }.grep(%r{/people/#{ul.id}/})
    expect(actions).to include(a_string_starting_with("/groups/#{ul.primary_group_id}/people/#{ul.id}/tags"),
      a_string_starting_with("/groups/#{ul.primary_group_id}/people/#{ul.id}/primary_group"))
    expect(actions).to all(start_with("/groups/#{ul.primary_group_id}/people/#{ul.id}/"))
  end

  it "stays in the default group whatever group_id the query string names" do
    Fabricate(Group::Ist::Member.name.to_sym, person: ul, group: groups(:ist_a))

    get "/people/#{ul.id}?group_id=#{groups(:ist_a).id}"

    expect(response).to have_http_status(:ok)
    expect(controller.send(:parent)).to eq(ul.primary_group)
    expect(html.css("li.active > a").pluck("href")).to include("/people/#{ul.id}")
  end

  it "shows the page in the group of the URL, as before" do
    get "/groups/#{ul.primary_group_id}/people/#{ul.id}"

    expect(response).to have_http_status(:ok)
  end

  it "shows the page for a primary group without a role left" do
    Fabricate(Group::Ist::Member.name.to_sym, person: ul, group: groups(:ist_a))
    ul.roles.where(group_id: ul.primary_group_id).delete_all

    get "/people/#{ul.id}"

    expect(response).to have_http_status(:ok)
  end

  it "refuses who may not see the person" do
    other = people(:yp_a_2)
    other.confirm
    sign_in(other)

    expect { get "/people/#{admin.id}" }.to raise_error(CanCan::AccessDenied)
  end

  it "keeps the core's redirect for any other format and the core's /people/... routes" do
    get "/people/#{ul.id}.json"
    expect(response).to redirect_to("/groups/#{ul.primary_group_id}/people/#{ul.id}.json")

    get "/people/#{ul.id}", headers: {"Accept" => "application/json"}
    expect(response).to redirect_to("/groups/#{ul.primary_group_id}/people/#{ul.id}.json")

    expect(Rails.application.routes.recognize_path("/people/query")).to include(controller: "person/query")
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

  it "links the people of a group by the rule: the short URL in their primary group" do
    get "/groups/#{ul.primary_group_id}/people"

    expect(html.at_css("a[href='/people/#{ul.id}']")).to be_present
    expect(html.at_css("a[href='/groups/#{ul.primary_group_id}/people/#{ul.id}']")).to be_nil
  end

  describe Wsjrdp2027::GroupPersonPaths do
    include Rails.application.routes.url_helpers

    let(:other) { groups(:ist_a) }

    it "answers the short path and URL for the primary group, as a record or an id" do
      expect(group_person_path(ul.primary_group, ul)).to eq("/people/#{ul.id}")
      expect(group_person_path(ul.primary_group_id, ul)).to eq("/people/#{ul.id}")
      expect(group_person_path(ul.primary_group, ul, format: :html)).to eq("/people/#{ul.id}")
      expect(group_person_url(ul.primary_group, ul, host: "example.com")).to eq("http://example.com/people/#{ul.id}")
    end

    it "keeps the group's URL for another group, a person given by id, a format or other options" do
      expect(group_person_path(other, ul)).to eq("/groups/#{other.id}/people/#{ul.id}")
      expect(group_person_path(ul.primary_group, ul.id)).to eq("/groups/#{ul.primary_group_id}/people/#{ul.id}")
      expect(group_person_path(ul.primary_group, ul, format: :pdf))
        .to eq("/groups/#{ul.primary_group_id}/people/#{ul.id}.pdf")
      expect(group_person_path(ul.primary_group, ul, returning: true))
        .to eq("/groups/#{ul.primary_group_id}/people/#{ul.id}?returning=true")
      expect(group_person_path(ul.primary_group, ul, format: nil)).to eq("/groups/#{ul.primary_group_id}/people/#{ul.id}")
    end

    it "keeps the group's URL for a person without a primary group" do
      ul.update_columns(primary_group_id: nil)

      expect(group_person_path(other, ul.reload)).to eq("/groups/#{other.id}/people/#{ul.id}")
    end
  end
end
