# frozen_string_literal: true

module Wsjrdp2027::PersonAbility
  extend ActiveSupport::Concern

  included do
    on(Person) do
      # Replaced original permission:
      # permission(:any).may(:show, :update, :update_email, :primary_group, :totp_reset, :security)
      #   .herself
      permission(:any)
        .may(:update_email, :primary_group, :totp_reset, :security)
        .nobody
      permission(:any)
        .may(:show, :update)
        .herself

      # Replaced original permission:
      # permission(:any)
      #   .may(:show_details, :show_full, :history, :log, :index_invoices, :update_settings)
      #   .herself_unless_only_basic_permissions_roles
      permission(:any)
        .may(:history, :log, :index_invoices, :update_settings)
        .nobody
      permission(:any)
        .may(:show_details, :show_full)
        .herself_unless_only_basic_permissions_roles

    # permission(:group_full).may(:show_full, :history).in_same_group
    # permission(:group_full)
    #   .may(:update, :primary_group, :send_password_instructions, :log, :index_tags, :manage_tags,
    #     :security)
    #   .non_restricted_in_same_group
    # permission(:group_full).may(:update_email).if_permissions_in_all_capable_groups
    # permission(:group_full).may(:create).all # restrictions are on Roles
    permission(:group_full).may(:log, :history, :security, :update_email, :update_settings, :create).nobody
    permission(:group_full).may(:show_full).in_same_group
    # permission(:group_full)
    #   .may(:update, :primary_group)
    #   .non_restricted_in_same_group
    # permission(:group_full).may(:update_email).if_permissions_in_all_capable_groups
    # permission(:group_full).may(:create).all # restrictions are on Roles


      permission(:finance).may(:fin_admin).if_finance_on_root
    end

    def if_finance_on_root
      user_context.permission_layer_ids(:finance).include?(Group.root.id)
    end
  end
end
