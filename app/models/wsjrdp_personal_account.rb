# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A DATEV personal account (Personenkonto): CREDITOR
# (Kreditor/Lieferant, 7xxxxx-9xxxxx) or DEBITOR (Debitor/Kunde,
# 1xxxxx-6xxxxx); see doc/fin/personal_accounts.md for which column
# comes from which system.
class WsjrdpPersonalAccount < ActiveRecord::Base
  STATUS_ACTIVE = "active"
  STATUS_DEACTIVATED = "deactivated"
  STATUS_DELETED = "deleted"
  CREDITOR_NUMBER = /\A[7-9]\d{#{WsjrdpLedgerAccount::NUMBER_LENGTH}}\z/

  validates :number, presence: true, uniqueness: true

  belongs_to :represented_person, class_name: "Person", optional: true,
    inverse_of: :personal_accounts

  # A supplier's default Moss team, by Moss UUID; may dangle.
  belongs_to :default_moss_team, class_name: "MossTeam", optional: true,
    primary_key: :moss_team_uuid, foreign_key: :default_moss_team_uuid, inverse_of: :default_suppliers
  # A supplier's defaults in Moss, by Moss UUID; each may dangle.
  belongs_to :default_moss_expense_account, class_name: "WsjrdpLedgerAccount", optional: true,
    primary_key: :moss_uuid, foreign_key: :default_moss_expense_account_uuid, inverse_of: false
  belongs_to :default_moss_cost_center, class_name: "WsjrdpCostCenter", optional: true,
    primary_key: :moss_uuid, foreign_key: :default_moss_cost_center_uuid, inverse_of: false
  belongs_to :default_moss_cost_carrier, class_name: "WsjrdpSphere", optional: true,
    primary_key: :moss_uuid, foreign_key: :default_moss_cost_carrier_uuid, inverse_of: false
  belongs_to :default_moss_payment_term, class_name: "MossPaymentTerm", optional: true,
    primary_key: :moss_payment_term_uuid, foreign_key: :default_moss_payment_term_uuid, inverse_of: :suppliers
  belongs_to :default_moss_vat_rate, class_name: "MossTaxRate", optional: true,
    primary_key: :moss_tax_rate_uuid, foreign_key: :default_moss_vat_rate_uuid, inverse_of: :suppliers

  # Bookings whose Konto (account) is this personal account
  # rubocop:disable Rails/HasManyOrHasOneDependent -- deliberately no
  # :dependent option: bookings are independent facts; deleting an account
  # must never touch them (and there is no FK to nullify).
  has_many :bookings, class_name: "DatevBooking", as: :account,
    primary_key: :number, foreign_key: :account_number, inverse_of: :account
  # rubocop:enable Rails/HasManyOrHasOneDependent

  # Bank accounts / wallets that map to this personal account (by
  # number).  dependent: :nullify -- removing a personal account clears
  # the mapping on the fin accounts (there is no FK; the link is
  # polymorphic, by number).
  has_many :fin_accounts, class_name: "WsjrdpFinAccount",
    as: :bookkeeping_account, primary_key: :number,
    foreign_key: :bookkeeping_account_number,
    inverse_of: :bookkeeping_account, dependent: :nullify

  # moss_status is NULL for accounts without a Moss connection
  scope :active, -> { where(moss_status: STATUS_ACTIVE) }
  scope :deactivated, -> { where(moss_status: [STATUS_DEACTIVATED, STATUS_DELETED, nil]) }
  scope :deleted, -> { where(moss_status: STATUS_DELETED) }

  # Every personal account with its two-sided booking totals as REAL columns:
  #
  #   booking_balance  SUM of DatevBooking.legs' signed_leg_amount for this
  #                    account number, 0 when it has no booking
  #   booking_count    how many bookings touch the account, 0 when none
  #
  # Both are computed in ONE derived table aliased back to
  # `wsjrdp_personal_accounts`, so they are ordinary columns of the relation:
  # the Kreditoren page's filter compiles conditions against them
  # (Fin::PersonalAccountsFilterSchema), the table sorts by them, and
  # `.sum(:booking_balance)` / `.sum(:booking_count)` give the footer totals of
  # the FILTERED set. A LEFT JOIN, so an account without bookings still appears.
  #
  # The legs subquery is DatevBooking.legs itself (its UNION of the Konto and
  # Gegenkonto side, each valued from that account's own perspective), never a
  # second copy of that definition -- see DatevBooking.legs for why summing
  # signed_base_amount alone would be wrong.
  scope :with_booking_summary, -> {
    totals = DatevBooking.legs
      .select("leg_account_number, SUM(signed_leg_amount) AS booking_balance, " \
              "COUNT(*) AS booking_count")
      .group(:leg_account_number)
    from(Arel.sql(<<~SQL.squish))
      (SELECT pa.*,
              COALESCE(l.booking_balance, 0) AS booking_balance,
              COALESCE(l.booking_count, 0) AS booking_count
         FROM wsjrdp_personal_accounts pa
         LEFT JOIN (#{totals.to_sql}) l ON l.leg_account_number = pa.number)
      AS wsjrdp_personal_accounts
    SQL
  }

  def active?
    moss_status == STATUS_ACTIVE
  end

  def to_s
    "#{number} #{display_short_name}"
  end
end
