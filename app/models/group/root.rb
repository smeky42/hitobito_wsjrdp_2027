# frozen_string_literal: true

# CMT
class Group::Root < ::Group
  self.layer = true

  children Group::Unit
  children Group::Ist

  ### ROLES
  # Developers and Administrators
  class Admin < ::Role
    self.permissions = %i[layer_and_below_full admin]
  end

  # HoC, Finance
  class Leader < ::Role
    self.permissions = [:layer_and_below_full]
  end

  # CMT Member
  class Member < ::Role
    self.permissions = []
  end

  roles Admin, Leader, Member
end
