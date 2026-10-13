# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Einstellungen > Ländercodes: the entries of the nationalities with their
# codes, and their switch to codes. Admins only.
describe CountryCodesController, type: :controller do
  render_views

  let(:person) { people(:yp_a_1) }
  # The fixture "admin" leads the root group but has no :admin permission.
  let(:admin) { Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person }

  def page = Nokogiri::HTML(response.body)

  it "lists each entry with its code, and the table of names" do
    sign_in(admin)
    person.update_columns(passport_nationality: "Deutsch, Elbisch")

    get :index

    expect(response).to have_http_status(:ok)
    rows = page.css("table").first.css("tbody tr").map { |row| row.css("td").map { |cell| cell.text.strip } }
    expect(rows.map { |row| [row[1], row[2], row[-3]] }).to include(%w[Deutsch 1 Deutschland], ["Elbisch", "1", "nicht erkannt"])
    role_column = 3 + CountryCodesController::ROLES.index(person.wsjrdp_role)
    expect(rows.find { |row| row[1] == "Elbisch" }[role_column]).to eq("1")
    expect(rows.map(&:first)).to eq((1..rows.size).map(&:to_s))
    expect(page.css("table").last.text).to include("us-amerikanisch", "US")
  end

  it "counts who has a visa and who needs one applied for, with a link to each" do
    sign_in(admin)
    person.update_columns(passport_nationality: "Elbisch", jamboree_data: {"visa_needed" => "yes_need_support"})
    other = people(:yp_a_2)
    other.update_columns(passport_nationality: "Elbisch", jamboree_data: {"visa_needed" => "yes_have_one"})

    get :index

    row = page.css("table.wsjrdp-country-entries tbody tr").find { |tr| tr.css("td")[1].text.strip == "Elbisch" }
    has_one, apply = row.css("td").to_a.last(2)
    expect(has_one.text.squish).to eq("1: #{other.id}")
    expect(apply.text.squish).to eq("1: #{person.id}")
    expect(apply.css("a").pluck("href")).to eq([person_path(person)])

    # Whatever the view: no role chosen, the visa still shows.
    get :index, params: {roles: [""]}
    row = page.css("table.wsjrdp-country-entries tbody tr").find { |tr| tr.css("td")[1].text.strip == "Elbisch" }
    expect(row.css("td").to_a.last(2).map { |cell| cell.text.squish }).to eq(["1: #{other.id}", "1: #{person.id}"])
  end

  it "counts the people without a nationality in a row of their own, last" do
    sign_in(admin)
    person.update_columns(passport_nationality: nil)

    get :index

    last = page.css("table.wsjrdp-country-entries tbody tr").last.css("td").map { |cell| cell.text.strip }
    expect(last[1]).to eq("ohne Nationalität")
    expect(last[2].to_i).to be >= 1
  end

  it "narrows the table to the main nationality and to roles" do
    sign_in(admin)
    person.update_columns(passport_nationality: "Deutsch, Elbisch")

    entries = ->(params) do
      get :index, params: params
      page.css("table.wsjrdp-country-entries tbody tr").map { |row| row.css("td")[1].text.strip }
    end

    expect(entries.call(nationality: "main")).not_to include("Elbisch")
    expect(entries.call(roles: ["", person.wsjrdp_role])).to include("Elbisch")
    expect(entries.call(roles: [""])).to be_empty
  end

  it "shows in a test run what the switch would store, saving nothing" do
    sign_in(admin)
    person.update_columns(passport_nationality: "Deutsch, Elbisch")

    get :index, params: {test_run: 1}

    row = page.css("#test-run ~ table tbody tr").find { |tr| tr.css("td").first.text == person.id.to_s }
    expect(row.css("td").map { |cell| cell.text.strip }.last(3)).to eq(["Deutsch, Elbisch", "DE, Elbisch", "ja"])
    expect(person.reload.passport_nationality).to eq("Deutsch, Elbisch")

    get :index, params: {test_run: 1, hide: %w[unchanged deutsch_de]}
    ids = page.css("#test-run ~ table tbody tr td:first-child").map(&:text)
    expect(ids).to include(person.id.to_s)
    people(:yp_a_2).update_columns(passport_nationality: "Deutsch")
    get :index, params: {test_run: 1, hide: %w[deutsch_de]}
    expect(page.css("#test-run ~ table tbody tr td:first-child").map(&:text)).not_to include(people(:yp_a_2).id.to_s)
  end

  it "switches the known entries to codes, the others stay" do
    sign_in(admin)
    person.update_columns(passport_nationality: "Deutsch, Elbisch")

    unchanged = people(:yp_a_2)
    unchanged.update_columns(passport_nationality: "DE")

    with_versioning { post :migrate }

    expect(response).to redirect_to(country_codes_path)
    expect(person.reload.passport_nationality).to eq("DE, Elbisch")
    expect(unchanged.versions).to be_empty
    expect(person.versions.last).to have_attributes(whodunnit: "1", whodunnit_type: "Person")
    expect(person.versions.last.changeset).to include("passport_nationality" => ["Deutsch, Elbisch", "DE, Elbisch"])
  end

  it "is for admins only" do
    sign_in(people(:ul_a_1))

    expect { get :index }.to raise_error(CanCan::AccessDenied)
    expect { post :migrate }.to raise_error(CanCan::AccessDenied)
  end
end
