# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A person's registration status as the lists of the Beiträge area show it
# (the Reduktionen, the Individuelle Ratenpläne): in a word, coloured where it
# matters, the full label of Settings.status as the tooltip. The colours:
# fin/_person_status_styles.
module Fin::PersonStatusHelper
  # The status in colour where it matters: confirmed green, a noted
  # deregistration orange, a deregistration red.
  STATUS_CLASSES = {"confirmed" => "fin-status-confirmed",
                    "deregistration_noted" => "fin-status-noted",
                    "deregistered" => "fin-status-deregistered"}.freeze

  STATUS_WORDS = {"registered" => "registriert", "printed" => "gedruckt", "upload" => "hochgeladen",
                  "in_review" => "in Prüfung", "reviewed" => "geprüft", "confirmed" => "bestätigt",
                  "deregistration_noted" => "Abmeldung", "deregistered" => "abgemeldet"}.freeze

  def fin_person_status(person)
    status = person.status.to_s
    word = tag.span(STATUS_WORDS.fetch(status, status), class: STATUS_CLASSES[status])
    wsjrdp_tip(word, lines: [["Status", Settings.status[status].presence || status]])
  end
end
