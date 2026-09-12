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
    # NOTE on the admin tier: :manage is CanCanCan's WILDCARD -- it
    # covers every action on the subject, :destroy included. The admin
    # tier therefore has full access to the finance models; the other
    # actions are listed only to spell the intent out.
    read_actions = %i[show]
    audit_actions = read_actions + %i[log]
    write_actions = audit_actions + %i[create update]
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

    # AccountingEntry is the ONE finance model the read tier does not
    # get. This way we can hide some personal data.  So /fin/ae/:id is
    # a person-level page in everything but its route. It therefore
    # stays closed to :finance_read, the same line fin/person_fees
    # draws with :log. The read tier still sees WHERE an entry is
    # referenced (a booking's or a statement's link), by its bare id.
    # The AUDIT tier does get it -- seeing the Beitragsbuchungen is
    # what it exists for.
    read_tier_models = finance_models - [AccountingEntry]

    finance_models.each do |model|
      reads_this_model = read_tier_models.include?(model)
      on(model) do
        permission(:finance_read).may(*read_actions).if_finance_read if reads_this_model
        permission(:finance_audit).may(*audit_actions).if_finance_audit
        permission(:finance).may(*write_actions).if_finance_write
        permission(:finance_manage).may(*admin_actions).if_finance_admin
      end
    end
  end
end
