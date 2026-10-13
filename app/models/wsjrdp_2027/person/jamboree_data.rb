# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The additional data the Jamboree registration asks for, kept in the jsonb
# column people.jamboree_data (one key per answer), and whether the person
# confirmed them (people.jamboree_data_confirmed). Included into Person after
# Wsjrdp2027::Person (lib/hitobito_wsjrdp_2027/wagon.rb).
module Wsjrdp2027::Person::JamboreeData
  extend ActiveSupport::Concern

  LANGUAGES = %i[english french spanish arabic].freeze
  LANGUAGE_SKILLS = %i[reading writing speaking listening].freeze
  # The level of each language skill; the labels come from the locale
  # (LANGUAGE_LEVEL_I18N), as for the core's genders.
  LANGUAGE_LEVELS = %w[none basic conversational proficient fluent native].freeze
  LANGUAGE_LEVEL_I18N = "activerecord.attributes.person.jamboree_language_levels"
  # english_reading, english_writing, ..., arabic_listening
  LANGUAGE_ATTRS = LANGUAGES.flat_map { |language| LANGUAGE_SKILLS.map { |skill| :"#{language}_#{skill}" } }.freeze
  ADULT_ONLY_ATTRS = (%i[mothers_first_name fathers_first_name mothers_surname_at_birth
    prior_wsj_experience vehicle_registration_number] + LANGUAGE_ATTRS.drop(LANGUAGE_SKILLS.size)).freeze
  JOURNEY_ATTRS = %i[arrival_location arrival_date arrival_time arrival_type arrival_number
    departure_location departure_date departure_time departure_type departure_number].freeze
  LANGUAGE_EXPORT_MAP = {
    reading: {
      "none" => "Not reading",
      "basic" => "Basic",
      "conversational" => "Conversational",
      "proficient" => "Proficient",
      "fluent" => "Fluent",
      "native" => "Native"
    },
    writing: {
      "none" => "Not writing",
      "basic" => "Basic",
      "conversational" => "Conversational",
      "proficient" => "Proficient",
      "fluent" => "Fluent",
      "native" => "Native"
    },
    speaking: {
      "none" => "Not speaking",
      "basic" => "Basic",
      "conversational" => "Conversational",
      "proficient" => "Proficient",
      "fluent" => "Fluent",
      "native" => "Native"
    },
    listening: {
      "none" => "Not listening",
      "basic" => "Basic",
      "conversational" => "Conversational",
      "proficient" => "Proficient",
      "fluent" => "Fluent",
      "native" => "Native"
    }
  }.freeze
  # The values of the selects; their labels come from the locale under
  # ENUM_I18N (i18n_enum), as for the language levels.
  ENUM_I18N = "activerecord.attributes.person"
  TRAVEL_DOCUMENT_TYPES = %w[ordinary_passport national_identity_card official_passport diplomatic_passport
    service_passport special_passport other_travel_document].freeze
  # What travel_document_other holds for a national identity card: the export
  # sends it as the organizer's "Other travel document (please specify)".
  NATIONAL_IDENTITY_CARD_TEXT = "National identity card"
  VISA_NEEDED_VALUES = %w[no yes_have_one yes_need_support].freeze
  ARRIVAL_LOCATIONS = %w[amber_expo gdansk_ferry_terminal gdansk_glowny_trainstation
    gdynia_ferry_terminal lech_walesa_airport].freeze
  DEPARTURE_LOCATIONS = (ARRIVAL_LOCATIONS - %w[amber_expo] + %w[jamboree_site_pick_up_point]).freeze
  TRAVEL_TYPES = %w[bicycle bus car coach ferry flight train].freeze
  # The choices of the visa questions, as the organizer's template has them;
  # non-trivial labels give the template's English with a German translation
  # (Ja/Nein and "Andere (bitte angeben)" are German only).
  VISA_GENDERS = %w[female male x].freeze
  VISA_CIVIL_STATUSES = %w[single married registered_partnership separated divorced widowed other].freeze
  VISA_STUDENT_STATUSES = %w[student not_student].freeze
  VISA_YES_NO = %w[yes no].freeze
  VISA_FAMILY_RELATIONS = %w[spouse child grandchild dependent_ascendant registered_partnership other].freeze
  # The visa gender a person's gender suggests (w, m, d).
  VISA_GENDER_OF_GENDER = {"w" => "female", "m" => "male", "d" => "x"}.freeze
  VISA_DETAIL_ATTRS = %i[
    visa_nationality_at_birth
    visa_other_nationalities
    visa_gender_as_in_travel_document
    visa_civil_status
    visa_civil_status_other
    visa_current_student_status
    visa_family_eu_citizen_relationship
    visa_family_eu_citizen_relation
    visa_family_eu_citizen_relation_other
    visa_employer_name
    visa_employer_address_1
    visa_employer_address_2
    visa_employer_city
    visa_employer_postcode
    visa_employer_state
    visa_employer_country
    visa_residence_country
    visa_residence_permit
    visa_schengen_first_entry
    visa_fingerprints_visa_number
  ].freeze
  # Visa questions answered Ja or Nein: true or false stored, nothing while
  # unanswered (unlike BOOLEAN_ATTRS, where false is not stored).
  VISA_YES_NO_ATTRS = %i[visa_residence_other_than_nationality visa_fingerprints_collected].freeze
  # The visa answers in the order of the form: each Ja/Nein question before
  # what it asks for.
  VISA_DISPLAY_ATTRS = VISA_DETAIL_ATTRS.flat_map do |attr|
    case attr
    when :visa_residence_country then [:visa_residence_other_than_nationality, attr]
    when :visa_fingerprints_visa_number then [:visa_fingerprints_collected, :visa_fingerprints_date, attr]
    else [attr]
    end
  end.freeze
  WHEELCHAIR_TYPES = %w[manual electric].freeze
  ALLERGY_SEVERITIES = %w[severe medium mild].freeze
  MEDICAL_EQUIPMENT = %w[battery_charging_station continuous_power_supply medication_cooling other].freeze
  # The allergies asked for; each one's name is its attribute's
  # (allergy_<key>), the severity its own select (allergy_<key>_severity).
  ALLERGIES = %i[milk casein egg peanut tree_nuts gluten soy lupin mustard crustaceans sesame molluscs
    sulfite fruit allium fish seafood].freeze
  # The one choice per allergy on the form (allergy_<key>_level): "none" for
  # no allergy, else its severity. Written to allergy_<key> and
  # allergy_<key>_severity, which stay what is stored.
  ALLERGY_LEVELS = (%w[none] + ALLERGY_SEVERITIES.reverse).freeze
  ALLERGY_LEVEL_ATTRS = ALLERGIES.map { |allergy| :"allergy_#{allergy}_level" }.freeze

  TEXT_ATTRS = %i[
    known_as_name
    mothers_first_name
    fathers_first_name
    mothers_surname_at_birth
    place_of_birth
    country_of_birth
    nationality
    travel_document_number
    travel_document_country
    visa_information
    arrival_time
    arrival_number
    departure_time
    departure_number
    prior_wsj_experience
    vehicle_registration_number
    dietary_details
    religious_health_beliefs
    medical_equipment_details
    other_mobility_details
    non_visible_disability_details
  ].concat(VISA_DETAIL_ATTRS, %i[travel_document_other]).freeze

  # Texts holding a country, stored as its ISO code (jsonb_accessor cast:
  # :country) and chosen from the country list
  # (StandardFormBuilder#country_select_field).
  COUNTRY_ATTRS = %i[country_of_birth nationality travel_document_country visa_nationality_at_birth
    visa_employer_country visa_residence_country visa_schengen_first_entry].freeze
  # Texts holding several countries, stored as their ISO codes ("AT, FR",
  # cast: :countries), chosen as <attr>_codes
  # (StandardFormBuilder#country_multi_select_field).
  COUNTRIES_ATTRS = %i[visa_other_nationalities].freeze

  SELECT_ATTRS = (
    LANGUAGE_ATTRS +
    %i[
      travel_document_type
      visa_needed
      wheelchair_type
      arrival_location
      arrival_type
      departure_location
      departure_type
    ] +
    ALLERGIES.map { |allergy| :"allergy_#{allergy}_severity" }
  ).freeze

  DATE_ATTRS = %i[
    travel_document_issue_date
    travel_document_expiration_date
    visa_fingerprints_date
    arrival_date
    departure_date
  ].freeze

  BOOLEAN_ATTRS = (
    %i[
      comfortable_on_water
      comfortable_in_water
      comfortable_without_balance
      comfortable_in_crowd
      comfortable_flashing_lights
      comfortable_loud_noise
      comfortable_confined_space
      refrigerated_medication_needed
      mobility_restricted
      uses_wheelchair
      uses_mobility_frame
      other_mobility_needs
      sensory_sensitivities
      non_visible_disability
      gdpr_agreement
    ] +
    ALLERGIES.map { |allergy| :"allergy_#{allergy}" }
  ).freeze

  ARRAY_ATTRS = %i[
    medical_equipment_needs
  ].freeze

  ATTRS = (
    TEXT_ATTRS +
    SELECT_ATTRS +
    DATE_ATTRS +
    BOOLEAN_ATTRS +
    ARRAY_ATTRS +
    VISA_YES_NO_ATTRS +
    %i[jamboree_data_confirmed]
  ).freeze

  included do
    # Modify the core lists in place, as Wsjrdp2027::Person does.
    ::Person::INTERNAL_ATTRS.concat(ATTRS + [:jamboree_data])
    ::Person.used_attributes.concat(ATTRS)
    ::Person.used_attributes.uniq!
    # The person log leaves out the column as a whole and shows each answer
    # changed on the page on its own (the keys are stored attributes,
    # Wsjrdp2027::PaperTrail::Events::Base), as for additional_info.
    paper_trail_options[:skip] << "jamboree_data"

    # The column is NOT NULL, so validates_by_schema (core person.rb) adds a
    # presence validator -- but its {} default is blank?, which would make
    # every Person invalid. Drop it, as for wsjrdp_user_preferences.
    remove_schema_validations :jamboree_data, only: :presence

    TEXT_ATTRS.each do |attr|
      cast = if COUNTRY_ATTRS.include?(attr) then :country
      elsif COUNTRIES_ATTRS.include?(attr) then :countries
      end
      jsonb_accessor :jamboree_data, attr, strip: true, cast: cast
      attribute attr, :string
    end

    SELECT_ATTRS.each do |attr|
      jsonb_accessor :jamboree_data, attr, strip: true
      attribute attr, :string
    end

    # <attr>_label in German for the page (FormatHelper#format_attr), and only
    # the known levels.
    LANGUAGE_ATTRS.each { |attr| i18n_enum attr, LANGUAGE_LEVELS, i18n_prefix: LANGUAGE_LEVEL_I18N }
    i18n_enum :travel_document_type, TRAVEL_DOCUMENT_TYPES, i18n_prefix: "#{ENUM_I18N}.jamboree_travel_document_types"
    i18n_enum :visa_needed, VISA_NEEDED_VALUES, i18n_prefix: "#{ENUM_I18N}.jamboree_visa_needed"
    i18n_enum :wheelchair_type, WHEELCHAIR_TYPES, i18n_prefix: "#{ENUM_I18N}.jamboree_wheelchair_types"
    i18n_enum :visa_gender_as_in_travel_document, VISA_GENDERS, i18n_prefix: "#{ENUM_I18N}.jamboree_visa_genders"
    i18n_enum :visa_civil_status, VISA_CIVIL_STATUSES, i18n_prefix: "#{ENUM_I18N}.jamboree_visa_civil_statuses"
    i18n_enum :visa_current_student_status, VISA_STUDENT_STATUSES,
      i18n_prefix: "#{ENUM_I18N}.jamboree_visa_student_statuses"
    i18n_enum :visa_family_eu_citizen_relationship, VISA_YES_NO, i18n_prefix: "#{ENUM_I18N}.jamboree_visa_yes_no"
    i18n_enum :visa_family_eu_citizen_relation, VISA_FAMILY_RELATIONS,
      i18n_prefix: "#{ENUM_I18N}.jamboree_visa_family_relations"
    i18n_enum :arrival_location, ARRIVAL_LOCATIONS, i18n_prefix: "#{ENUM_I18N}.jamboree_travel_locations"
    i18n_enum :departure_location, DEPARTURE_LOCATIONS, i18n_prefix: "#{ENUM_I18N}.jamboree_travel_locations"
    i18n_enum :arrival_type, TRAVEL_TYPES, i18n_prefix: "#{ENUM_I18N}.jamboree_travel_types"
    i18n_enum :departure_type, TRAVEL_TYPES, i18n_prefix: "#{ENUM_I18N}.jamboree_travel_types"
    ALLERGIES.each do |allergy|
      i18n_enum :"allergy_#{allergy}_severity", ALLERGY_SEVERITIES, i18n_prefix: "#{ENUM_I18N}.jamboree_allergy_severities"

      # "none" without the allergy, the severity with it -- nil for an allergy
      # whose severity is missing. A blank choice changes nothing, so a missing
      # severity stays as it is until one is chosen.
      define_method(:"allergy_#{allergy}_level") do
        public_send(:"allergy_#{allergy}") ? public_send(:"allergy_#{allergy}_severity") : "none"
      end

      define_method(:"allergy_#{allergy}_level=") do |level|
        level = level.to_s
        return if level.blank?

        public_send(:"allergy_#{allergy}=", level != "none")
        public_send(:"allergy_#{allergy}_severity=", (level == "none") ? nil : level)
      end
    end

    # Cast on write and read: a form sends dates and boxes as strings, and a
    # stored "0" would read as true. An unticked box removes its key.
    DATE_ATTRS.each do |attr|
      jsonb_accessor :jamboree_data, attr, cast: :date
      attribute attr, :date
    end

    BOOLEAN_ATTRS.each do |attr|
      jsonb_accessor :jamboree_data, attr, cast: :boolean
      attribute attr, :boolean
    end

    # true, false, or nil while unanswered; a blank answer removes the key.
    VISA_YES_NO_ATTRS.each do |attr|
      store_accessor :jamboree_data, attr
      define_method(attr) { ActiveModel::Type::Boolean.new.cast(read_store_attribute(:jamboree_data, attr)) }
      define_method(:"#{attr}=") do |value|
        value = ActiveModel::Type::Boolean.new.cast(value)
        value.nil? ? jamboree_data.delete(attr.to_s) : write_store_attribute(:jamboree_data, attr, value)
      end
    end

    store_accessor :jamboree_data, :medical_equipment_needs
    validate :medical_equipment_needs_known

    attribute :jamboree_data_confirmed, :boolean

    # Disabled until it is clear what they are for: without a context they
    # run on every save of a person, and jamboree_data_confirmed defaults to
    # false, so every person would be invalid.
    # validates :jamboree_data_confirmed, acceptance: {accept: true}
    # validates :gdpr_agreement, acceptance: {accept: true}

    before_validation :clear_jamboree_details_without_their_box
  end

  # A detail answers a box; with the box unticked, it goes (the form sends no
  # hidden, disabled field, so the old value would stay).
  DETAILS_OF_BOX = ALLERGIES.to_h { |allergy| [:"allergy_#{allergy}_severity", :"allergy_#{allergy}"] }.merge(
    wheelchair_type: :uses_wheelchair,
    other_mobility_details: :other_mobility_needs,
    non_visible_disability_details: :non_visible_disability,
    visa_residence_country: :visa_residence_other_than_nationality,
    visa_residence_permit: :visa_residence_other_than_nationality,
    visa_fingerprints_date: :visa_fingerprints_collected,
    visa_fingerprints_visa_number: :visa_fingerprints_collected
  ).freeze

  # The name for the name tag as shown when none was given: the stored
  # known_as_name keeps only what the person entered.
  def known_as_name_or_default = known_as_name.presence || known_as_name_default_with_source.first

  # The name for the name tag without a known_as_name, with where it comes
  # from (Wsjrdp2027::Person#nickname_or_short_first_name_with_source).
  def known_as_name_default_with_source = nickname_or_short_first_name_with_source

  # The allergies with an allergy, as [key, severity or nil], and those
  # without, in the order of ALLERGIES.
  def jamboree_data_allergies
    with, without = ALLERGIES.partition { |allergy| public_send(:"allergy_#{allergy}") }
    [with.map { |allergy| [allergy, public_send(:"allergy_#{allergy}_severity").presence] }, without]
  end

  # The nationality as stored, else the main one of the registration (the
  # first of passport_nationality, as its code where the lookup knows it).
  def nationality_or_default
    nationality.presence || Wsjrdp::CountryLookup.codes_of(
      Wsjrdp::CountryLookup.split(passport_nationality).first
    )
  end

  # The other nationalities as codes, for the form.
  def visa_other_nationalities_codes = Wsjrdp::CountryLookup.split(visa_other_nationalities)

  def visa_other_nationalities_codes=(values)
    self.visa_other_nationalities = Array(values).join(",")
  end

  # The other nationalities as stored, else those of the registration after
  # the main one (passport_nationality).
  def visa_other_nationalities_codes_or_default
    visa_other_nationalities_codes.presence ||
      Wsjrdp::CountryLookup.split(Wsjrdp::CountryLookup.codes_of(passport_nationality)).drop(1)
  end

  # The visa gender as stored, else the one the person's gender suggests.
  def visa_gender_as_in_travel_document_or_default
    visa_gender_as_in_travel_document.presence || VISA_GENDER_OF_GENDER[gender]
  end

  # The confirmations of the page "Daten für den Veranstalter" not yet given,
  # in the order of the page.
  def jamboree_data_missing_confirmations
    %i[gdpr_agreement jamboree_data_confirmed].reject { |attr| public_send(attr) == true }
  end

  def jamboree_data_adult?
    %w[UL IST CMT].include?(effective_wsj_role)
  end

  def jamboree_data_journey_editable?
    !%w[YP UL].include?(effective_wsj_role)
  end

  def medical_equipment_needs
    Array(super).compact_blank
  end

  def medical_equipment_needs=(value)
    super(Array(value).compact_blank)
  end

  # [label, value] for the form's select of an i18n_enum attribute, in the
  # order of the locale.
  def jamboree_data_options(attr)
    labels = self.class.public_send(:"#{attr}_labels")
    if attr.to_sym == :departure_location
      labels = labels.select { |value, _label| DEPARTURE_LOCATIONS.include?(value.to_s) }
    end
    labels.map { |value, label| [label, value.to_s] }
  end

  # [label, value] for the medical equipment boxes; the labels of the chosen.
  def jamboree_data_medical_equipment_options
    MEDICAL_EQUIPMENT.map { |value| [I18n.t("#{ENUM_I18N}.jamboree_medical_equipment.#{value}"), value] }
  end

  def medical_equipment_needs_labels
    medical_equipment_needs.map { |value| I18n.t("#{ENUM_I18N}.jamboree_medical_equipment.#{value}", default: value) }
  end

  # [label, value] for the form's selects, in the order of LANGUAGE_LEVELS.
  def jamboree_data_language_levels
    LANGUAGE_LEVELS.map { |level| [I18n.t("#{LANGUAGE_LEVEL_I18N}.#{level}"), level] }
  end

  private

  def clear_jamboree_details_without_their_box
    DETAILS_OF_BOX.each { |detail, box| public_send(:"#{detail}=", nil) unless public_send(box) }
    # Fixed for an identity card. The texts for Other (*_other) and the visa
    # answers stay when their choice changes: hidden, they are not sent, and
    # the page and the export use them only while their choice asks for them.
    self.travel_document_other = NATIONAL_IDENTITY_CARD_TEXT if travel_document_type == "national_identity_card"
    self.visa_family_eu_citizen_relation = nil unless visa_family_eu_citizen_relationship == "yes"
    self.medical_equipment_details = nil unless medical_equipment_needs.include?("other")
  end

  def medical_equipment_needs_known
    unknown = medical_equipment_needs - MEDICAL_EQUIPMENT
    errors.add(:medical_equipment_needs, :inclusion) if unknown.any?
  end
end
