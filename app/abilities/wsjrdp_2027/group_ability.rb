# frozen_string_literal: true

module Wsjrdp2027::GroupAbility
  extend ActiveSupport::Concern

  included do
    include Wsjrdp2027::FinanceAccess

    on(Group) do
      # Show events and mailing lists to users with pemissions to read the group, instead of everyone
      permission(:any)
        .may(:index_events, :"index_event/courses", :index_mailing_lists)
        .nobody
      permission(:any)
        .may(:index_events)
        .if_member_of_group
      permission(:group_read)
        .may(:index_events, :index_mailing_lists)
        .in_same_group
      permission(:group_and_below_read)
        .may(:index_events, :"index_event/courses", :index_mailing_lists)
        .in_same_group_or_below
      permission(:layer_read)
        .may(:index_events, :"index_event/courses", :index_mailing_lists)
        .in_same_layer
      permission(:layer_and_below_read)
        .may(:index_events, :"index_event/courses", :index_mailing_lists)
        .in_same_layer_or_below

      permission(:group_full)
        .may(:update, :index_full_people, :log, :deleted_subgroups, :reactivate, :"index_event/courses",
          :export_events, :"export_event/courses")
        .none
      permission(:group_full).may(:show_statistics).in_same_group

      # The group's finance tab and its pages. :show_finance opens
      # them, :update_finance is the gate for anything that edits
      # there beyond the regular finance tiers.
      #
      # A unit leader (:group_full) works on their own unit. A
      # :layer_and_below_full role reaches the groups of its layer and
      # below as long as that layer is not the contingent's root layer
      # -- a unit manager on their unit, an IST leader on the IST layer
      # including the IST groups nested in it. The root layer does not
      # count, so a CMT leader reaches a group's finance pages only
      # through the group ids listed in their finance_group_ids, which
      # grant an action each ("show", "update") and only to holders of
      # :layer_and_below_full.
      #
      # The finance tiers are not layer-bound: the audit tier reads
      # every group's finance pages, the write and the manage tier
      # also edit them. :finance_read alone grants nothing on a group,
      # and the session's finance cap applies, because it takes the
      # capped tiers out of the permission set the constraints read.
      permission(:group_full).may(:show_finance, :update_finance).in_same_group
      permission(:layer_and_below_full).may(:show_finance).if_finance_group_show
      permission(:layer_and_below_full).may(:update_finance).if_finance_group_update
      permission(:finance_audit).may(:show_finance).if_finance_audit
      permission(:finance).may(:show_finance, :update_finance).if_finance_write
      permission(:finance_manage).may(:show_finance, :update_finance).if_finance_manage

      # The admin area of the finance section: who hands out the
      # per-group finance access (finance_group_ids) and assigns the
      # cost centers of a group. CLASS SIDE, because the pages
      # configure the groups as a whole, not one group.
      #
      # The name is :configure_finance, not :admin_finance: on the
      # finance models :admin_finance belongs to the manage tier
      # alone, while here the CMT admins hold it as well. The manage
      # tier still has to be picked for the session, so the session's
      # finance cap applies here too.
      class_side(:configure_finance).if_admin_or_finance_manage
    end

    # The finance admin area's gate. :admin is read the way the core's
    # own if_admin reads it (AbilityDsl::Base), and :finance_manage
    # through the shared finance constraint, so the cap takes the
    # manage tier away here as it does everywhere else.
    def if_admin_or_finance_manage
      if_admin || if_finance_manage
    end

    def if_member_of_group
      user.group_ids.include?(group.id)
    end

    # :layer_and_below_full held in a Unit or IST layer of the group's
    # hierarchy; the contingent's root layer does not count, so a CMT leader
    # reaches a group's finance pages only through finance_group_ids.
    def in_same_layer_or_below_outside_the_root_layer
      return false unless group

      held_in = user_context.permission_layer_ids(permission)
      group.layer_hierarchy.any? { |layer| !layer.is_a?(Group::Root) && held_in.include?(layer.id) }
    end

    def if_finance_group_show
      in_same_layer_or_below_outside_the_root_layer || finance_group_action?("show")
    end

    def if_finance_group_update
      in_same_layer_or_below_outside_the_root_layer || finance_group_action?("update")
    end

    def finance_group_action?(token)
      group.present? && user.finance_group_actions(group).include?(token)
    end
  end
end
