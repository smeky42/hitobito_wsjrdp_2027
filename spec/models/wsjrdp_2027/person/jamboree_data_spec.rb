# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Wsjrdp2027::Person::JamboreeData do
  let(:person) { people(:cmt_leader) }

  it "uses the effective WSJ role for adult-only answers" do
    expect(people(:yp_a_1).jamboree_data_adult?).to be(false)
    expect(people(:ul_a_1).jamboree_data_adult?).to be(true)
    expect(people(:ist_a_1).jamboree_data_adult?).to be(true)
    expect(person.jamboree_data_adult?).to be(true)
  end

  it "reserves journey editing for roles outside the units" do
    expect(people(:yp_a_1).jamboree_data_journey_editable?).to be(false)
    expect(people(:ul_a_1).jamboree_data_journey_editable?).to be(false)
    expect(people(:ist_a_1).jamboree_data_journey_editable?).to be(true)
    expect(person.jamboree_data_journey_editable?).to be(true)
  end

  it "keeps the answers in people.jamboree_data" do
    person.update!(nationality: "DE", english_speaking: "fluent", allergy_peanut: true,
      travel_document_issue_date: Date.new(2025, 1, 2), medical_equipment_needs: ["", "medication_cooling"])

    stored = Person.where(id: person.id).pick(:jamboree_data)
    expect(stored).to include("nationality" => "DE", "english_speaking" => "fluent", "allergy_peanut" => true,
      "travel_document_issue_date" => "2025-01-02", "medical_equipment_needs" => ["medication_cooling"])
    expect(person.reload.allergy_peanut).to be(true)
  end

  it "reads an unanswered comfort answer as comfortable without storing it, and stores false as well as true" do
    person.update_columns(jamboree_data: {})
    expect(person.reload.comfortable_on_water).to be(true)
    expect(Person.where(id: person.id).pick(:jamboree_data)).to eq({})

    person.update!(comfortable_on_water: "false")
    expect(person.reload.comfortable_on_water).to be(false)
    expect(Person.where(id: person.id).pick(:jamboree_data)).to include("comfortable_on_water" => false)

    person.update!(comfortable_on_water: "true")
    expect(Person.where(id: person.id).pick(:jamboree_data)).to include("comfortable_on_water" => true)
  end

  it "stores known_as_name only as given, the default apart" do
    person.update_columns(nickname: "Kim", jamboree_data: {})
    expect(person.reload).to have_attributes(known_as_name: nil, known_as_name_or_default: "Kim",
      known_as_name_default_with_source: ["Kim", :nickname])
    expect(Person.new(first_name: "Alex").known_as_name).to be_nil

    person.update!(known_as_name: "Kimmy")
    expect(person.reload).to have_attributes(known_as_name: "Kimmy", known_as_name_or_default: "Kimmy")
  end

  it "reads dates as dates, written as a form sends them" do
    person.update!(travel_document_issue_date: "02.01.2025", travel_document_expiration_date: "2035-01-01")

    expect(person.reload.travel_document_issue_date).to eq(Date.new(2025, 1, 2))
    expect(person.travel_document_expiration_date).to eq(Date.new(2035, 1, 1))
    expect(Person.where(id: person.id).pick(:jamboree_data)).to include("travel_document_issue_date" => "2025-01-02")
  end

  it "stores journey choices, times and dates in jamboree_data" do
    person.update!(arrival_location: "amber_expo", arrival_date: "28.07.2027", arrival_time: "14:30",
      arrival_type: "train", arrival_number: "ICE 123", departure_location: "jamboree_site_pick_up_point",
      departure_date: "08.08.2027", departure_time: "09:15", departure_type: "coach", departure_number: "Bus 4")

    expect(person.reload).to have_attributes(arrival_date: Date.new(2027, 7, 28), departure_date: Date.new(2027, 8, 8))
    expect(Person.where(id: person.id).pick(:jamboree_data)).to include(
      "arrival_location" => "amber_expo", "arrival_time" => "14:30", "arrival_type" => "train",
      "arrival_number" => "ICE 123", "departure_location" => "jamboree_site_pick_up_point",
      "departure_time" => "09:15", "departure_type" => "coach", "departure_number" => "Bus 4"
    )

    person.departure_location = "amber_expo"
    expect(person).not_to be_valid
  end

  it "keeps the visa application details when visa support is no longer needed" do
    person.update!(visa_needed: "yes_need_support", visa_nationality_at_birth: "DE",
      visa_fingerprints_collected: "true", visa_fingerprints_date: "2025-01-02", visa_fingerprints_visa_number: "123")

    person.update!(visa_needed: "yes_have_one")
    expect(person.reload).to have_attributes(visa_nationality_at_birth: "DE",
      visa_fingerprints_collected: true, visa_fingerprints_date: Date.new(2025, 1, 2),
      visa_fingerprints_visa_number: "123")

    person.update!(visa_fingerprints_collected: "false")
    expect(person.reload).to have_attributes(visa_fingerprints_collected: false, visa_fingerprints_date: nil,
      visa_fingerprints_visa_number: nil, visa_residence_other_than_nationality: nil)
  end

  it "stores the countries as ISO codes, keeping a value it does not know" do
    person.update!(travel_document_country: "Deutschland", visa_employer_country: "Österreich",
      visa_schengen_first_entry: "PL", visa_nationality_at_birth: "Mittelerde",
      visa_other_nationalities_codes: ["", "FR", "Elbisch"])

    expect(person.reload).to have_attributes(travel_document_country: "DE", visa_employer_country: "AT",
      visa_schengen_first_entry: "PL", visa_nationality_at_birth: "Mittelerde",
      visa_other_nationalities: "FR, Elbisch", visa_other_nationalities_codes: %w[FR Elbisch])

    person.update!(visa_other_nationalities_codes: [""])
    expect(Person.where(id: person.id).pick(:jamboree_data)).not_to have_key("visa_other_nationalities")
  end

  it "suggests the further nationalities of the registration as other nationalities" do
    person.passport_nationality = "ZA, Deutsch, GB"
    expect(person.visa_other_nationalities_codes_or_default).to eq(%w[DE GB])

    person.visa_other_nationalities = "FR"
    expect(person.visa_other_nationalities_codes_or_default).to eq(%w[FR])
  end

  it "keeps the residence country and permit only with a residence other than the nationality" do
    person.update!(visa_residence_other_than_nationality: "true", visa_residence_country: "Schweiz",
      visa_residence_permit: "Permit C 123")
    expect(person.reload).to have_attributes(visa_residence_country: "CH", visa_residence_permit: "Permit C 123")

    person.update!(visa_residence_other_than_nationality: "false")
    expect(person.reload).to have_attributes(visa_residence_country: nil, visa_residence_permit: nil)
  end

  it "reads boxes as booleans, a form's 0 as false, and drops an unticked one" do
    person.update!(allergy_milk: "1", uses_wheelchair: "1")
    expect(person.reload).to have_attributes(allergy_milk: true, uses_wheelchair: true)

    person.update!(allergy_milk: "0")
    expect(person.reload.allergy_milk).to be(false)
    expect(Person.where(id: person.id).pick(:jamboree_data)).not_to have_key("allergy_milk")
  end

  it "leaves a person without confirmed jamboree data valid" do
    expect(person.jamboree_data_confirmed).to be(false)
    expect(person).to be_valid
  end

  it "logs each answer changed, not the column" do
    with_versioning do
      person.update!(nationality: "DE", allergy_milk: "1", jamboree_data_confirmed: true)
    end

    version = person.versions.reorder(:id).last
    expect(version.changeset.keys).to include("nationality", "allergy_milk", "jamboree_data_confirmed")
    expect(version.changeset.keys).not_to include("jamboree_data")
  end

  it "labels the language levels in German from the locale and allows only those" do
    person.english_reading = "basic"
    expect(person.english_reading_label).to eq("Grundkenntnisse")
    expect(person.jamboree_data_language_levels.first).to eq(["Keine", "none"])

    person.english_reading = "excellent"
    expect(person).not_to be_valid
  end

  it "labels the selects in German from the locale and allows only their values" do
    person.travel_document_type = "ordinary_passport"
    person.visa_needed = "no"
    person.allergy_milk_severity = "severe"
    expect(person).to have_attributes(travel_document_type_label: "Reisepass", visa_needed_label: "Nein",
      allergy_milk_severity_label: "Schwere anaphylaktische Reaktion (lebensbedrohlich)")
    expect(person.jamboree_data_options(:wheelchair_type)).to eq([["Manuell", "manual"], ["Elektrisch", "electric"]])
    expect(person.jamboree_data_options(:travel_document_type).first(3))
      .to eq([["Reisepass", "ordinary_passport"], ["Personalausweis", "national_identity_card"],
        ["Amtlicher Pass", "official_passport"]])

    person.visa_needed = "maybe"
    expect(person).not_to be_valid
  end

  it "keeps the medical equipment as chosen, clearable, labelled, and only known values" do
    person.update!(medical_equipment_needs: ["", "medication_cooling", "other"], medical_equipment_details: "Insulin")
    expect(person.reload.medical_equipment_needs_labels).to eq(["Kühlung für Medikamente", "Sonstiges"])

    person.update!(medical_equipment_needs: [""])
    expect(person.reload.medical_equipment_needs).to eq([])

    person.medical_equipment_needs = ["jetpack"]
    expect(person).not_to be_valid
  end

  it "writes an allergy level to the allergy and its severity, a blank one changes nothing" do
    person.update!(allergy_peanut_level: "severe", allergy_milk_level: "none")
    expect(person.reload).to have_attributes(allergy_peanut: true, allergy_peanut_severity: "severe",
      allergy_peanut_level: "severe", allergy_milk: false, allergy_milk_severity: nil, allergy_milk_level: "none")

    person.update!(allergy_peanut_level: "none")
    expect(person.reload).to have_attributes(allergy_peanut: false, allergy_peanut_severity: nil)

    person.update!(allergy_egg: true)
    expect(person.reload.allergy_egg_level).to be_nil
    person.update!(allergy_egg_level: "")
    expect(person.reload).to have_attributes(allergy_egg: true, allergy_egg_severity: nil)

    with, without = person.jamboree_data_allergies
    expect(with).to eq([[:egg, nil]])
    expect(without).to include(:milk, :peanut)
  end

  it "keeps the text of an other travel document, fixed for an identity card" do
    person.update!(travel_document_type: "other_travel_document", travel_document_other: "Kinderreisepass")
    expect(person.reload.travel_document_other).to eq("Kinderreisepass")

    person.update!(travel_document_type: "national_identity_card", travel_document_other: "egal")
    expect(person.reload.travel_document_other).to eq("National identity card")

    person.update!(travel_document_type: "other_travel_document", travel_document_other: "Kinderreisepass")
    person.update!(travel_document_type: "ordinary_passport")
    expect(person.reload.travel_document_other).to eq("Kinderreisepass")
  end

  it "keeps the visa choices of the template and the other civil status" do
    person.update!(visa_needed: "yes_need_support", visa_civil_status: "other", visa_civil_status_other: "verlobt",
      visa_current_student_status: "student", visa_family_eu_citizen_relationship: "no",
      visa_gender_as_in_travel_document: "x")
    expect(person.reload).to have_attributes(visa_civil_status_other: "verlobt",
      visa_current_student_status_label: "I am a student (ich bin in Ausbildung, z. B. Schule oder Studium)",
      visa_family_eu_citizen_relationship_label: "Nein", visa_gender_as_in_travel_document_label: "X (divers / ohne Geschlechtsangabe)")

    person.update!(visa_civil_status: "married")
    expect(person.reload.visa_civil_status_other).to eq("verlobt")

    person.visa_civil_status = "engaged"
    expect(person).not_to be_valid
  end

  it "keeps the family relation only with an EU family member, its text always" do
    person.update!(visa_needed: "yes_need_support", visa_family_eu_citizen_relationship: "yes",
      visa_family_eu_citizen_relation: "other", visa_family_eu_citizen_relation_other: "Cousine")
    expect(person.reload).to have_attributes(visa_family_eu_citizen_relation_other: "Cousine",
      visa_family_eu_citizen_relation_label: "Andere (bitte angeben)")

    person.update!(visa_family_eu_citizen_relation: "spouse")
    expect(person.reload).to have_attributes(visa_family_eu_citizen_relation: "spouse",
      visa_family_eu_citizen_relation_other: "Cousine")

    person.update!(visa_family_eu_citizen_relationship: "no")
    expect(person.reload.visa_family_eu_citizen_relation).to be_nil
  end

  it "suggests the visa gender from the gender" do
    expect(Person.new(gender: "w").visa_gender_as_in_travel_document_or_default).to eq("female")
    expect(Person.new(gender: "d", visa_gender_as_in_travel_document: "male").visa_gender_as_in_travel_document_or_default)
      .to eq("male")
    expect(Person.new.visa_gender_as_in_travel_document_or_default).to be_nil
  end

  it "drops a detail whose box is unticked" do
    person.update!(allergy_peanut: "1", allergy_peanut_severity: "mild", uses_wheelchair: "1", wheelchair_type: "manual",
      medical_equipment_needs: ["other"], medical_equipment_details: "Pumpe")

    person.update!(allergy_peanut: "0", uses_wheelchair: "0", medical_equipment_needs: [""])

    expect(person.reload).to have_attributes(allergy_peanut_severity: nil, wheelchair_type: nil, medical_equipment_details: nil)
  end

  it "takes the nickname, else the first of the first names, as the default" do
    expect(Person.new(first_name: "Anna Maria", nickname: "Ani").known_as_name_default_with_source).to eq(["Ani", :nickname])
    expect(Person.new(first_name: "Anna").known_as_name_default_with_source).to eq(["Anna", :first_name])
    expect(Person.new(first_name: "Anna-Lena Marie", nickname: "").known_as_name_default_with_source)
      .to eq(["Anna-Lena", :first_names])
    expect(Person.new(first_name: "", nickname: "").known_as_name_default_with_source).to eq([nil, nil])
    expect(Person.new(first_name: "Anna Maria").nickname_or_short_first_name).to eq("Anna")
  end

  it "lists the confirmations not yet given" do
    expect(person.jamboree_data_missing_confirmations).to eq(%i[gdpr_agreement jamboree_data_confirmed])

    person.update!(gdpr_agreement: true)
    expect(person.jamboree_data_missing_confirmations).to eq(%i[jamboree_data_confirmed])

    person.update!(jamboree_data_confirmed: true)
    expect(person.jamboree_data_missing_confirmations).to be_empty
  end

  it "asks the adults by wsjrdp_role to order a uniform" do
    expect(people(:yp_a_1).uniform_order_available?).to be(false)
    expect(people(:ul_a_1).uniform_order_available?).to be(true)
    expect(people(:ist_a_1).uniform_order_available?).to be(true)

    person = people(:ist_a_1)
    person.update_columns(wsj_role: nil, primary_group_id: 45)
    expect(person.wsjrdp_role).to eq("BMT")
    expect(person.uniform_order_available?).to be(true)
  end

  it "registers its attributes as internal ones" do
    expect(Person::INTERNAL_ATTRS).to include(:nationality, :jamboree_data_confirmed)
  end
end
