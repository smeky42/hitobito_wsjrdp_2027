# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The Moss teams dataset for the generic CNF filter
# (doc/wsjrdp/generic_filter_builder.md). Every condition is SQL on
# `moss_teams`; the user count is the list's own subquery.
module Fin::MossTeamsFilterSchema
  extend Wsjrdp::Filtering::FilterSchema

  KNOWN_STATUSES = [MossTeam::STATUS_ACTIVE, MossTeam::STATUS_ARCHIVED].freeze

  STATUS_OPTIONS = Fin::MossOrganisationFilter.status_options(MossTeam, KNOWN_STATUSES)

  DEPARTMENT_OPTIONS = Wsjrdp::Filtering::Options.from(-> { MossDepartment.order(:name) },
    value: :moss_department_uuid, label: :to_s)

  COUNT_OPERATORS = %i[nonzero between lte gte lt gt eq].freeze

  SCHEMA = Wsjrdp::Filtering::Schema.define do |s|
    s.attribute key: :name, short_key: :q, label: "Name",
      type: Wsjrdp::Filtering::Types::TEXT, operators: Fin::MossOrganisationFilter::TEXT_OPERATORS,
      column: :name
    s.attribute key: :status, short_key: :st, label: "Status",
      type: Fin::MossOrganisationFilter::STATUS, operators: %i[in not_in blank],
      column: :status, options: STATUS_OPTIONS
    s.attribute key: :department, short_key: :dp, label: "Abteilung",
      type: Fin::MossOrganisationFilter::UUID_REFERENCE, operators: %i[in not_in present blank],
      column: :moss_department_uuid, options: DEPARTMENT_OPTIONS
    # A count; "≠ 0" first, "has users at all".
    s.attribute key: :user_count, short_key: :uc, label: "Benutzer",
      type: Wsjrdp::Filtering::Types::DECIMAL, operators: COUNT_OPERATORS,
      column: ->(_t) { Arel.sql(Fin::MossTeamsColumns::USER_COUNT_SQL) }
    Fin::MossOrganisationFilter.common_attributes(s, "moss_teams")
  end

  # Quick filter on the status: all but archived teams by default.
  STATUS_GROUP = {key: "status", multiple: true, attribute: "status", default: %w[active others],
                  all_title: "Alle wählen bzw. abwählen",
                  members: [
                    {key: "active", label: "Aktiv", value: MossTeam::STATUS_ACTIVE},
                    {key: "archived", label: "Archiviert", value: MossTeam::STATUS_ARCHIVED},
                    {key: "others", label: "Andere Status", others: true, title: "Andere Status und ohne Status"}
                  ]}.freeze

  QUICK_FILTER = {
    fixed_groups: [STATUS_GROUP, Fin::MossOrganisationFilter::IN_MOSS_GROUP],
    fixed: [{key: "with_users", optional: true, slots: [[["user_count", "nonzero"]]]}],
    presets: [{key: "with_users", label: "Nur mit Benutzern", pins: %w[with_users]}]
  }.freeze

  def self.bound(except: nil)
    SCHEMA.bind(MossTeam.all, except: except)
  end
end
