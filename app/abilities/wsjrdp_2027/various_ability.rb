# frozen_string_literal: true

module Wsjrdp2027::VariousAbility
  extend ActiveSupport::Concern

  included do
    on(LabelFormat) do
      class_side(:index).if_admin
    end

    on(AccountingEntry) do
      permission(:finance).may(:fin_admin, :create, :log, :manage, :show, :update, :destroy).if_finance_on_root
    end

    on(WsjrdpCamtTransaction) do
      permission(:finance).may(:fin_admin, :create, :log, :manage, :show, :update).if_finance_on_root
    end

    on(WsjrdpFinAccount) do
      permission(:finance).may(:fin_admin, :create, :log, :manage, :show, :update).if_finance_on_root
    end

    def if_finance_on_root
      user_context.permission_layer_ids(:finance).include?(Group.root.id)
    end
  end
end
