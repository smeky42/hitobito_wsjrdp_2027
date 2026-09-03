# frozen_string_literal: true

module Wsjrdp2027::VariousAbility
  extend ActiveSupport::Concern

  included do
    include Wsjrdp2027::FinanceOnRoot

    on(LabelFormat) do
      class_side(:index).if_admin
    end

    on(AccountingEntry) do
      permission(:finance).may(:fin_admin, :create, :log, :manage, :show, :update, :destroy).if_finance_on_root
    end

    on(WsjrdpCamtTransaction) do
      permission(:finance).may(:fin_admin, :create, :log, :manage, :show, :update).if_finance_on_root
    end

    on(WsjrdpPaymentPlan) do
      permission(:finance).may(:fin_admin, :create, :log, :manage, :show, :update).if_finance_on_root
    end

    on(WsjrdpFinAccount) do
      permission(:finance).may(:fin_admin, :create, :log, :manage, :show, :update).if_finance_on_root
    end

    on(MossTransaction) do
      permission(:finance).may(:fin_admin, :create, :log, :manage, :show, :update).if_finance_on_root
    end

    on(MossExpense) do
      permission(:finance).may(:fin_admin, :create, :log, :manage, :show, :update).if_finance_on_root
    end

    on(MossBooking) do
      permission(:finance).may(:fin_admin, :create, :log, :manage, :show, :update).if_finance_on_root
    end
  end
end
