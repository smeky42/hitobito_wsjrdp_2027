# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # The people list of Kontingent > Übersicht for the generic CNF filter: an
  # array-backed dataset (doc/wsjrdp/generic_filter_builder.md, "Filtering
  # arrays") over Wsjrdp2027::ContingentOverview::Entry, filtered in Ruby.
  #
  # THE one definition of what a list on the page means: the cells of the
  # matrix (.cell_tree), the default (DEFAULT) and the Schnellauswahl
  # (PRESETS) are filter trees over this schema. The matrix column of a
  # person (ContingentOverview.contract_column) and the roles are computed
  # once, in Ruby, by ContingentOverview.
  module ContingentPeopleFilterSchema
    extend Wsjrdp::Filtering::ArrayFilterSchema

    GROUP_KINDS = {"wsjrdp" => "WSJRDP-Gruppe", "waitlist" => "Warteliste", "other" => "andere Gruppe"}.freeze
    ROLES = %w[CMT BMT IST UL YP EXT].freeze
    WSJ_ROLES = %w[CMT IST UL YP JPT EXT].freeze
    YES_NO = {"yes" => "ja", "no" => "nein"}.freeze

    SOURCE = Wsjrdp::Filtering::ArraySource.define(:contingent_people) do |s|
      s.field :name, :text
      s.field :need, :text
      s.field :group_kind, :text
      s.field :group_name, :text
      s.field :wsjrdp_role, :text
      s.field :wsj_role, :text
      s.field :role_diff, :text, ->(entry) { entry.role_difference ? "yes" : "no" }
      s.field :status, :text
      s.field :contract_status, :text
      s.field :patrol, :text
      s.field :contract_column, :text
    end

    # The matrix columns a person can fall into, by their name in the filter.
    CONTRACT_COLUMNS = ContingentOverview::MATRIX_COLUMNS.reject { |_, c| c[:subtotal] }
      .transform_values { |c| c[:filter_label] || c[:label] }.freeze

    # The patrols to choose from: none, then every patrol of every WSJRDP unit
    # (Group::PatrolsController::PATROLS), by unit name.
    PATROL_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
      units = ::Group.where(type: "Group::Unit", is_wsjrdp: true).order(:name).pluck(:id, :name)
      [["none", "keine Patrol"]] + units.flat_map do |id, name|
        ::Group::PatrolsController::PATROLS.map { |letter| ["#{id}-#{letter}", "#{name} · Patrol #{letter}"] }
      end
    })

    ENUM = Wsjrdp::Filtering::Types::ENUM
    TEXT_OPERATORS = %i[contains not_contains eq].freeze

    SCHEMA = Wsjrdp::Filtering::Schema.define do |s|
      # The column of the matrix "Kontingents-Rolle und Vertrag": "offen" and
      # "ohne Vertrag" in WSJRDP groups only, "in Abmeldung" and "abgemeldet"
      # in all; nobody else has a value.
      s.attribute key: :contract_column, short_key: :vs, label: "Vertrags-Spalte",
        type: ENUM, operators: %i[in not_in], column: :contract_column,
        options: Wsjrdp::Filtering::Options.values(-> { CONTRACT_COLUMNS.to_a })
      s.attribute key: :need, short_key: :nd, label: "Handlungsbedarf",
        type: ENUM, operators: %i[in not_in], column: :need,
        options: Wsjrdp::Filtering::Options.values(-> { ContingentOverview::NEEDS.to_a + [["none", "keiner"]] })
      s.attribute key: :group_kind, short_key: :gk, label: "Gruppen-Art",
        type: ENUM, operators: %i[in not_in], column: :group_kind,
        options: Wsjrdp::Filtering::Options.values(-> { GROUP_KINDS.to_a })
      s.attribute key: :wsjrdp_role, short_key: :ro, label: "Kontingents-Rolle", group: "Rolle",
        type: ENUM, operators: %i[in not_in], column: :wsjrdp_role,
        options: Wsjrdp::Filtering::Options.values(-> { ROLES.map { |r| [r, r] } })
      s.attribute key: :wsj_role, short_key: :wr, label: "Jamboree-Rolle", group: "Rolle",
        type: ENUM, operators: %i[in not_in], column: :wsj_role,
        options: Wsjrdp::Filtering::Options.values(-> { WSJ_ROLES.map { |r| [r, r] } })
      s.attribute key: :role_diff, short_key: :rd, label: "Rolle abweichend", group: "Rolle",
        type: ENUM, operators: %i[in], column: :role_diff,
        options: Wsjrdp::Filtering::Options.values(-> { YES_NO.to_a })
      # The registration status and the contract as stored, as on the finance
      # lists (Fin::PersonStatusFilter).
      Fin::PersonStatusFilter.attributes(s)
      # One patrol, several, or none ("none": an UL or YP of a unit without
      # one); people outside a unit have no value and match neither.
      s.attribute key: :patrol, short_key: :pt, label: "Patrol", group: "Unit",
        type: ENUM, operators: %i[in not_in], column: :patrol, options: PATROL_OPTIONS
      s.attribute key: :name, short_key: :q, label: "Name", group: "Text",
        type: Wsjrdp::Filtering::Types::TEXT, operators: TEXT_OPERATORS, column: :name
      s.attribute key: :group_name, short_key: :gn, label: "Gruppe", group: "Text",
        type: Wsjrdp::Filtering::Types::TEXT, operators: TEXT_OPERATORS, column: :group_name
    end

    # What the list shows while the user has chosen nothing: the people not
    # settled yet -- the matrix columns "offen", "in Abmeldung" and
    # "ohne Vertrag", over all its rows.
    DEFAULT = [[["contract_column", "in", "docs", "cancel", "none"]]].freeze

    # The Schnellauswahl: what needs doing as a group whose buttons widen each
    # other -- all of them pressed is "Handlungsbedarf" --, the kind of group
    # as an exclusive one, and the role differences.
    PRESETS = [
      {group: "need", attribute: "need", operator: "in",
       members: ContingentOverview::NEEDS.map { |value, label| {key: value, label: label, value: value} }},
      {group: "group_kind", attribute: "group_kind", operator: "in", exclusive: true,
       members: [{key: "wsjrdp", label: "WSJRDP-Gruppen", value: "wsjrdp"},
         {key: "waitlist", label: "Wartelisten", value: "waitlist"}]},
      {key: "role_diff", label: "Rolle abweichend", slots: [[["role_diff", "in", "yes"]]]}
    ].freeze

    def self.bound(except: nil) = SCHEMA.bind(SOURCE, except: except)

    def self.array_strategy = :ruby

    # The entries a host-authored tree leaves (strict: a typo raises).
    def self.apply(tree, entries)
      schema = bound
      compile(parse_fixed!(tree, schema: schema, what: "contingent filter"), schema: schema, relation: entries)
    end

    # The tree of a cell of the matrix: its column or columns (a row's sum:
    # the columns it adds up; a subtotal: the columns it adds up), and the
    # row's jamboree roles (wsj / wsj_not) and contingent roles
    # (roles / roles_not).
    def self.cell_tree(column_keys, wsj: nil, wsj_not: nil, roles: nil, roles_not: nil)
      keys = Array(column_keys).flat_map { |key| ContingentOverview::MATRIX_COLUMNS.fetch(key)[:subtotal] || [key] }
      [[["contract_column", "in", *keys]],
        *([[["wsj_role", "in", *wsj]]] if wsj), *([[["wsj_role", "not_in", *wsj_not]]] if wsj_not),
        *([[["wsjrdp_role", "in", *roles]]] if roles), *([[["wsjrdp_role", "not_in", *roles_not]]] if roles_not)]
    end
  end
end
