# frozen_string_literal: true

module Wsjrdp2027::VariousAbility
  extend ActiveSupport::Concern

  included do
    include Wsjrdp2027::FinanceAccess

    on(LabelFormat) do
      class_side(:index).if_admin
    end

    # The finance tiers. Most actions are CUMULATIVE: each tier
    # repeats the actions of the one below it. The ability store is
    # keyed by (permission, subject, action), so a role which holds
    # :finance but not :finance_read would not see :show otherwise.
    #
    # :log stays out of the READ tier on purpose. In this wagon :log
    # is the generic "privileged/internal view" gate, and on the
    # finance models it is what the person-level views ask for
    # (fin/person_fees, the fee blocks of a Beitragsbuchung). That is
    # exactly the line between the read tier and the AUDIT tier, which
    # is read-only just the same but does get :log.
    #
    # NOTE on the manage tier: :manage is CanCanCan's WILDCARD -- it
    # covers every action on the subject, :destroy included. The admin
    # tier therefore has full access to the finance models; the other
    # actions are listed only to spell the intent out.
    finance_models = [
      WsjrdpCamtTransaction,
      WsjrdpPaymentPlan,
      WsjrdpFinAccount,
      MossTransaction,
      MossExpense,
      MossBooking,
      DatevBooking,
      DatevBookingBatch,
      WsjrdpLedgerAccount,
      WsjrdpCostCenter,
      WsjrdpPersonalAccount
    ]

    # Every finance model but ones below shares the whole ladder.
    finance_models.each do |model|
      on(model) do
        permission(:finance_read).may(:show).if_finance_read
        permission(:finance_audit).may(:show, :log).if_finance_audit
        permission(:finance).may(:show, :log, :create, :update).if_finance_write
        permission(:finance_manage).may(:show, :log, :create, :update, :manage, :admin_finance).if_finance_manage
      end
    end

    # AccountingEntry: No read access if only :finance_read is held
    on(AccountingEntry) do
      permission(:finance_audit).may(:show, :log).if_finance_audit
      permission(:finance).may(:show, :log, :create, :update).if_finance_write
      permission(:finance_manage).may(:show, :log, :create, :update, :manage, :admin_finance).if_finance_manage
    end

    # WsjrdpDirectDebitPreNotification: the announcement of a single
    # participant's collection. It carries the same person-level
    # payment details as a AccountingEntry and shares its ladder.
    on(WsjrdpDirectDebitPreNotification) do
      permission(:finance_audit).may(:show, :log).if_finance_audit
      permission(:finance).may(:show, :log, :create, :update).if_finance_write
      permission(:finance_manage).may(:show, :log, :create, :update, :manage, :admin_finance).if_finance_manage
    end
  end
end
