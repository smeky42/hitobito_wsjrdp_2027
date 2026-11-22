# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The Moss users dataset for the generic CNF filter
# (doc/wsjrdp/generic_filter_builder.md). Every condition is SQL on
# `moss_users`.
module Fin::MossUsersFilterSchema
  extend Wsjrdp::Filtering::FilterSchema

  KNOWN_STATUSES = [MossUser::STATUS_INVITED, MossUser::STATUS_ACTIVE, MossUser::STATUS_DEACTIVATED].freeze

  STATUS_OPTIONS = Fin::MossOrganisationFilter.status_options(MossUser, KNOWN_STATUSES)

  # Every role a user in the table holds, with its German label.
  ROLE_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    MossUser.distinct.pluck(Arel.sql("unnest(roles)")).sort
      .map { |role| [role, I18n.t("fin.moss_organisation.roles.#{role}", default: role)] }
  })

  TEAM_OPTIONS = Wsjrdp::Filtering::Options.from(-> { MossTeam.order(:name) },
    value: :moss_team_uuid, label: :to_s)

  # `roles` is an array: "ist" matches a user holding ANY of the chosen roles
  # (overlap), "ist nicht" one holding none of them.
  def self.roles_overlap(column, roles)
    quoted = roles.map { |role| MossUser.connection.quote(role) }.join(", ")
    Arel::Nodes::InfixOperation.new("&&", column, Arel.sql("ARRAY[#{quoted}]::varchar[]"))
  end

  ROLES_TYPE = Wsjrdp::Filtering::Type.new(key: :enum, control: "select", operators: [
    Wsjrdp::Filtering::Operator.new(key: :in, label: "ist", arity: :many,
      **Wsjrdp::Filtering::Types::IN_MANY) { |c, v| roles_overlap(c, v) },
    Wsjrdp::Filtering::Operator.new(key: :not_in, label: "ist nicht", arity: :many,
      **Wsjrdp::Filtering::Types::NOT_IN_MANY) { |c, v| Arel::Nodes::Not.new(Arel::Nodes::Grouping.new(roles_overlap(c, v))) }
  ])

  SCHEMA = Wsjrdp::Filtering::Schema.define do |s|
    # Searches the first and last name, the two together, and the e-mail.
    s.attribute key: :name, short_key: :q, label: "Name / E-Mail",
      type: Wsjrdp::Filtering::Types::TEXT, operators: Fin::MossOrganisationFilter::TEXT_OPERATORS,
      column: ->(t) { [t[:first_name], t[:last_name], Arel.sql(Fin::MossUsersColumns::NAME_SQL), t[:email]] }
    s.attribute key: :status, short_key: :st, label: "Status",
      type: Fin::MossOrganisationFilter::STATUS, operators: %i[in not_in blank],
      column: :status, options: STATUS_OPTIONS
    s.attribute key: :roles, short_key: :rl, label: "Rolle",
      type: ROLES_TYPE, operators: %i[in not_in], column: :roles, options: ROLE_OPTIONS
    s.attribute key: :team, short_key: :tm, label: "Team",
      type: Fin::MossOrganisationFilter::UUID_REFERENCE, operators: %i[in not_in present blank],
      column: :moss_team_uuid, options: TEAM_OPTIONS
    s.attribute key: :person_linked, short_key: :pl, label: "Person verknüpft",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: ->(_t) { Fin::MossOrganisationFilter.yes_no("moss_users.person_id IS NOT NULL") },
      options: Fin::MossOrganisationFilter::YES_NO
    Fin::MossOrganisationFilter.common_attributes(s, "moss_users")
  end

  # Quick filter on the status: all but deactivated users by default.
  STATUS_GROUP = {key: "status", multiple: true, attribute: "status", default: %w[active invited others],
                  all_title: "Alle wählen bzw. abwählen",
                  members: [
                    {key: "active", label: "Aktiv", value: MossUser::STATUS_ACTIVE},
                    {key: "invited", label: "Eingeladen", value: MossUser::STATUS_INVITED},
                    {key: "deactivated", label: "Deaktiviert", value: MossUser::STATUS_DEACTIVATED},
                    {key: "others", label: "Andere Status", others: true,
                     title: "Andere Status (z. B. Versteckt, Einladung vorbereitet) und ohne Status"}
                  ]}.freeze

  # The Schnellauswahl: fixed conditions, shown locked, kept apart from the
  # user's own. A users table's filter policy takes it over.
  QUICK_FILTER = {
    fixed_groups: [STATUS_GROUP, Fin::MossOrganisationFilter::IN_MOSS_GROUP],
    fixed: [{key: "without_person", optional: true, slots: [[["person_linked", "in", "nein"]]]}],
    presets: [{key: "without_person", label: "Keine Person verknüpft", pins: %w[without_person]}]
  }.freeze

  def self.bound(except: nil)
    SCHEMA.bind(MossUser.all, except: except)
  end
end
