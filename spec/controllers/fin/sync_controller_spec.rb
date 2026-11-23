# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Synchronisation: three pages, for Admin and the manage tier only.
describe Fin::SyncController do
  render_views

  let(:admin) { Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person }

  def tab_links = Nokogiri::HTML(response.body).css("a").pluck("href").grep(%r{\A/fin/sync})

  %i[index moss_api moss_csv].each do |action|
    it "renders #{action} with the area's three tabs" do
      sign_in(admin)
      get action

      expect(response).to be_successful
      expect(tab_links).to include(fin_sync_moss_api_path, fin_sync_moss_csv_path)
    end
  end

  it "lists the runs, with what they synchronised and how long they took" do
    sign_in(admin)
    WsjrdpSyncRun.create!(source: "moss_api", status: "unchanged", started_at: Time.current, selected_parts: [],
      timings: [{"phase" => "start", "duration_ms" => 1500}])

    get :index

    page = Nokogiri::HTML(response.body)
    rows = page.css("#main tr.exp-row[aria-controls^='sr-']")
    expect(rows.size).to eq(1)
    expect(rows.first.text).to include("Moss API", "1,5 s")
    expect(page.at_css("#main details[open]")).to be_nil # the phases are closed in a row
    expect(page.css("#main .bk-item-detail").text).to include("Status", "Quelle")
  end

  it "opens for a finance manager once the manage tier is picked" do
    sign_in(Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person)
    session[:max_finance_permission] = "finance_manage"

    get :index

    expect(response).to be_successful
  end

  it "deletes the files of old runs" do
    sign_in(admin)
    allow(Wsjrdp::Sync::Purge).to receive(:call).and_return(3)

    post :purge

    expect(response).to redirect_to(fin_sync_path)
    expect(Wsjrdp::Sync::Purge).to have_received(:call)
  end

  it "offers the Moss API parts, all chosen" do
    sign_in(admin)
    allow(Wsjrdp::Sync::MossApi).to receive(:account_keys).and_return(["default"])

    get :moss_api

    page = Nokogiri::HTML(response.body)
    expect(page.css("#sync-choose [data-sync-group]").size).to eq(2) # Moss API, Organisationsstruktur
    boxes = page.css("#sync-choose input[name='parts[]']")
    expect(boxes.pluck("value")).to eq(Wsjrdp::Sync.parts_of(:moss_api).map(&:key))
    expect(boxes.pluck("checked")).to all(be_present)
  end

  it "refuses the write tier" do
    sign_in(Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person)

    expect { get :moss_api }.to raise_error(CanCan::AccessDenied)
  end
end
