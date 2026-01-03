# frozen_string_literal: true

# CMT
class Group::Root < ::Group
  self.layer = true

  children Group::Unit
  children Group::Ist

  ### ROLES
  # Developers and Administrators
  class Admin < ::Role
    self.permissions = %i[layer_and_below_full admin finance]
  end

  # Leader (HoC, Unit Managers, ...)
  class Leader < ::Role
    self.permissions = [:layer_and_below_full]
  end

  # Finance (includes Leader permissions)
  class Finance < ::Role
    self.permissions = [:layer_and_below_full, :finance]
  end

  # CMT Member
  class Member < ::Role
    self.permissions = []
  end

  roles Admin, Leader, Member, Finance
end
