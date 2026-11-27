# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The pages of a run. The Moss client is a fake: no request leaves the
# process. The data is made up (spec/fixtures/files/moss).
describe Fin::SyncRunsController do
  include SyncSpecHelpers

  before_all(setup_fixtures: true) {}

  let_it_be(:admin) { Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person }
  let(:users_key) { Wsjrdp::Sync::MossApi::Users.key }

  before do
    allow(Wsjrdp::Sync::MossApi).to receive_messages(account_keys: ["default"], credential: nil, credential_source: nil, client: client)
    sign_in(admin)
  end

  def run_with(keys = [users_key])
    Wsjrdp::Sync::Start.new(source: "moss_api", selection: keys, client: client, actor: admin).call
  end

  it "fetches the chosen parts and what they need, then shows the plan" do
    post :create, params: {account_key: "default", parts: [users_key]}

    run = WsjrdpSyncRun.last
    expect(response).to redirect_to(fin_sync_moss_api_run_path(run))
    expect(run.parts.map(&:part_key)).to eq(Wsjrdp::Sync.parts.map(&:key))
    expect(MossUser.count).to eq(0)
  end

  it "refuses an account without a usable version" do
    expect { post :create, params: {account_key: "other", parts: [users_key]} }
      .to raise_error(ActiveRecord::RecordNotFound)
  end

  it "asks again when no known part is chosen" do
    post :create, params: {account_key: "default", parts: ["moss_api.gone"]}

    expect(response).to redirect_to(fin_sync_moss_api_path)
    expect(WsjrdpSyncRun.count).to eq(0)
  end

  it "writes a run once confirmed" do
    run = run_with

    post :apply, params: {id: run.id, confirmed: "1"}

    expect(run.reload.status).to eq("applied")
    expect(MossUser.count).to eq(4)
    expect(flash[:notice]).to be_present
  end

  it "does not write without the second confirmation when there are warnings" do
    apply_first = run_with
    Wsjrdp::Sync::Apply.new(apply_first, actor: admin, confirmed: true, warnings_confirmed: false).call
    lists["users"] = []
    run = run_with

    post :apply, params: {id: run.id, confirmed: "1"}

    expect(run.reload.status).to eq("planned")
    expect(flash[:alert]).to eq(I18n.t("fin.sync.run.refused.warnings_not_confirmed"))
    expect(MossUser.in_moss.count).to eq(4)
  end

  it "cancels a run" do
    run = run_with

    post :cancel, params: {id: run.id}

    expect(run.reload.status).to eq("cancelled")
  end

  it "hands out a file of the run, and none of another run" do
    run = run_with
    other = run_with

    get :file, params: {id: run.id, name: run.parts.last.files.last["name"]}
    expect(response).to be_successful

    expect { get :file, params: {id: run.id, name: other.parts.last.files.last["name"]} }
      .to raise_error(ActiveRecord::RecordNotFound)
  end

  it "refuses the write tier" do
    sign_in(Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person)

    expect { get :show, params: {id: 0} }.to raise_error(CanCan::AccessDenied)
  end

  describe "the run's page" do
    render_views

    it "shows a run's changes and the form that writes it" do
      run = run_with

      get :show, params: {id: run.id}

      expect(response).to be_successful
      expect(response.headers["Cache-Control"]).to include("no-store")
      page = Nokogiri::HTML(response.body)
      parts = page.css("#main tr.exp-row[aria-controls^='sp#{run.id}-']")
      expect(parts.size).to eq(3)
      expect(parts.pluck("aria-expanded").uniq).to eq(["true"]) # every part open on the page
      expect(page.at_css("#sync-apply")).to be_present
      users = run.parts.find_by!(part_key: users_key)
      expect(page.css("tr.exp-row[aria-controls^='sc#{users.id}-']").size).to eq(4)
    end

    it "still shows a part no longer in the registry" do
      run = run_with
      run.parts.last.update_columns(part_key: "moss_api.gone")

      get :show, params: {id: run.id}

      expect(response).to be_successful
      expect(response.body).to include("moss_api.gone")
    end

    it "links a notice's records that are in the table, teams with their status" do
      Wsjrdp::Sync::Apply.new(run_with, actor: admin, confirmed: true, warnings_confirmed: false).call
      lists["teams"].first["departmentId"] = "d0000000-0000-4000-8000-0000000000ff"
      run = run_with

      get :show, params: {id: run.id}

      item = Nokogiri::HTML(response.body).at_css("#main details li")
      expect(item.text.squish).to eq("Team Eins Status: ACTIVE → d0000000-0000-4000-8000-0000000000ff")
      expect(item.css("a").pluck("href").uniq).to eq([moss_team_path(MossTeam.find_by!(name: "Team Eins"))])
    end

    it "puts a notice's chip at the value it is about, and links a person" do
      person = people(:ul_a_1)
      person.update!(moss_email: "ben.muster@example.org")
      run = run_with

      get :show, params: {id: run.id}

      page = Nokogiri::HTML(response.body)
      person_values = page.css("dt").select { |dt| dt["title"] == "person_id" }.map(&:next_element)
      expect(person_values.map { |dd| dd.css(".badge").text }).to include(I18n.t("fin.sync.notice_labels.without_person"))
      expect(person_values.flat_map { |dd| dd.css("a").pluck("href") }).to include(person_path(person))
    end

    it "shows no buttons once a run has ended, also when it ended at once with nothing to do" do
      Wsjrdp::Sync::Apply.new(run_with, actor: admin, confirmed: true, warnings_confirmed: false).call
      run = run_with

      get :show, params: {id: run.id}

      expect(run.reload.status).to eq("unchanged")
      expect(Nokogiri::HTML(response.body).css("#main .btn-primary, #main .btn-outline-secondary")).to be_empty
    end
  end
end
