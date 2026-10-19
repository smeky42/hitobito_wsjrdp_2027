# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp
  # The events of the wagon's log entries (PaperTrail versions whose event
  # starts with PREFIX; doc/wsjrdp/log_entries.md) and the data each one has
  # in versions.wsjrdp_data. Per event:
  #
  # - params: the values its sentence (version.<event>) interpolates, by key
  #   and type (Wsjrdp2027::PaperTrail::VersionDecorator#wsjrdp_value),
  # - details: further values, one line "Label: value" each, when present,
  # - legacy: how an entry with no wsjrdp_data gets its data from the YAML in
  #   object_changes, for an event written before wsjrdp_data.
  #
  # A key of the data neither lists is not shown.
  module LogEvents
    PREFIX = "wsjrdp_"
    NOTE = "wsjrdp_note"

    EVENTS = {
      "wsjrdp_add_tag" => {
        params: {tag_name: :text},
        legacy: ->(changes) { {"tag_name" => Array(changes["tag"])[1]} }
      },
      "wsjrdp_remove_tag" => {
        params: {tag_name: :text},
        legacy: ->(changes) { {"tag_name" => Array(changes["tag"])[0]} }
      },
      NOTE => {
        params: {category: :note_category, message: :text}
      }
    }.freeze

    module_function

    def wsjrdp?(event) = event.to_s.start_with?(PREFIX)

    def definition(event) = EVENTS[event.to_s]

    # The data of a version with string keys: its wsjrdp_data, or, where that
    # is empty, what legacy makes of its object_changes; {} for none.
    def data(version)
      data = version.wsjrdp_data
      return data.stringify_keys if data.is_a?(Hash) && data.present?

      legacy_data(version)
    end

    def legacy_data(version)
      legacy = definition(version.event)&.dig(:legacy)
      return {} if legacy.nil? || version.object_changes.blank?

      changes = YAML.safe_load(version.object_changes, permitted_classes: [Date, Time, Symbol])
      changes.is_a?(Hash) ? legacy.call(changes).compact : {}
    rescue Psych::Exception
      {}
    end
  end
end
