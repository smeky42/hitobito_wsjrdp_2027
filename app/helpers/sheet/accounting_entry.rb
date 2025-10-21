# frozen_string_literal: true

#  Copyright (c) 2025, German Contingent for the Worldscoutjamboree 2027. This file is part of
#  hitobito_wsjrdp_2027 and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/hitobito/hitobito_wsjrdp_2027.

module Sheet
  class AccountingEntry < Base
    self.parent_sheet = Sheet::Person

    def current_parent_nav_path
      view.accounting_group_person_path(entry.group, entry.person)
    end
  end
end
