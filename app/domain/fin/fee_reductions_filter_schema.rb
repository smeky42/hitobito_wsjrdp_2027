# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The Reduktionen dataset (Fin::FeeReductionsController) for the generic CNF
# filter (doc/wsjrdp/generic_filter_builder.md). It filters the PEOPLE before
# their rows are built, so every condition is SQL on `people`.
#
# A text search runs over names, hint and comment. Two yes/no attributes carry
# the quick filters (PRESETS): whether a reduction
# is planned (the planned values sit in additional_info -- jsonb_exists, as `?`
# would read as a bind placeholder) and whether the person is confirmed.
module Fin::FeeReductionsFilterSchema
  extend Wsjrdp::Filtering::FilterSchema

  YES_NO = Wsjrdp::Filtering::Options.values(-> { [%w[ja ja], %w[nein nein]] })

  STATUS_OPTIONS = Wsjrdp::Filtering::Options.values(-> { Settings.status.to_h.map { |key, label| [key.to_s, label] } })

  def self.yes_no(condition) = Arel.sql("CASE WHEN #{condition} THEN 'ja' ELSE 'nein' END")

  # The text search: the person's names, the reduction's hint and comment, the
  # active ones and the planned ones (in additional_info).
  def self.planned(t, key) = Arel::Nodes::InfixOperation.new("->>", t[:additional_info], Arel::Nodes.build_quoted(key))

  SCHEMA = Wsjrdp::Filtering::Schema.define do |s|
    s.attribute key: :search, short_key: :q, label: "Suche (Name, Hinweis, Kommentar)",
      type: Wsjrdp::Filtering::Types::TEXT, operators: Fin::DatevBookingsFilterSchema::TEXT_OPERATORS,
      column: ->(t) {
        [t[:first_name], t[:last_name], t[:nickname], t[:wsjrdp_total_fee_reduction_hint],
          t[:wsjrdp_total_fee_reduction_comment], planned(t, "planned_total_fee_reduction_hint"),
          planned(t, "planned_total_fee_reduction_comment")]
      }
    s.attribute key: :planned, short_key: :pl, label: "Geplante Reduktion",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: ->(_t) { yes_no("jsonb_exists(people.additional_info, 'planned_total_fee_reduction')") },
      options: YES_NO
    s.attribute key: :confirmed, short_key: :bs, label: "Bestätigt",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: ->(_t) { yes_no("people.status = 'confirmed'") },
      options: YES_NO
    s.attribute key: :status, short_key: :st, label: "Status",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: :status, options: STATUS_OPTIONS
  end

  # The quick filters: two exclusive groups, the unrestricted button (an
  # asterisk, "ohne Einschränkung") in front of each.
  PRESETS = [
    {group: "planned", attribute: "planned", operator: "in", exclusive: true,
     members: [{key: "planned", label: "geplant", value: "ja", icon: "clock"},
       {key: "not_planned", label: "ohne Plan", value: "nein"}]},
    {group: "confirmed", attribute: "confirmed", operator: "in", exclusive: true,
     members: [{key: "confirmed", label: "bestätigt", value: "ja"},
       {key: "not_confirmed", label: "nicht bestätigt", value: "nein"}]}
  ].freeze

  def self.bound(except: nil)
    SCHEMA.bind(Person.all, except: except)
  end
end
