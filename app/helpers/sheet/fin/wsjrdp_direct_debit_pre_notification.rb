# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  class Fin::WsjrdpDirectDebitPreNotification < Base
    self.parent_sheet = Sheet::Person

    def title
      "Lastschrift Pre-Notification #{entry.id}"
    end

    def current_parent_nav_path
      view.person_accounting_path(entry.person)
    end
  end
end
