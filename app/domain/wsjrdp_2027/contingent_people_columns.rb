# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # Column definitions of the people list on Kontingent > Übersicht: one
  # ContingentOverview::Entry per row, array-backed, so every column sorts by an
  # extractor. Without a chosen sort the list stands most urgent first (the
  # order of ContingentOverview::STATES), then by name.
  module ContingentPeopleColumns
    URGENCY = ContingentOverview::STATES.keys.each_with_index.to_h.freeze
    STATUS_ORDER = Settings.status.to_h.keys.map(&:to_s).each_with_index.to_h.freeze
    # The contract in the order of the finance lists (Fin::PersonStatusColumns).
    CONTRACT_ORDER = Wsjrdp2027::Person::CONTRACT_STATUSES.each_with_index.to_h.freeze

    COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "cocol") do |c|
      c.column key: "person", abbr: "p", label: "Person", width: "14rem", target_width: "22rem", grow: 2,
        truncate: true, sticky: true, sort: ->(e) { [e.name.downcase, e.id] }, default: true
      c.column key: "contract", abbr: "c", label: "Vertrag", width: "6.5rem",
        sort: ->(e) { [CONTRACT_ORDER.fetch(e.contract_status.to_s, 9), e.contract_confirmed_at || Date.new(0)] },
        default: true
      c.column key: "status", abbr: "s", label: "Status", width: "6.5rem",
        sort: ->(e) { STATUS_ORDER.fetch(e.status.to_s, 99) }, default: true
      c.column key: "reason", abbr: "r", label: "Grund", width: "12rem", target_width: "20rem", grow: 2,
        truncate: true, sort: ->(e) { URGENCY.fetch(e.state, 99) }, default: true
      c.column key: "group", abbr: "g", label: "Gruppe", width: "8rem", target_width: "12rem", grow: 1,
        truncate: true, sort: ->(e) { e.group_name.to_s.downcase }, default: true
      c.column key: "role", abbr: "ro", label: "Rolle", width: "6rem",
        sort: ->(e) { (e.role_difference || e.wsjrdp_role).to_s }, default: true
      c.column key: "patrol", abbr: "pt", label: "Patrol", width: "5rem",
        sort: ->(e) { [e.patrol ? 0 : 1, e.group_name.to_s.downcase, e.patrol.to_s] }
    end

    # The order while no sort is chosen: most urgent first, then by name.
    DEFAULT_ORDER = [["reason", "asc"], ["person", "asc"]].freeze

    def self.sort_lambdas = COLUMNS.sort_expressions
  end
end
