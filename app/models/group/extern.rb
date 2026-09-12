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

  # Read-only finance access for external auditors. :finance_audit adds
  # the person-level finance VIEWS on top of :finance_read -- the
  # Beitragsbuchungen and fin/person_fees -- and nothing else: no
  # layer_* permission, so the role still grants no access to a
  # person's own page or data.
  class FinanceAuditor < ::Role
    self.permissions = %i[finance_read finance_audit]
    self.admin_only_assignment = true
  end

  # An external accountant: everything the auditor sees, plus the write
  # tier for the bookkeeping work itself. Like the auditor it holds no
  # layer_* permission.
  class FinanceAccountant < ::Role
    self.permissions = %i[finance_read finance_audit finance]
    self.admin_only_assignment = true
  end

  roles Member, FinanceAuditor, FinanceAccountant
end
