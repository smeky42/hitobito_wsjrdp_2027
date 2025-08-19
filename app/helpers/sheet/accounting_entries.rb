# frozen_string_literal: true

#  Copyright (c) 2025, German Contingent for the Worldscoutjamboree 2027. This file is part of
#  hitobito_wsjrdp_2027 and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/hitobito/hitobito_wsjrdp_2027.

module Sheet
  class Person < Base
    class AccountingEntry < Base
      class_attribute :always_render_parent
      self.parent_sheet = Sheet::Person
      self.always_render_parent = true
    end

    class AccountingEntries < Base
      class_attribute :always_render_parent
      self.parent_sheet = Sheet::Person
      self.always_render_parent = true
    end
  end
end
