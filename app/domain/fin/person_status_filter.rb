# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Registration status and participation contract of a person in the filters of
# the people lists of the Beiträge area (the Reduktionen, the Individuelle
# Ratenpläne): the attributes and the quick filter groups of the contract and
# of the confirmation.
#
#   SCHEMA = Wsjrdp::Filtering::Schema.define do |s|
#     ...
#     Fin::PersonStatusFilter.attributes(s)
#   end
#   PRESETS = [..., Fin::PersonStatusFilter::CONTRACT_PRESET, ...]
module Fin::PersonStatusFilter
  STATUS_OPTIONS = Wsjrdp::Filtering::Options.values(-> { Settings.status.to_h.map { |key, label| [key.to_s, label] } })

  CONTRACT_STATUS_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    ::Person::CONTRACT_STATUSES.map { |key| [key, Settings.contract_status[key].presence || key] }
  })

  # The quick filter group of the contract, on the contract as stored: in
  # force, waiting for its replacement, none (never one or ended).
  CONTRACT_PRESET = {group: "contract", attribute: "contract_status", operator: "in", exclusive: true,
                     members: [{key: "contract_active", label: "Vertrag besteht", value: "confirmed"},
                       {key: "contract_pending", label: "ausstehend", value: "replacement_pending"},
                       {key: "contract_none", label: "ohne Vertrag oder beendet", value: %w[none ended]}]}.freeze

  # The quick filter group of the confirmation (the attribute `confirmed` of
  # the dataset's schema). Not offered at the moment: the lists show the
  # contract instead.
  CONFIRMED_PRESET = {group: "confirmed", attribute: "confirmed", operator: "in", exclusive: true,
                      members: [{key: "confirmed", label: "bestätigt", value: "ja"},
                        {key: "not_confirmed", label: "nicht bestätigt", value: "nein"}]}.freeze

  # The registration status and the contract.
  def self.attributes(s)
    s.attribute key: :status, short_key: :st, label: "Status",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: :status, options: STATUS_OPTIONS
    s.attribute key: :contract_status, short_key: :ctst, label: "Vertrag",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: :contract_status, options: CONTRACT_STATUS_OPTIONS
  end
end
