# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027::Role
  extend ActiveSupport::Concern

  included do
    # Marks a role type whose assignment is reserved to CMT admins: only
    # people with the :admin permission may create or update such roles, and
    # only they may take one away from ANOTHER person (see the general
    # constraints in Wsjrdp2027::RoleAbility). Role classes opt in with
    # `self.admin_only_assignment = true` (Group::Root::Admin,
    # Group::Root::Finance, ...).
    class_attribute :admin_only_assignment, default: false, instance_accessor: false
  end
end
