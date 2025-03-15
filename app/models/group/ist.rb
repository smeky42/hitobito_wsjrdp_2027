# frozen_string_literal: true

# IST
class Group::Ist < ::Group
  self.layer = true

  children Group::Ist

  ### ROLES
  # MIST
  class Leader < ::Role
    self.permissions = [:layer_and_below_full, :event]
  end

  # IST Member
  class Member < ::Role
    self.permissions = []
  end

  roles Leader, Member
end
