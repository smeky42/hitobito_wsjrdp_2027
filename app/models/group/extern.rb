# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class Group::Extern < ::Group
  self.layer = true

  class Member < ::Role
    self.permissions = []
  end

  # Read-only finance access for auditors: the finance data and
  # nothing else. No layer_* permission, so the role grants no access
  # to any person's data.
  class FinanceAuditor < ::Role
    self.permissions = [:finance_read]
    self.admin_only_assignment = true
  end

  roles Member, FinanceAuditor
end
