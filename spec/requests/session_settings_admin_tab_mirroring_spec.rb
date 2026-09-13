# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# End-to-end mirroring of admin_tab between the session and the login user's
# persisted preference (people.wsjrdp_user_preferences), driven through real
# requests -- what the controller spec, which pokes the session directly,
# cannot show: the persisted side, the seed of a fresh session, and that an
# impersonation writes and reads the person who ACTUALLY logged in, never the
# impersonated one.
#
# store_session_settings is a prepend_before_action on ApplicationController, so
# every authenticated request runs it; a plain GET "/" is trigger enough and the
# 302 it answers with is irrelevant here. The session carries across requests in
# one example via the integration session's cookie jar (active_record_store).
RSpec.describe "admin_tab session/preference mirroring", type: :request do
  let(:user) { Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person }

  # The persisted preference, read back from a fresh load of the row.
  def persisted(person) = Person.find(person.id).wsjrdp_preference_admin_tab

  before do
    user.confirm
    sign_in(user)
  end

  describe "setting it" do
    it "writes the value to both the session and the persisted preference" do
      get "/", params: {admin_tab: "ondemand"}

      expect(session[:admin_tab]).to eq("ondemand")
      expect(persisted(user)).to eq("ondemand")
    end

    it "persists the normalised value, not the raw spelling" do
      get "/", params: {admin_tab: "yes"} # a truthy spelling

      expect(session[:admin_tab]).to eq("always")
      expect(persisted(user)).to eq("always")
    end

    it "leaves an unknown, non-blank value alone: neither stored nor a reset" do
      user.wsjrdp_preference_admin_tab = "always" # persisted beforehand

      get "/", params: {admin_tab: "sometimes"}

      # An invalid param is ignored outright -- it does not seed the session and,
      # crucially, does not clear the persisted preference (that is what a blank
      # would do).
      expect(session[:admin_tab]).to be_nil
      expect(persisted(user)).to eq("always")
    end
  end

  describe "resetting it" do
    it "a blank value clears both the session and the persisted preference" do
      get "/", params: {admin_tab: "always"}
      expect(persisted(user)).to eq("always")

      get "/", params: {admin_tab: ""}

      expect(session[:admin_tab]).to be_nil
      expect(persisted(user)).to be_nil
    end
  end

  describe "seeding a fresh session" do
    it "seeds the session from the persisted preference, without a parameter" do
      user.wsjrdp_preference_admin_tab = "ondemand" # persisted, session still empty

      get "/"

      expect(session[:admin_tab]).to eq("ondemand")
    end

    it "does not re-persist while seeding" do
      user.wsjrdp_preference_admin_tab = "ondemand"

      expect { get "/" }.not_to(change { persisted(user) }.from("ondemand"))
    end
  end

  describe "while impersonating" do
    let(:member) { people(:cmt_member1) }

    before do
      post "/wsjrdp/impersonate", params: {person_id: member.id} # user (origin) now acts as member
      expect(session[:origin_user]).to eq(user.id)
    end

    it "writes the login (origin) user's preference, never the impersonated one's" do
      get "/", params: {admin_tab: "always"}

      expect(persisted(user)).to eq("always") # the admin who logged in
      expect(persisted(member)).to be_nil # not the impersonated member
    end

    it "seeds a fresh session from the origin user's preference" do
      user.wsjrdp_preference_admin_tab = "ondemand" # the origin user's, set after impersonation

      get "/"

      expect(session[:admin_tab]).to eq("ondemand")
    end
  end
end
