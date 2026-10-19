# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp
  # Writes a log entry of the wagon: a PaperTrail version with an event of
  # Wsjrdp::LogEvents and its data in wsjrdp_data (doc/wsjrdp/log_entries.md).
  # It shows in the log of main (a person's or a group's), whatever item is.
  # Nothing is checked: an event, category or message of any kind is written
  # as given.
  module LogEntry
    module_function

    def record!(item, event, data = {}, main: item, whodunnit: PaperTrail.request.whodunnit,
      whodunnit_type: nil, additional_info: {}, object_changes: nil)
      attributes = {item: item, main: main, event: event, whodunnit: whodunnit,
                    wsjrdp_data: data.to_h, additional_info: additional_info.to_h,
                    object_changes: object_changes}
      attributes[:whodunnit_type] = whodunnit_type if whodunnit_type
      PaperTrail::Version.create!(attributes)
    end

    # A note: {"category" => category, "message" => message} and whatever data
    # holds besides (category and message win).
    def note!(item, category:, message:, data: {}, **options)
      record!(item, LogEvents::NOTE,
        data.to_h.stringify_keys.merge("category" => category, "message" => message), **options)
    end
  end
end
