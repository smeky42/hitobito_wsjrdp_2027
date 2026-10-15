# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Zusatzdaten page, as the status page: without a group in the primary
# group, in any group of the URL, with the person sheet and its tabs.
describe Person::JamboreeDataController, type: :controller do
  render_views

  let(:ul) { people(:ul_a_1) }
  let(:yp) { people(:yp_a_1) }

  before { sign_in(people(:admin)) }

  def page = Nokogiri::HTML(response.body)

  it "shows the page at /people/:id/jamboree_data with the person's tabs" do
    get :show, params: {id: ul.id}

    expect(response).to have_http_status(:ok)
    expect(assigns(:group)).to eq(ul.primary_group)
    expect(page.css("li.active > a").map(&:text).map(&:strip)).to include("Personen", "Daten für den Veranstalter")
    expect(page.at_css("a[href='#{jamboree_data_edit_person_path(ul)}']")).to be_present
  end

  it "links the group's URLs in another group" do
    get :show, params: {group_id: groups(:ist_a).id, id: ul.id}

    expect(page.at_css("a[href='#{jamboree_data_edit_group_person_path(groups(:ist_a), ul)}']")).to be_present
  end

  it "saves at the short URL and comes back there" do
    get :edit, params: {id: ul.id}
    expect(page.at_css("form[action='#{jamboree_data_person_path(ul)}']")).to be_present

    put :update, params: {id: ul.id, person: {nationality: "DE"}}
    expect(response).to redirect_to(jamboree_data_person_path(ul))
    expect(ul.reload.nationality).to eq("DE")
  end

  it "shows and updates journey fields for a user with log access" do
    ist = people(:ist_a_1)
    get :edit, params: {id: ist.id}
    expect(page.at_css("select#person_arrival_location")).to be_present
    expect(page.at_css("select#person_departure_type")).to be_present
    expect(page.text).to include("Trage deine An- und Abreise ein sobald du dies für dich geklärt hast. Es ist nicht notwendig alles sofort einzutragen.")

    put :update, params: {id: ist.id, person: {arrival_location: "amber_expo", departure_type: "train"}}
    expect(ist.reload).to have_attributes(arrival_location: "amber_expo", departure_type: "train")

    get :show, params: {id: ist.id}
    expect(page.text).to include("AmberExpo", "Zug", "Trage deine An- und Abreise ein sobald du dies für dich geklärt hast.")
  end

  it "keeps UL and YP journeys read-only even for authorized editors" do
    [ul, yp].each do |unit_member|
      unit_member.update!(arrival_location: "amber_expo", departure_type: "train")
      get :edit, params: {id: unit_member.id}
      expect(page.text).to include("AmberExpo", "Zug",
        "Deine An- und Abreise wird zentral von der Logistik gebucht und kann deswegen von dir nicht bearbeitet werden. Wir melden uns bei dir sobald wir wissen wie deine Unit reist.")
      expect(page.at_css("#person_arrival_location")).to be_nil
      expect(page.at_css("#person_departure_type")).to be_nil
      expect(page.at_css("[name='person[arrival_location]']")).to be_nil

      put :update, params: {id: unit_member.id, person: {
        arrival_location: "lech_walesa_airport",
        departure_type: "flight", arrival_date: "2027-07-28", nationality: "DE"
      }}
      expect(unit_member.reload).to have_attributes(arrival_location: "amber_expo", departure_type: "train",
        arrival_date: nil, nationality: "DE")

      get :show, params: {id: unit_member.id}
      expect(page.text).to include("AmberExpo", "Zug", "Deine An- und Abreise wird zentral von der Logistik gebucht")
    end
  end

  it "lets a person see and edit their own data, but not their unit's journey" do
    sign_in(ul)
    get :show, params: {id: ul.id}
    expect(response).to have_http_status(:ok)
    get :edit, params: {id: ul.id}
    expect(response).to have_http_status(:ok)

    put :update, params: {id: ul.id, person: {arrival_location: "amber_expo", nationality: "DE"}}
    expect(ul.reload).to have_attributes(arrival_location: nil, nationality: "DE")
  end

  it "asks only the adults to order a uniform, Langarm and Ja ticked without an answer" do
    get :edit, params: {id: ul.id}
    expect(page.at_css("input#person_uniform_order_true")["checked"]).to be_present
    expect(page.at_css("input#person_uniform_long_sleeve_true")["checked"]).to be_present

    get :edit, params: {id: yp.id}
    expect(page.at_css("[name='person[uniform_order]']")).to be_nil

    put :update, params: {id: yp.id, person: {uniform_order: "false", uniform_long_sleeve: "false"}}
    expect(yp.reload).to have_attributes(uniform_order: nil, uniform_long_sleeve: false)
  end

  it "offers defaulted Wohl/Unwohl choices and explains when to choose Unwohl" do
    get :edit, params: {id: ul.id}

    expect(page.at_css("input#person_comfortable_on_water_true")["checked"]).to be_present
    expect(page.css("input[name='person[comfortable_on_water]']").pluck("value")).to eq(%w[true false])
    expect(page.text).to include("Ich fühle mich bei Aktivitäten auf dem Wasser", "wohl", "unwohl",
      "Bitte wähle \"unwohl\" nur aus, wenn du Aktivitäten und Situationen vermeiden möchtest, bei denen diese Umstände auftreten.")

    put :update, params: {id: ul.id, person: {comfortable_on_water: "false"}}
    expect(ul.reload.comfortable_on_water).to be(false)
  end

  it "shows the default name tag grey with where it comes from, the form without a placeholder" do
    ul.update_columns(first_name: "Anna Maria", nickname: nil, jamboree_data: {})

    get :show, params: {id: ul.id}
    name_tag = page.css("dt").find { |dt| dt.text.include?("Rufname") }.next_element
    expect(name_tag.at_css("span.text-muted.fw-light").text).to eq("Anna")
    expect(page.text).to include("nicht gewählt. Wir nehmen beim Datenexport deinen Spitznamen (wenn eingetragen) " \
      "oder deinen 1. Vornamen. Aktuell dein 1. Vorname")
    expect(page.text).not_to include("Leer lassen für Spitzname bzw. Vorname.")

    get :edit, params: {id: ul.id}
    expect(page.at_css("input#person_known_as_name")["placeholder"]).to be_nil
    expect(page.at_css("input#person_known_as_name")["value"]).to be_blank
    expect(page.text).to include("Wenn das Feld leer bleibt, nehmen wir beim Datenexport deinen Spitznamen " \
      "(wenn eingetragen) oder deinen 1. Vornamen. Aktuell dein 1. Vorname: Anna")
  end

  it "offers one choice per allergy and shows only the allergies with their severity" do
    ul.update_columns(jamboree_data: {"allergy_peanut" => true, "allergy_peanut_severity" => "severe", "allergy_egg" => true})

    get :edit, params: {id: ul.id}
    expect(page.at_css("input#person_allergy_peanut_level_severe")["checked"]).to be_present
    expect(page.at_css("input#person_allergy_milk_level_none")["checked"]).to be_present
    expect(page.css("input[name='person[allergy_egg_level]'][checked]")).to be_empty
    expect(page.text).to include("Allergie angegeben, aber die Stärke fehlt.", "schwer: Schwere anaphylaktische Reaktion")

    put :update, params: {id: ul.id, person: {allergy_egg_level: "mild", allergy_peanut_level: "none"}}
    expect(ul.reload).to have_attributes(allergy_egg: true, allergy_egg_severity: "mild", allergy_peanut: false,
      allergy_peanut_severity: nil)

    get :show, params: {id: ul.id}
    expect(page.text).to include("Ei", "mild", "keine Allergie: Milch, Kasein, Erdnuss")
  end

  it "requires the other travel document only while it is chosen, disabled otherwise" do
    ul.update_columns(jamboree_data: {"travel_document_type" => "ordinary_passport"})
    get :edit, params: {id: ul.id}
    field = page.at_css("input#person_travel_document_other")
    expect(field).to have_attributes(attributes: include("required", "disabled"))

    ul.update_columns(jamboree_data: {"travel_document_type" => "other_travel_document"})
    get :edit, params: {id: ul.id}
    field = page.at_css("input#person_travel_document_other")
    expect(field["required"]).to be_present
    expect(field["disabled"]).to be_nil
  end

  it "asks the visa questions with the template's choices, without the old visa information" do
    ul.update_columns(gender: "w", jamboree_data: {"visa_needed" => "yes_need_support", "visa_information" => "alt"})

    get :edit, params: {id: ul.id}
    expect(page.at_css("select#person_visa_gender_as_in_travel_document option[selected]")&.text).to eq("F – Female (weiblich)")
    expect(page.css("select#person_visa_civil_status option").map(&:text)).to start_with("", "Single (ledig)")
    expect(page.at_css("input#person_visa_civil_status_other")).to have_attributes(attributes: include("disabled"))
    expect(page.css("input[name='person[visa_current_student_status]'][type=radio]").size).to eq(2)
    expect(page.css("input[name='person[visa_family_eu_citizen_relationship]'][type=radio]").size).to eq(2)
    expect(page.at_css("[name='person[visa_information]']")).to be_nil
    expect(page.at_css("select#person_visa_family_eu_citizen_relation")).to have_attributes(attributes: include("disabled"))
    expect(page.at_css("input#person_visa_family_eu_citizen_relation_other")).to have_attributes(attributes: include("disabled"))

    get :show, params: {id: ul.id}
    status = page.css("dt").find { |dt| dt.text.include?("Familienstand") }.next_element
    expect(status.at_css("span.text-muted.fw-light").text).to eq("nicht gewählt")
    expect(page.text).not_to include("Visainformationen")

    put :update, params: {id: ul.id, person: {visa_information: "neu", visa_civil_status: "single"}}
    expect(ul.reload).to have_attributes(visa_information: "alt", visa_civil_status: "single")
  end

  it "offers the selects with an empty choice and German labels" do
    get :edit, params: {id: ul.id}

    select = page.at_css("select#person_travel_document_type")
    expect(select.css("option").map(&:text)).to start_with("", "Reisepass", "Personalausweis")
    expect(page.at_css("input[type=hidden][name='person[medical_equipment_needs][]'][value='']")).to be_present
  end

  it "chooses Nein for the visa and Keine for each language level when nothing is stored" do
    ul.update_columns(jamboree_data: {})
    get :edit, params: {id: ul.id}

    expect(page.at_css("select#person_visa_needed option[selected]")&.text).to eq("Nein")
    expect(page.css("select#person_visa_needed option").map(&:text)).not_to include("")
    expect(page.at_css("input#person_english_reading_none")["checked"]).to be_present
    expect(page.css("input[type=radio][name^='person['][checked]:not([name^='person[uniform_']):not([name^='person[allergy_']):not([name^='person[comfortable_'])").size).to eq(16)
  end

  it "shows YP only their applicable questions in the form and on the page" do
    get :edit, params: {id: yp.id}
    expect(page.at_css("#person_english_reading_none")).to be_present
    expect(page.css("input[type=radio][name^='person['][checked]:not([name^='person[uniform_']):not([name^='person[allergy_']):not([name^='person[comfortable_'])").size).to eq(4)
    %w[mothers_first_name fathers_first_name mothers_surname_at_birth
      french_reading spanish_reading arabic_reading prior_wsj_experience vehicle_registration_number].each do |attr|
      expect(page.at_css("#person_#{attr}")).to be_nil
    end
    expect(page.at_css("#person_place_of_birth").ancestors("[data-jamboree-dependent-value]")).to be_present
    expect(page.at_css("#person_arrival_location")).to be_nil

    get :show, params: {id: yp.id}
    expect(page.text).not_to include("Mutters Vorname", "Französisch", "Frühere Jamboree-Erfahrung")
    expect(page.text).to include("Englisch", "An- und Abreise")
  end

  it "does not accept adult-only answers for YP" do
    put :update, params: {id: yp.id, person: {
      mothers_first_name: "Test", french_reading: "basic",
      prior_wsj_experience: "Test", country_of_birth: "DE"
    }}

    expect(yp.reload).to have_attributes(mothers_first_name: nil, french_reading: nil,
      prior_wsj_experience: nil, country_of_birth: "DE")
  end

  it "keeps adult questions for IST and CMT" do
    [people(:ist_a_1), people(:cmt_leader)].each do |adult|
      get :edit, params: {id: adult.id}
      expect(page.at_css("#person_mothers_first_name")).to be_present
      expect(page.at_css("#person_french_reading_none")).to be_present
      expect(page.at_css("#person_prior_wsj_experience")).to be_present
      expect(page.at_css("#person_arrival_location")).to be_present
      expect(page.text).to include("Trage deine An- und Abreise ein sobald du dies für dich geklärt hast.")
    end
  end

  it "hides visa details on the read-only page without visa support" do
    get :show, params: {id: yp.id}
    expect(page.text).not_to include(Person.human_attribute_name(:visa_employer_name))

    yp.update!(visa_needed: "yes_need_support")
    get :show, params: {id: yp.id}
    expect(page.text).to include(Person.human_attribute_name(:visa_employer_name))
  end

  it "asks YP for their birthplace only when visa support is needed" do
    get :edit, params: {id: yp.id}
    expect(page.at_css("#person_place_of_birth")).to be_present
    expect(page.at_css("#person_place_of_birth").ancestors("[data-jamboree-dependent-value]").first["hidden"]).not_to be_nil

    yp.update!(visa_needed: "yes_need_support")
    get :edit, params: {id: yp.id}
    expect(page.at_css("#person_place_of_birth").ancestors("[data-jamboree-dependent-value]").first["hidden"]).to be_nil
    get :show, params: {id: yp.id}
    expect(page.text).to include(Person.human_attribute_name(:place_of_birth))
  end

  it "shows visa application fields only when visa support is needed" do
    get :edit, params: {id: ul.id}
    visa_fields = page.at_css('[data-jamboree-dependent-value="yes_need_support"]')
    expect(visa_fields["hidden"]).not_to be_nil

    ul.update!(visa_needed: "yes_need_support")
    get :edit, params: {id: ul.id}
    visa_fields = page.at_css('[data-jamboree-dependent-value="yes_need_support"]')
    expect(visa_fields["hidden"]).to be_nil
    expect(visa_fields.at_css("#person_visa_employer_name")).to be_present
  end

  it "chooses the country of birth from the country list and stores its code" do
    ul.update_columns(jamboree_data: {"country_of_birth" => "Deutschland"})
    get :edit, params: {id: ul.id}
    select = page.at_css("select#person_country_of_birth[data-country-select]")
    expect(select["multiple"]).to be_nil
    expect(select.at_css("option[selected]")["value"]).to eq("DE")
    expect(select.css("option").first["value"]).to eq("")

    put :update, params: {id: ul.id, person: {country_of_birth: "Österreich"}}
    expect(ul.reload.country_of_birth).to eq("AT")
    get :show, params: {id: ul.id}
    expect(page.text).to include("Österreich (AT)")

    put :update, params: {id: ul.id, person: {country_of_birth: ""}}
    expect(ul.reload.jamboree_data).not_to have_key("country_of_birth")
  end

  it "preselects the main nationality of the registration while no nationality is stored" do
    ul.update_columns(passport_nationality: "AT, DE", jamboree_data: {})
    get :edit, params: {id: ul.id}
    expect(page.at_css("select#person_nationality[data-country-select] option[selected]")["value"]).to eq("AT")

    ul.update_columns(jamboree_data: {"nationality" => "deutsch"})
    get :edit, params: {id: ul.id}
    expect(page.at_css("select#person_nationality option[selected]")["value"]).to eq("DE")
  end

  it "chooses the visa countries from the country list, the Schengen entry from its members only" do
    ul.update_columns(passport_nationality: "ZA, DE, GB",
      jamboree_data: {"visa_needed" => "yes_need_support", "visa_schengen_first_entry" => "US"})
    get :edit, params: {id: ul.id}

    other = page.at_css("select#person_visa_other_nationalities_codes[multiple][data-country-select]")
    expect(other.css("option[selected]").pluck("value")).to eq(%w[DE GB])
    schengen = page.css("select#person_visa_schengen_first_entry option").pluck("value")
    expect(schengen).to match_array(["", "US", *Wsjrdp::CountryLookup::SCHENGEN_CODES])
    expect(page.at_css("select#person_visa_schengen_first_entry option[selected]").text)
      .to eq("US (nicht erkannt)")
    %w[travel_document_country visa_nationality_at_birth visa_employer_country visa_residence_country].each do |attr|
      expect(page.at_css("select#person_#{attr}[data-country-select]")).to be_present
    end
    expect(page.at_css("input#person_visa_residence_permit")).to be_present

    put :update, params: {id: ul.id, person: {visa_other_nationalities_codes: ["", "GB", "FR"]}}
    expect(ul.reload.visa_other_nationalities).to eq("GB, FR")
    get :show, params: {id: ul.id}
    expect(page.text).to include("Vereinigtes Königreich (GB), Frankreich (FR)")
  end

  it "keeps a country of birth it does not know, marked in the list" do
    ul.update_columns(jamboree_data: {"country_of_birth" => "Mittelerde"})
    get :edit, params: {id: ul.id}
    expect(page.at_css("select#person_country_of_birth option[selected]").text).to eq("Mittelerde (nicht erkannt)")

    put :update, params: {id: ul.id, person: {country_of_birth: "Mittelerde"}}
    expect(ul.reload.country_of_birth).to eq("Mittelerde")
  end

  it "routes the short URLs" do
    expect(get: "/people/#{ul.id}/jamboree_data").to route_to("person/jamboree_data#show", id: ul.id.to_s)
    expect(get: "/people/#{ul.id}/jamboree_data/edit").to route_to("person/jamboree_data#edit", id: ul.id.to_s)
    expect(put: "/people/#{ul.id}/jamboree_data").to route_to("person/jamboree_data#update", id: ul.id.to_s)
  end
end
