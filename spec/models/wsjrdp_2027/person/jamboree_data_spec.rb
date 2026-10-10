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

  it "keeps the answers in people.jamboree_data" do
    person.update!(nationality: "deutsch", english_speaking: "fluent", allergy_peanut: true,
      travel_document_issue_date: Date.new(2025, 1, 2), medical_equipment_needs: ["", "medication_cooling"])

    stored = Person.where(id: person.id).pick(:jamboree_data)
    expect(stored).to include("nationality" => "deutsch", "english_speaking" => "fluent", "allergy_peanut" => true,
      "travel_document_issue_date" => "2025-01-02", "medical_equipment_needs" => ["medication_cooling"])
    expect(person.reload.allergy_peanut).to be(true)
  end

  it "stores known_as_name only as given, the default apart" do
    person.update_columns(nickname: "Kim", jamboree_data: {})
    expect(person.reload).to have_attributes(known_as_name: nil, known_as_name_or_default: "Kim",
      known_as_name_source: :nickname)
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
      person.update!(nationality: "deutsch", allergy_milk: "1", jamboree_data_confirmed: true)
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

  it "drops a detail whose box is unticked" do
    person.update!(allergy_peanut: "1", allergy_peanut_severity: "mild", uses_wheelchair: "1", wheelchair_type: "manual",
      medical_equipment_needs: ["other"], medical_equipment_details: "Pumpe")

    person.update!(allergy_peanut: "0", uses_wheelchair: "0", medical_equipment_needs: [""])

    expect(person.reload).to have_attributes(allergy_peanut_severity: nil, wheelchair_type: nil, medical_equipment_details: nil)
  end

  it "registers its attributes as internal ones" do
    expect(Person::INTERNAL_ATTRS).to include(:nationality, :jamboree_data_confirmed)
  end
end
