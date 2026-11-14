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
    self.permissions = %i[layer_and_below_full admin impersonation finance_read finance_audit finance contingent_read]
    self.admin_only_assignment = true
  end

  # Leader (HoC, Unit Managers, ...)
  class Leader < ::Role
    self.permissions = [:layer_and_below_full, :contingent_read]
  end

  # CMT Member
  class Member < ::Role
    self.permissions = []
  end

  # Read-only finance access for CMT members. Deliberately without any
  # layer_* permission, so the role grants no access to the
  # contingent's people on its own.
  class FinanceReader < ::Role
    self.permissions = [:finance_read]
    self.admin_only_assignment = true
  end

  # Read-only access to the contingent pages. Deliberately without any
  # layer_* permission, so the role grants no access to the
  # contingent's people on its own.
  class ContingentReader < ::Role
    self.permissions = [:contingent_read]
    self.admin_only_assignment = true
  end

  # Finance (includes Leader permissions)
  class Finance < ::Role
    self.permissions = [:layer_and_below_full, :finance_read, :finance_audit, :finance, :contingent_read]
    self.admin_only_assignment = true
  end

  # Finance administration
  class FinanceManager < ::Role
    self.permissions = [:layer_and_below_full, :finance_read, :finance_audit, :finance, :finance_manage, :contingent_read]
    self.admin_only_assignment = true
  end

  # Head of Contingent (HoC): the permissions of Leader, Finance,
  # ContingentReader and Member together, read from those roles (defined
  # above), so they follow them. Array#| keeps each permission once.
  class HeadOfContingent < ::Role
    self.permissions = Leader.permissions | Finance.permissions | ContingentReader.permissions | Member.permissions
    self.admin_only_assignment = true
  end

  # Extended Head of Contingent (eHoC): the permissions of FinanceReader,
  # ContingentReader and Member together, read from those roles (defined
  # above), each once.
  class ExtendedHeadOfContingent < ::Role
    self.permissions = FinanceReader.permissions | ContingentReader.permissions | Member.permissions
    self.admin_only_assignment = true
  end

  roles Admin, Leader, Member, FinanceReader, ContingentReader, Finance, FinanceManager, HeadOfContingent,
    ExtendedHeadOfContingent
end
