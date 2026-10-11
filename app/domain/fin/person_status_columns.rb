# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The columns "Vertrag" and "Status" of the people lists of the Beiträge area
# (the Reduktionen, the Individuelle Ratenpläne), for rows with a #person. The
# cells: Fin::PersonStatusHelper#fin_person_cell.
#
#   COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "...") do |c|
#     ...
#     Fin::PersonStatusColumns.define(c)
#   end
module Fin::PersonStatusColumns
  KEYS = %w[contract status].freeze

  def self.define(c)
    # The participation contract (people.contract_status), in a word -- what
    # the payment runs collect by; the full label and its dates are the
    # tooltip.
    c.column key: "contract", abbr: "ctrct", label: "Vertrag", header_tooltip: "Status vom Teilnahmevertrag",
      width: "5.25rem",
      sort: ->(row) { ::Person::CONTRACT_STATUSES.index(row.person.contract_status.to_s) || -1 }, default: true
    # The registration status (people.status), in a word; the full label is the
    # cell's tooltip. Hidden by default: the contract names it where the two
    # do not go together.
    c.column key: "status", abbr: "st", label: "Status", width: "5.5rem",
      sort: ->(row) { Settings.status.keys.map(&:to_s).index(row.person.status.to_s) || -1 }
  end
end
