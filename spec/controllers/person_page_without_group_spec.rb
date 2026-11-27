# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The person's page at /people/:id, without a group in the path: shown in
# the default group, its links and forms pointing at the short URL.
describe PeopleController do
  let(:admin) { people(:admin) }
  let(:ul) { people(:ul_a_1) }

  def html = Capybara.string(response.body)

  before { sign_in(admin) }

  it "shows the page in the primary group" do
    get :show, params: {id: ul.id}

    expect(response).to have_http_status(:ok)
    expect(assigns(:group)).to eq(ul.primary_group)
  end

  it "shows the page for a primary group without a role left" do
    Fabricate(Group::Ist::Member.name.to_sym, person: ul, group: groups(:ist_a))
    ul.roles.where(group_id: ul.primary_group_id).delete_all

    get :show, params: {id: ul.id}

    expect(response).to have_http_status(:ok)
  end

  it "shows the page in the group of the URL" do
    get :show, params: {group_id: ul.primary_group_id, id: ul.id}

    expect(response).to have_http_status(:ok)
  end

  it "answers an unknown id as not found" do
    expect { get :show, params: {id: 0} }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "saves at the short URL and comes back to the page" do
    patch :update, params: {id: ul.id, person: {nickname: "Kurz"}}

    expect(response).to redirect_to("/people/#{ul.id}")
    expect(ul.reload.nickname).to eq("Kurz")
  end

  # Deleting a person with roles is refused (CanCan).
  it "refuses a delete at the short URL and at the group's URL" do
    expect { delete :destroy, params: {id: ul.id} }.to raise_error(CanCan::AccessDenied)
    expect { delete :destroy, params: {group_id: ul.primary_group_id, id: ul.id} }
      .to raise_error(CanCan::AccessDenied)
    expect(Person.exists?(ul.id)).to be(true)
  end

  describe "who sees it" do
    it "shows a person's own page" do
      yp = people(:yp_a_1)
      sign_in(yp)

      get :show, params: {id: yp.id}

      expect(response).to have_http_status(:ok)
    end

    it "shows a unit leader the page of a participant of the unit" do
      sign_in(ul)

      get :show, params: {id: people(:yp_a_1).id}

      expect(response).to have_http_status(:ok)
    end

    it "refuses who may not see the person" do
      sign_in(people(:yp_a_2))

      expect { get :show, params: {id: admin.id} }.to raise_error(CanCan::AccessDenied)
    end

    it "sends who is not logged in to the login" do
      sign_out(admin)

      get :show, params: {id: ul.id}

      expect(response).to redirect_to(new_person_session_path)
    end
  end

  # The links and forms are built by the page from the group of the URL.
  describe "the page's links" do
    render_views

    it "keeps the actions of the page (tags, primary group) at the primary group's URL" do
      ul.tag_list.add("Beispiel-Tag")
      ul.save!

      get :show, params: {id: ul.id}

      actions = html.all("a[data-method], form", visible: :all).map { |e| e["href"] || e["action"] }
        .grep(%r{/people/#{ul.id}/})
      expect(actions).to include(a_string_starting_with("/groups/#{ul.primary_group_id}/people/#{ul.id}/tags"),
        a_string_starting_with("/groups/#{ul.primary_group_id}/people/#{ul.id}/primary_group"))
      expect(actions).to all(start_with("/groups/#{ul.primary_group_id}/people/#{ul.id}/"))
    end

    it "sends the edit form to the short URL" do
      get :edit, params: {group_id: ul.primary_group_id, id: ul.id}

      expect(html).to have_css("form[action='/people/#{ul.id}'] input[name='_method'][value='patch']", visible: :all)
    end

    it "shows the form again at the short URL when saving fails" do
      patch :update, params: {id: ul.id, person: {first_name: "", last_name: "", nickname: "", company_name: ""}}

      expect(response).to have_http_status(422)
      expect(html).to have_css("form[action='/people/#{ul.id}']")
    end

    it "links the people of a group by the short URL in their primary group" do
      get :index, params: {group_id: ul.primary_group_id}

      expect(html).to have_css("a[href='/people/#{ul.id}']")
      expect(html).to have_no_css("a[href='/groups/#{ul.primary_group_id}/people/#{ul.id}']")
    end
  end
end
