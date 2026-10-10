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
  TRAVEL_DOCUMENT_TYPES = %w[ordinary_passport diplomatic_passport service_passport official_passport
    special_passport other_travel_document].freeze
  VISA_NEEDED_VALUES = %w[no yes_have_one yes_need_support].freeze
  WHEELCHAIR_TYPES = %w[manual electric].freeze
  ALLERGY_SEVERITIES = %w[severe medium mild].freeze
  MEDICAL_EQUIPMENT = %w[battery_charging_station continuous_power_supply medication_cooling other].freeze
  # The allergies asked for; each one's name is its attribute's
  # (allergy_<key>), the severity its own select (allergy_<key>_severity).
  ALLERGIES = %i[milk casein egg peanut tree_nuts gluten soy lupin mustard crustaceans sesame molluscs
    sulfite fruit allium fish seafood].freeze

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
    prior_wsj_experience
    vehicle_registration_number
    dietary_requirements
    dietary_details
    religious_health_beliefs
    medical_equipment_details
    other_mobility_details
    non_visible_disability_details
  ].freeze

  SELECT_ATTRS = (
    LANGUAGE_ATTRS +
    %i[
      travel_document_type
      visa_needed
      wheelchair_type
    ] +
    ALLERGIES.map { |allergy| :"allergy_#{allergy}_severity" }
  ).freeze

  DATE_ATTRS = %i[
    travel_document_issue_date
    travel_document_expiration_date
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
      jsonb_accessor :jamboree_data, attr, strip: true
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
    ALLERGIES.each do |allergy|
      i18n_enum :"allergy_#{allergy}_severity", ALLERGY_SEVERITIES, i18n_prefix: "#{ENUM_I18N}.jamboree_allergy_severities"
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
    non_visible_disability_details: :non_visible_disability
  ).freeze

  # The name for the name tag as shown when none was given: the stored
  # known_as_name keeps only what the person entered.
  def known_as_name_or_default = known_as_name.presence || nickname.presence || first_name

  # Where known_as_name_or_default comes from: :given, :nickname or :first_name.
  def known_as_name_source
    return :given if known_as_name.present?

    nickname.present? ? :nickname : :first_name
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
    self.class.public_send(:"#{attr}_labels").map { |value, label| [label, value.to_s] }
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
    self.medical_equipment_details = nil unless medical_equipment_needs.include?("other")
  end

  def medical_equipment_needs_known
    unknown = medical_equipment_needs - MEDICAL_EQUIPMENT
    errors.add(:medical_equipment_needs, :inclusion) if unknown.any?
  end
end
