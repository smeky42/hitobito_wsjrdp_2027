# frozen_string_literal: true

module Wsjrdp2027::VariousAbility
  extend ActiveSupport::Concern

  included do
    include Wsjrdp2027::FinanceAccess

    on(LabelFormat) do
      class_side(:index).if_admin
    end

    # The three finance tiers, CUMULATIVE: each tier repeats the
    # actions of the one below it. The ability store is keyed by
    # (permission, subject, action), so a role which holds :finance
    # but not :finance_read would not see :show otherwise.
    #
    # :log stays out of the read tier on purpose. In this wagon :log
    # is the generic "privileged/internal view" gate, so a read-only
    # person must not get it.
    #
    # NOTE on the admin tier: :manage is CanCan's WILDCARD -- it
    # covers every action on the subject, :destroy included. The admin
    # tier therefore has full access to the finance models; the other
    # actions are listed only to spell the intent out.
    read_actions = %i[show]
    write_actions = read_actions + %i[log create update]
    admin_actions = write_actions + %i[fin_admin manage]

    finance_models = [
      AccountingEntry,
      WsjrdpCamtTransaction,
      WsjrdpPaymentPlan,
      WsjrdpFinAccount,
      MossTransaction,
      MossExpense,
      MossBooking,
      # DATEV bookkeeping: every Buchhaltung/Abstimmung page authorizes against
      # its own model (no proxy subject); same gate as the other finance models.
      DatevBooking,
      DatevBookingBatch,
      WsjrdpLedgerAccount,
      WsjrdpCostCenter,
      WsjrdpPersonalAccount
    ]

    finance_models.each do |model|
      on(model) do
        permission(:finance_read).may(*read_actions).if_finance_read
        permission(:finance).may(*write_actions).if_finance_write
        permission(:finance_admin).may(*admin_actions).if_finance_admin
      end
    end
  end
end
