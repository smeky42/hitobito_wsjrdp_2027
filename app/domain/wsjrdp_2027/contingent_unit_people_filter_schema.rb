# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # The people of one unit on Kontingent > Units for the generic CNF filter:
  # the fields and attributes of the overview's people list
  # (ContingentPeopleFilterSchema) and one more, whether a person still
  # belongs to the unit -- which only the unit knows, so its rows are
  # ContingentUnits::UnitPerson (an entry and its `presence` there):
  #
  # - "current": in the unit, in Abmeldung or deregistered from it
  # - "moved": left it for another group, by a swap or not
  #
  # The table shows the people of the unit while nobody asks for more
  # (PRESENCE_GROUP, a switch of the filter line).
  #
  # The patrol is the bare letter here (people.patrol, "A" … "D") or "none"
  # for an UL or YP not in a patrol yet: one unit, so the overview's
  # "<unit id>-<letter>" with a choice per unit is not needed.
  module ContingentUnitPeopleFilterSchema
    extend Wsjrdp::Filtering::ArrayFilterSchema

    PRESENCES = {"current" => "in der Unit", "moved" => "gewechselt / getauscht"}.freeze

    SOURCE = Wsjrdp::Filtering::ArraySource.define(:contingent_unit_people) do |s|
      ContingentPeopleFilterSchema::SOURCE.fields.each_value { |field| s.field(field.name, field.sql_type, field.reader) }
      s.field :presence, :text
      s.field :patrol_letter, :text, ->(row) { row.patrol&.split("-")&.last }
    end

    PATROL_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
      [["none", "nicht gesetzt"]] + ::Group::PatrolsController::PATROLS.map { |letter| [letter, "Patrol #{letter}"] }
    })

    SCHEMA = ContingentPeopleFilterSchema::SCHEMA.derive do |s|
      s.remove :patrol
      s.attribute key: :patrol, short_key: :pt, label: "Patrol", group: "Unit",
        type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in], column: :patrol_letter,
        options: PATROL_OPTIONS
      s.attribute key: :presence, short_key: :pr, label: "In der Unit", group: "Unit",
        type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in], column: :presence,
        options: Wsjrdp::Filtering::Options.values(-> { PRESENCES.to_a })
    end

    # Who moved to another group shows only on request: hidden by default,
    # one click shows them along.
    PRESENCE_GROUP = {key: "moved", label: "Gewechselte / Getauschte", default: "hidden", show: :hidden,
                      members: [{key: "hidden", label: "ausblenden", slots: [[["presence", "in", "current"]]]},
                        {key: "shown", label: "anzeigen", slots: [[["presence", "in", "current", "moved"]]]}]}.freeze

    def self.bound(except: nil) = SCHEMA.bind(SOURCE, except: except)

    def self.array_strategy = :ruby
  end
end
