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

      permission(:finance).may(:fin_admin).if_finance_on_root
    end

    def if_finance_on_root
      user_context.permission_layer_ids(:finance).include?(Group.root.id)
    end
  end
end
