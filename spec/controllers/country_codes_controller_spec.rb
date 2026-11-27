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
  before_all(setup_fixtures: true) {}

  let(:person) { people(:yp_a_1) }

  # The fixture "admin" leads the root group but has no :admin permission.
  let_it_be(:admin) { Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person }

  before { sign_in(admin) }

  def entry_names = assigns(:entries).map(&:first)

  def entry(name) = assigns(:entries).find { |row| row.first == name }

  describe "the page" do
    render_views

    def page = Nokogiri::HTML(response.body)

    it "lists each entry with its code, and the table of names" do
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
      person.update_columns(passport_nationality: "Elbisch", jamboree_data: {"visa_needed" => "yes_need_support"})
      other = people(:yp_a_2)
      other.update_columns(passport_nationality: "Elbisch", jamboree_data: {"visa_needed" => "yes_have_one"})

      get :index

      row = page.css("table.wsjrdp-country-entries tbody tr").find { |tr| tr.css("td")[1].text.strip == "Elbisch" }
      has_one, apply = row.css("td").to_a.last(2)
      expect(has_one.text.squish).to eq("1: #{other.id}")
      expect(apply.text.squish).to eq("1: #{person.id}")
      expect(apply.css("a").pluck("href")).to eq([person_path(person)])
    end
  end

  it "counts the visas whatever the view, also with no role chosen" do
    person.update_columns(passport_nationality: "Elbisch", jamboree_data: {"visa_needed" => "yes_need_support"})

    get :index, params: {roles: [""]}

    expect(entry("Elbisch").last).to eq([person])
  end

  it "counts the people without a nationality in a row of their own, last" do
    person.update_columns(passport_nationality: nil)

    get :index

    expect(assigns(:entries).last.first(2)).to match([nil, be >= 1])
  end

  it "narrows the table to the main nationality and to roles" do
    person.update_columns(passport_nationality: "Deutsch, Elbisch")

    entries = ->(params) do
      get :index, params: params
      entry_names
    end

    expect(entries.call(nationality: "main")).not_to include("Elbisch")
    expect(entries.call(roles: ["", person.wsjrdp_role])).to include("Elbisch")
    expect(entries.call(roles: [""])).to be_empty
  end

  it "shows in a test run what the switch would store, saving nothing" do
    person.update_columns(passport_nationality: "Deutsch, Elbisch")
    test_run = ->(params) do
      get :index, params: {test_run: 1, **params}
      assigns(:test_run)
    end

    expect(test_run.call({})).to include([person, "Deutsch, Elbisch", "DE, Elbisch"])
    expect(person.reload.passport_nationality).to eq("Deutsch, Elbisch")
    expect(test_run.call(hide: %w[unchanged deutsch_de]).map(&:first)).to include(person)
    people(:yp_a_2).update_columns(passport_nationality: "Deutsch")
    expect(test_run.call(hide: %w[deutsch_de]).map(&:first)).not_to include(people(:yp_a_2))
  end

  it "switches the known entries to codes, the others stay" do
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
