# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Sheet
  class Person < Base
    class JamboreeData < Base
      class_attribute :always_render_parent

      self.parent_sheet = Sheet::Person
      self.always_render_parent = true
    end

    # The core finds a controller's sheet by its singular name
    # (Sheet::Base.controller_sheet_class): Person::JamboreeDataController
    # looks for JamboreeDatum.
    JamboreeDatum = JamboreeData
  end
end
