# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The lookup behind the admin tab's person search (doc/roles.md -> "The
# finance cap"). Its whole reason to exist is the impersonating case: the
# core's own /people/query asks the impersonated person, who may neither
# query people nor impersonate anybody, so the field stays empty exactly
# where it is needed -- to leave one impersonation for the next.
describe Wsjrdp::ImpersonationQueryController, type: :controller do
  let(:admin) { Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person }
  let(:participant) { people(:yp_a_1) }

  # Both fixture participants of unit A share this last name.
  let(:term) { "UnitA" }

  def results = JSON.parse(response.body)

  context "while impersonating" do
    before do
      sign_in(participant)
      session[:origin_user] = admin.id
    end

    it "answers for the person who logged in" do
      get :index, params: {q: term}

      expect(response).to be_successful
      expect(results).not_to be_empty
      expect(results.first.keys).to include("id", "label")
    end

    it "is refused when the person who logged in may not impersonate" do
      session[:origin_user] = people(:cmt_member1).id

      expect { get :index, params: {q: term} }.to raise_error(CanCan::AccessDenied)
    end
  end

  context "without an impersonation" do
    it "answers whoever may impersonate" do
      sign_in(admin)

      get :index, params: {q: term}

      expect(response).to be_successful
      expect(results).not_to be_empty
    end

    it "refuses whoever may not" do
      sign_in(participant)

      expect { get :index, params: {q: term} }.to raise_error(CanCan::AccessDenied)
    end
  end

  # The core's minimum: anything shorter is not a search.
  it "answers nothing below three characters" do
    sign_in(admin)

    get :index, params: {q: "Un"}

    expect(results).to eq([])
  end

  # Not a general people search: what the request asks to filter by has no say.
  it "filters by :impersonate_user whatever the request says" do
    sign_in(admin)

    get :index, params: {q: term, limit_by_permission: "destroy"}

    expect(controller.send(:limit_by_permission)).to eq("impersonate_user")
    expect(results).not_to be_empty
  end
end
