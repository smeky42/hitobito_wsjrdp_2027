# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The base of the /fin section. Its pages share a sheet and a left nav, and
# how they word a save that failed its validation.
class Fin::FinController < ApplicationController
  private

  # The alert of a save that failed its validation: every message of the
  # record, as the finance pages word it ("Fehler: ...").
  def validation_alert(record)
    "Fehler: #{record.errors.full_messages.join(", ")}"
  end
end
