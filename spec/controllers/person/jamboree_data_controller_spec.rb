# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Zusatzdaten page, as the status page: without a group in the primary
# group, in any group of the URL.
describe Person::JamboreeDataController, type: :controller do
  let(:ul) { people(:ul_a_1) }
  let(:yp) { people(:yp_a_1) }
  let(:ist) { people(:ist_a_1) }

  before { sign_in(people(:admin)) }

  def update(person, attrs) = put(:update, params: {id: person.id, person: attrs})

  it "assigns the primary group without a group in the URL" do
    get :show, params: {id: ul.id}

    expect(response).to have_http_status(:ok)
    expect(assigns(:group)).to eq(ul.primary_group)
  end

  it "routes the short URLs" do
    expect(get: "/people/#{ul.id}/jamboree_data").to route_to("person/jamboree_data#show", id: ul.id.to_s)
    expect(get: "/people/#{ul.id}/jamboree_data/edit").to route_to("person/jamboree_data#edit", id: ul.id.to_s)
    expect(put: "/people/#{ul.id}/jamboree_data").to route_to("person/jamboree_data#update", id: ul.id.to_s)
  end

  describe "#update" do
    it "saves at the short URL and comes back there" do
      update(ul, {nationality: "DE"})

      expect(response).to redirect_to(jamboree_data_person_path(ul))
      expect(ul.reload.nationality).to eq("DE")
    end

    it "saves the journey of an IST" do
      update(ist, {arrival_location: "amber_expo", departure_type: "train"})

      expect(ist.reload).to have_attributes(arrival_location: "amber_expo", departure_type: "train")
    end

    it "keeps the journey of a unit member, whoever edits it" do
      yp.update!(arrival_location: "amber_expo", departure_type: "train")

      update(yp, {arrival_location: "lech_walesa_airport", departure_type: "flight", arrival_date: "2027-07-28",
                  nationality: "DE"})

      expect(yp.reload).to have_attributes(arrival_location: "amber_expo", departure_type: "train",
        arrival_date: nil, nationality: "DE")
    end

    it "lets a person edit their own data, but not their unit's journey" do
      sign_in(ul)

      update(ul, {arrival_location: "amber_expo", nationality: "DE"})

      expect(ul.reload).to have_attributes(arrival_location: nil, nationality: "DE")
    end

    it "keeps the uniform order, size and sleeve length" do
      yp.update!(uniform_size: Settings.uniform_size.first, uniform_long_sleeve: true)

      update(yp, {uniform_order: "false", uniform_size: Settings.uniform_size.last, uniform_long_sleeve: "false"})

      expect(yp.reload).to have_attributes(uniform_order: nil, uniform_size: Settings.uniform_size.first.to_s,
        uniform_long_sleeve: true)
    end

    it "saves a Wohl/Unwohl choice" do
      update(ul, {comfortable_on_water: "false"})

      expect(ul.reload.comfortable_on_water).to be(false)
    end

    it "saves one choice per allergy as the flag and its severity" do
      ul.update_columns(jamboree_data: {"allergy_peanut" => true, "allergy_peanut_severity" => "severe"})

      update(ul, {allergy_egg_level: "mild", allergy_peanut_level: "none"})

      expect(ul.reload).to have_attributes(allergy_egg: true, allergy_egg_severity: "mild", allergy_peanut: false,
        allergy_peanut_severity: nil)
    end

    it "keeps the old visa information" do
      ul.update_columns(jamboree_data: {"visa_information" => "alt"})

      update(ul, {visa_information: "neu", visa_civil_status: "single"})

      expect(ul.reload).to have_attributes(visa_information: "alt", visa_civil_status: "single")
    end

    it "does not accept adult-only answers for YP" do
      update(yp, {mothers_first_name: "Test", french_reading: "basic", prior_wsj_experience: "Test",
                  country_of_birth: "DE"})

      expect(yp.reload).to have_attributes(mothers_first_name: nil, french_reading: nil,
        prior_wsj_experience: nil, country_of_birth: "DE")
    end

    it "stores a chosen country by its code" do
      update(ul, {country_of_birth: "Österreich", visa_other_nationalities_codes: ["", "GB", "FR"]})

      expect(ul.reload).to have_attributes(country_of_birth: "AT", visa_other_nationalities: "GB, FR")
    end

    it "drops an emptied country" do
      ul.update_columns(jamboree_data: {"country_of_birth" => "DE"})

      update(ul, {country_of_birth: ""})

      expect(ul.reload.jamboree_data).not_to have_key("country_of_birth")
    end

    it "keeps a country it does not know" do
      update(ul, {country_of_birth: "Mittelerde"})

      expect(ul.reload.country_of_birth).to eq("Mittelerde")
    end
  end

  describe "the pages" do
    render_views

    def page = Nokogiri::HTML(response.body)

    def edit(person) = get(:edit, params: {id: person.id})

    def show(person) = get(:show, params: {id: person.id})

    def checked_radios
      page.css("input[type=radio][name^='person['][checked]:not([name^='person[uniform_'])" \
        ":not([name^='person[allergy_']):not([name^='person[comfortable_'])")
    end

    it "edits a unit leader's data with the defaults chosen and the journey read-only" do
      ul.update_columns(first_name: "Anna Maria", nickname: nil, passport_nationality: "AT, DE",
        jamboree_data: {"travel_document_type" => "other_travel_document", "country_of_birth" => "Deutschland",
                        "arrival_location" => "amber_expo"})

      edit(ul)

      aggregate_failures do
        expect(page.at_css("form[action='#{jamboree_data_person_path(ul)}']")).to be_present
        expect(page.at_css("[name='person[arrival_location]']")).to be_nil
        expect(page.text).to include("AmberExpo")
        expect(page.at_css("[name='person[uniform_order]']")).to be_nil
        expect(page.text).to include("nicht gewählt (=Ja)")
        expect(page.at_css("input#person_comfortable_on_water_true")["checked"]).to be_present
        expect(page.at_css("select#person_visa_needed option[selected]")&.text).to eq("Nein")
        expect(page.css("select#person_visa_needed option").map(&:text)).not_to include("")
        expect(checked_radios.size).to eq(16)
        expect(page.at_css('[data-jamboree-dependent-value="yes_need_support"]')["hidden"]).not_to be_nil
        expect(page.css("select#person_travel_document_type option").map(&:text)).to start_with("", "Reisepass")
        expect(page.at_css("input[type=hidden][name='person[medical_equipment_needs][]'][value='']")).to be_present
        other_document = page.at_css("input#person_travel_document_other")
        expect([other_document["required"], other_document["disabled"]]).to eq(["required", nil])
        expect(page.at_css("select#person_country_of_birth option[selected]")["value"]).to eq("DE")
        expect(page.at_css("select#person_nationality option[selected]")["value"]).to eq("AT")
        name_tag = page.at_css("input#person_known_as_name")
        expect([name_tag["placeholder"], name_tag["value"]]).to eq([nil, nil])
        expect(page.text).to include("Aktuell dein 1. Vorname: Anna")
      end
    end

    it "edits the visa questions with the template's choices where visa support is needed" do
      ul.update_columns(gender: "w", passport_nationality: "ZA, DE, GB",
        jamboree_data: {"visa_needed" => "yes_need_support", "visa_information" => "alt",
                        "visa_schengen_first_entry" => "US", "country_of_birth" => "Mittelerde",
                        "travel_document_type" => "ordinary_passport", "allergy_peanut" => true,
                        "allergy_peanut_severity" => "severe", "allergy_egg" => true})

      edit(ul)

      aggregate_failures do
        expect(page.at_css('[data-jamboree-dependent-value="yes_need_support"] #person_visa_employer_name')).to be_present
        expect(page.at_css('[data-jamboree-dependent-value="yes_need_support"]')["hidden"]).to be_nil
        expect(page.at_css("select#person_visa_gender_as_in_travel_document option[selected]")&.text)
          .to eq("F – Female (weiblich)")
        expect(page.at_css("input#person_visa_civil_status_other")["disabled"]).to be_present
        expect(page.at_css("select#person_visa_family_eu_citizen_relation")["disabled"]).to be_present
        expect(page.at_css("[name='person[visa_information]']")).to be_nil
        expect(page.css("select#person_visa_other_nationalities_codes[multiple] option[selected]").pluck("value"))
          .to eq(%w[DE GB])
        expect(page.css("select#person_visa_schengen_first_entry option").pluck("value"))
          .to match_array(["", "US", *Wsjrdp::CountryLookup::SCHENGEN_CODES])
        expect(page.at_css("select#person_visa_schengen_first_entry option[selected]").text).to eq("US (nicht erkannt)")
        expect(page.at_css("select#person_country_of_birth option[selected]").text).to eq("Mittelerde (nicht erkannt)")
        expect(page.at_css("input#person_travel_document_other")["disabled"]).to be_present
        expect(page.at_css("input#person_allergy_peanut_level_severe")["checked"]).to be_present
        expect(page.at_css("input#person_allergy_milk_level_none")["checked"]).to be_present
        expect(page.css("input[name='person[allergy_egg_level]'][checked]")).to be_empty
        expect(page.text).to include("Allergie angegeben, aber die Stärke fehlt.")
      end
    end

    it "edits an IST's journey and adult questions, the stored nationality preselected" do
      ist.update_columns(jamboree_data: {"nationality" => "deutsch"})

      edit(ist)

      aggregate_failures do
        expect(page.at_css("select#person_arrival_location")).to be_present
        expect(page.at_css("select#person_departure_type")).to be_present
        expect(page.at_css("#person_mothers_first_name")).to be_present
        expect(page.at_css("#person_french_reading_none")).to be_present
        expect(page.at_css("#person_prior_wsj_experience")).to be_present
        expect(page.at_css("select#person_nationality option[selected]")["value"]).to eq("DE")
      end
    end

    it "edits only a YP's questions, the uniform shown and the birthplace hidden" do
      yp.update!(uniform_size: Settings.uniform_size.first, uniform_long_sleeve: true)

      edit(yp)

      aggregate_failures do
        expect(checked_radios.size).to eq(4)
        %w[mothers_first_name fathers_first_name mothers_surname_at_birth french_reading spanish_reading
          arabic_reading prior_wsj_experience vehicle_registration_number arrival_location].each do |attr|
          expect(page.at_css("#person_#{attr}")).to be_nil
        end
        expect(page.at_css('[data-jamboree-dependent-value="yes_need_support"][hidden] #person_place_of_birth'))
          .to be_present
        expect(page.at_css("[name='person[uniform_size]'], [name='person[uniform_long_sleeve]']")).to be_nil
        expect(page.text).to include("Langarm")
        expect(page.text).not_to include("nicht gewählt (=Ja)")
      end
    end

    it "shows a unit leader's default name tag grey, and links the group's URLs in another group" do
      ul.update_columns(first_name: "Anna Maria", nickname: nil, jamboree_data: {})

      get :show, params: {group_id: groups(:ist_a).id, id: ul.id}

      aggregate_failures do
        name_tag = page.css("dt").find { |dt| dt.text.include?("Rufname") }.next_element
        expect(name_tag.at_css("span.text-muted.fw-light").text).to eq("Anna")
        expect(page.at_css("a[href='#{jamboree_data_edit_group_person_path(groups(:ist_a), ul)}']")).to be_present
      end
    end

    it "shows the visa answers, the countries by name and only the allergies with their severity" do
      ul.update_columns(jamboree_data: {"visa_needed" => "yes_need_support", "visa_information" => "alt",
                                        "visa_other_nationalities" => "GB,FR", "country_of_birth" => "AT",
                                        "allergy_egg" => true, "allergy_egg_severity" => "mild"})

      show(ul)

      aggregate_failures do
        status = page.css("dt").find { |dt| dt.text.include?("Familienstand") }.next_element
        expect(status.at_css("span.text-muted.fw-light").text).to eq("nicht gewählt")
        expect(page.text).not_to include("Visainformationen")
        expect(page.text).to include(Person.human_attribute_name(:visa_employer_name), "Österreich (AT)",
          "Vereinigtes Königreich (GB), Frankreich (FR)", "keine Allergie: Milch, Kasein, Erdnuss")
      end
    end

    it "shows a YP only the questions that apply" do
      show(yp)

      expect(page.text).not_to include("Mutters Vorname", "Französisch", "Frühere Jamboree-Erfahrung",
        Person.human_attribute_name(:visa_employer_name))
      expect(page.text).to include("Englisch", "An- und Abreise")
    end

    it "shows a YP the birthplace and visa details where visa support is needed" do
      yp.update!(visa_needed: "yes_need_support")

      show(yp)

      expect(page.text).to include(Person.human_attribute_name(:place_of_birth),
        Person.human_attribute_name(:visa_employer_name))
    end
  end
end
