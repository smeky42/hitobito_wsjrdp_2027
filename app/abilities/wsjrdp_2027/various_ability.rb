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

    on(MossBalanceMovement) do
      permission(:finance).may(:fin_admin, :create, :log, :manage, :show, :update).if_finance_on_root
    end

    # DATEV bookkeeping: every Buchhaltung/Abstimmung page authorizes against
    # its own model (no proxy subject); same gate as the other finance models.
    on(DatevBooking) do
      permission(:finance).may(:fin_admin, :create, :log, :manage, :show, :update).if_finance_on_root
    end

    on(DatevBookingBatch) do
      permission(:finance).may(:fin_admin, :create, :log, :manage, :show, :update).if_finance_on_root
    end

    on(WsjrdpLedgerAccount) do
      permission(:finance).may(:fin_admin, :create, :log, :manage, :show, :update).if_finance_on_root
    end

    on(WsjrdpCostCenter) do
      permission(:finance).may(:fin_admin, :create, :log, :manage, :show, :update).if_finance_on_root
    end

    on(WsjrdpPersonalAccount) do
      permission(:finance).may(:fin_admin, :create, :log, :manage, :show, :update).if_finance_on_root
    end

    on(MossCardTransaction) do
      permission(:finance).may(:fin_admin, :create, :log, :manage, :show, :update).if_finance_on_root
    end
  end
end
