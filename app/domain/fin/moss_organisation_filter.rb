# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# What the filters of the Moss users, teams and departments share
# (Fin::MossUsersFilterSchema and its siblings): yes/no options, the text
# operators, the status options and the two attributes every one of the three
# has -- the comment and whether the row is still in Moss.
module Fin::MossOrganisationFilter
  YES_NO = Wsjrdp::Filtering::Options.values(-> { [%w[ja ja], %w[nein nein]] })

  TEXT_OPERATORS = %i[
    contains contains_cs not_contains not_contains_cs glob glob_cs eq eq_cs regex regex_cs
  ].freeze

  # A reference to another Moss record by its uuid column. A value that is no
  # uuid drops the condition (a uuid column would reject it).
  UUID_PATTERN = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
  UUID_CAST = ->(value) { value.to_s if value.to_s.match?(UUID_PATTERN) }
  UUID_REFERENCE = Wsjrdp::Filtering::Type.new(key: :reference, control: "multiselect", operators: [
    Wsjrdp::Filtering::Operator.new(key: :in, label: "ist", arity: :many, cast: UUID_CAST,
      **Wsjrdp::Filtering::Types::IN_MANY) { |c, v| c.in(v) },
    Wsjrdp::Filtering::Operator.new(key: :not_in, label: "ist nicht", arity: :many, cast: UUID_CAST,
      **Wsjrdp::Filtering::Types::NOT_IN_MANY) { |c, v| c.not_in(v) },
    Wsjrdp::Filtering::Operator.new(key: :present, label: "hat Wert", arity: :none) { |c, _| c.not_eq(nil) },
    Wsjrdp::Filtering::Operator.new(key: :blank, label: "ist leer", arity: :none) { |c, _| c.eq(nil) }
  ])

  # A Moss status: one of the values, or none (the quick filter's "others").
  STATUS = Wsjrdp::Filtering::Type.new(key: :enum, control: "select", operators: [
    *Wsjrdp::Filtering::Types::ENUM.operators.values,
    Wsjrdp::Filtering::Operator.new(key: :blank, label: "ist leer", arity: :none) { |c, _| c.eq(nil) }
  ])

  def self.yes_no(condition) = Arel.sql("CASE WHEN #{condition} THEN 'ja' ELSE 'nein' END")

  # The known statuses first, then any other the table holds, each with its
  # German label (fin.moss_organisation.statuses).
  def self.status_options(model, known)
    Wsjrdp::Filtering::Options.values(-> {
      (known + model.distinct.where.not(status: nil).pluck(:status).sort).uniq
        .map { |status| [status, status_label(status)] }
    })
  end

  def self.status_label(status)
    I18n.t("fin.moss_organisation.statuses.#{status}", default: status.to_s)
  end

  # The comment and the "in Moss" flag, last in the picker.
  def self.common_attributes(s, table)
    s.attribute key: :comment, short_key: :cm, label: "Kommentar",
      type: Wsjrdp::Filtering::Types::TEXT, operators: TEXT_OPERATORS, column: :comment
    s.attribute key: :in_moss, short_key: :im, label: "In Moss",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: ->(_t) { yes_no("#{table}.moss_removed_at IS NULL") }, options: YES_NO
  end

  IN_MOSS_EXPLANATION = "Ein Eintrag ist „in Moss“, solange der letzte Abgleich mit Moss ihn noch " \
    "geliefert hat. Fehlt er in einem späteren Abgleich – etwa weil er in Moss gelöscht wurde –, " \
    "bleibt er in Hitobito erhalten, gilt aber als „nicht in Moss“ (grau, mit dem Hinweis „entfernt“)."

  # Quick filter: is the row still in Moss? Starts with "In Moss".
  IN_MOSS_GROUP = {key: "in_moss", multiple: true, attribute: "in_moss", default: %w[in_moss],
                   all_title: "Beide wählen bzw. abwählen. #{IN_MOSS_EXPLANATION}",
                   members: [
                     {key: "in_moss", label: "In Moss", value: "ja",
                      title: "Einträge, die Moss noch liefert. #{IN_MOSS_EXPLANATION}"},
                     {key: "not_in_moss", label: "Nicht in Moss", value: "nein",
                      title: "Einträge, die Moss nicht mehr liefert. #{IN_MOSS_EXPLANATION}"}
                   ]}.freeze
end
