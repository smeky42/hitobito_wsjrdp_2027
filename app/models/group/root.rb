# frozen_string_literal: true

# CMT
class Group::Root < ::Group
  self.layer = true

  children Group::Unit
  children Group::Ist
  children Group::Extern
  children Group::Root

  ### ROLES
  # Developers and Administrators
  class Admin < ::Role
    self.permissions = %i[layer_and_below_full admin finance_read finance]
    self.admin_only_assignment = true
  end

  # Leader (HoC, Unit Managers, ...)
  class Leader < ::Role
    self.permissions = [:layer_and_below_full]
  end

  # CMT Member
  class Member < ::Role
    self.permissions = []
  end

  # Read-only finance access for CMT members. Deliberately without any
  # layer_* permission, so the role grants no access to the
  # contingent's people on its own.
  class FinanceRead < ::Role
    self.permissions = [:finance_read]
    self.admin_only_assignment = true
  end

  # Finance (includes Leader permissions)
  class Finance < ::Role
    self.permissions = [:layer_and_below_full, :finance_read, :finance]
    self.admin_only_assignment = true
  end

  # Finance administration
  class FinanceAdmin < ::Role
    self.permissions = [:layer_and_below_full, :finance_read, :finance, :finance_admin]
    self.admin_only_assignment = true
  end

  roles Admin, Leader, Member, FinanceRead, Finance, FinanceAdmin
end
