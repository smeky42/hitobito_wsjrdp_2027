# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # The unit list of Kontingent > Units for the generic CNF filter: an
  # array-backed dataset (doc/wsjrdp/generic_filter_builder.md, "Filtering
  # arrays") over Wsjrdp2027::ContingentUnits::Unit, filtered in Ruby. The page
  # shows only its Schnellauswahl (PRESETS), two exclusive groups:
  #
  # - the series, by the first letter of a unit's name (A1 … K6), and
  # - what to look at: units whose contracts in force do not add up to the
  #   size the unit is to have (Group#effective_expected_unit_size, 40 by
  #   the rule), units with people in Abmeldung, and units whose
  #   people in force are not all in a patrol yet. A unit may
  #   be both, so the checks are one list field (:integer_list, CHECKS) that
  #   `ist` matches by any of its elements.
  module ContingentUnitsFilterSchema
    extend Wsjrdp::Filtering::ArrayFilterSchema

    SERIES = %w[A B D E K].freeze
    CHECKS = {1 => "Summe ≠ Soll-Größe", 2 => "offene Abmeldungen", 3 => "Patrols unvollständig"}.freeze

    def self.checks(unit)
      [(1 if unit.in_force_total != unit.target_size), (2 if unit.cancelling.positive?),
        (3 if unit.patrols_incomplete?)].compact
    end

    SOURCE = Wsjrdp::Filtering::ArraySource.define(:contingent_units) do |s|
      s.field :name, :text
      s.field :series, :text, ->(unit) { unit.name.to_s[0].to_s.upcase }
      s.field :checks, :integer_list, ->(unit) { ContingentUnitsFilterSchema.checks(unit) }
    end

    SCHEMA = Wsjrdp::Filtering::Schema.define do |s|
      s.attribute key: :series, short_key: :se, label: "Serie",
        type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in], column: :series,
        options: Wsjrdp::Filtering::Options.values(-> { SERIES.map { |letter| [letter, "#{letter}-Units"] } })
      s.attribute key: :check, short_key: :ch, label: "Auffällig",
        type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in], column: :checks,
        options: Wsjrdp::Filtering::Options.values(-> { CHECKS.to_a })
      s.attribute key: :name, short_key: :q, label: "Name",
        type: Wsjrdp::Filtering::Types::TEXT, operators: %i[contains eq], column: :name
    end

    PRESETS = [
      {group: "series", attribute: "series", operator: "in", exclusive: true,
       members: SERIES.map { |letter| {key: "series_#{letter.downcase}", label: "#{letter}-Units", value: letter} }},
      {group: "check", attribute: "check", operator: "in", exclusive: true,
       members: [{key: "not_full", label: CHECKS.fetch(1), value: 1},
         {key: "cancelling", label: CHECKS.fetch(2), value: 2},
         {key: "patrols", label: CHECKS.fetch(3), value: 3}]}
    ].freeze

    def self.bound(except: nil) = SCHEMA.bind(SOURCE, except: except)

    def self.array_strategy = :ruby
  end
end
