# frozen_string_literal: true

module Wsjrdp2027::RoleAbility
  extend ActiveSupport::Concern

  included do
    on(Role) do
      # Replaced original permission:
      # permission(:group_full).may(:create, :update, :destroy, :terminate)
      #   .in_same_group_if_active
      permission(:group_full).may(:create, :update, :destroy, :terminate).none

      # Admin-only roles (Role.admin_only_assignment, e.g. Group::Root::Admin
      # and Group::Root::Finance): general constraints veto EVERY permission
      # rule above, so no layer/group permission can bypass them. Assigning or
      # modifying such a role is reserved to CMT admins; taking one away from
      # ANOTHER person as well (one's own role is not restricted by the wagon
      # rule).
      #
      # CAUTION: the ability DSL stores ONE general constraint per action
      # (AbilityDsl::Store#add is last-wins), so registering a general here
      # REPLACES the core RoleAbility's general for that action. The core
      # conditions (group_not_deleted_or_archived on :create,
      # not_permission_giving on :destroy) are therefore re-included below.
      general(:update).admin_only_role_assignment_by_admins
      general(:create).admin_only_role_creation_guard
      general(:terminate).admin_only_role_removal_by_admins_or_self
      general(:destroy).admin_only_role_destruction_guard
    end

    # :update
    # upstream Hitobito: n/a
    def admin_only_role_assignment_by_admins
      !subject.class.admin_only_assignment || user_context.admin
    end

    # :create
    # upstream Hitobito: general(:create).group_not_deleted_or_archived
    def admin_only_role_creation_guard
      admin_only_role_assignment_by_admins && group_not_deleted_or_archived
    end

    # :terminate
    # upstream Hitobito: n/a
    def admin_only_role_removal_by_admins_or_self
      admin_only_role_assignment_by_admins || her_own
    end

    # :destroy
    # upstream Hitobito: general(:destroy).not_permission_giving
    def admin_only_role_destruction_guard
      (admin_only_role_assignment_by_admins || her_own) && not_permission_giving
    end
  end
end
