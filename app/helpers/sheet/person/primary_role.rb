# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The page "Hauptgruppe/Rolle wechseln" (Person::PrimaryRoleController) under
# the person's tabs, as the status page: its paths lie below the status
# page's, so the status tab is the active one.
module Sheet
  class Person < Base
    class PrimaryRole < Base
      class_attribute :always_render_parent

      self.parent_sheet = Sheet::Person
      self.always_render_parent = true
    end
  end
end
