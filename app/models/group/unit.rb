# frozen_string_literal: true

# Units
class Group::Unit < ::Group
  self.layer = true

  ### ROLES
  # Unit Manager
  class Manager < ::Role
    self.permissions = [:layer_and_below_full]
  end

  # Unit Leader
  class Leader < ::Role
    self.permissions = [:group_full]
  end

  # Youth Participant
  class Member < ::Role
    self.permissions = []
  end

  roles Manager, Leader, Member
end
