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

    # A person's payment_role follows the roles in their primary group while
    # it is fluid (Wsjrdp2027::Person#payment_role_fluid?). The person is
    # saved before their first role exists, and core sets primary_group_id
    # without callbacks (People::UpdateAfterRoleChange), so the person's own
    # save cannot see a role coming or going: every change of a role lets
    # the person rebuild it. Declared after core's hooks, which set the
    # primary group first.
    after_save :rebuild_person_payment_role
    after_destroy :rebuild_person_payment_role
  end

  private

  # On a fresh instance: the one this role points to may be in the middle of
  # its own save (the registration wizard saves the roles with the person).
  # Without validation: the derived value must land whatever else the
  # person's data lacks; only payment_role is written.
  def rebuild_person_payment_role
    owner = ::Person.find_by(id: person_id)
    return unless owner&.payment_role_fluid?

    owner.ensure_payment_role(rebuild: true)
    owner.save(validate: false) if owner.payment_role_changed?
  end
end
