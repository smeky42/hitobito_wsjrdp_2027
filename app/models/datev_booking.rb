# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A single booking extracted from a DATEV Primanota export
# (Buchungsstapel). Identity: every booking carries the unique DATEV
# Buchungs GUID (buchungs_guid). Each booking optionally belongs to
# the datev_booking_batch it was imported from.
class DatevBooking < ActiveRecord::Base
  # The Buchungsstapel / Primanota this booking was imported from (optional).
  belongs_to :batch, class_name: "DatevBookingBatch",
    foreign_key: :datev_booking_batch_id,
    inverse_of: :bookings,
    optional: true

  delegate :consultant_number, :client_number, :primanota_number, :financial_year, :financial_year_start, :financial_year_end,
    to: :batch, allow_nil: true

  has_one :accounting_entry, inverse_of: :datev_booking, dependent: :nullify

  # Bookings not reconciled with any accounting entry (the link lives on the
  # entry now). A NOT IN subquery, deliberately NOT where.missing(:accounting_entry):
  # the latter LEFT JOINs accounting_entries, and the matcher's raw-SQL filters
  # reference booking_date, which BOTH tables carry (ambiguous under the join).
  scope :without_accounting_entry, -> {
    where.not(id: AccountingEntry.where.not(datev_booking_id: nil).select(:datev_booking_id))
  }
  has_one :camt_transaction, class_name: "WsjrdpCamtTransaction",
    inverse_of: :datev_booking, dependent: :nullify

  # Strict 1:1 back-links from the Moss card side. The Moss->DATEV chain posts
  # the expense booking (Sachkonto -> Sammelkreditor) per SPLIT and the clearing
  # booking (Sammelkreditor -> Moss-Konto) once per TRANSACTION, so the two
  # back-links point at different models.
  #
  # Naming: THIS booking is the expense resp. clearing booking; the Moss row on
  # the other end is just a Moss row. The role therefore trails the name and
  # qualifies the relationship instead of the target -- the target model leads,
  # as it does for `accounting_entry` / `camt_transaction` above.
  # No :dependent option: the foreign keys already null these columns on delete
  # (on_delete: :nullify), so Rails must not load the counterpart as well.
  # rubocop:disable Rails/HasManyOrHasOneDependent -- see the note above: the
  # foreign keys null these columns on delete, Rails must not do it a second time.
  has_one :moss_card_transaction_booking_as_expense,
    class_name: "MossCardTransactionBooking",
    foreign_key: :expense_datev_booking_id,
    inverse_of: :expense_datev_booking
  has_one :moss_card_transaction_as_clearing,
    class_name: "MossCardTransaction",
    foreign_key: :clearing_datev_booking_id,
    inverse_of: :clearing_datev_booking
  # rubocop:enable Rails/HasManyOrHasOneDependent

  # account (Konto) / offsetting_account (Gegenkonto) as polymorphic associations
  belongs_to :account, polymorphic: true, optional: true,
    foreign_key: :account_number, primary_key: :number
  belongs_to :offsetting_account, polymorphic: true, optional: true,
    foreign_key: :offsetting_account_number, primary_key: :number

  # General ledger legs
  #
  # Each booking touches account (Konto) and offsetting_account
  # (Gegenkonto). `signed_base_amount` is signed from the Konto's
  # perspective only, so summing over the offsetting_account
  # (Gegenkonto) side (or an account that appears on both sides) with
  # SUM(signed_base_amount) is wrong. `legs` expands every booking
  # into two rows -- one per account -- each valued from that
  # account's OWN perspective (`signed_base_amount` for the Konto leg,
  # `signed_offsetting_base_amount` for the Gegenkonto
  # leg). Grouping/filtering by `leg_account` then yields the correct,
  # two-sided account and supplier balances.
  #
  # Realised as a UNION-ALL subquery via #from, aliased `AS
  # datev_bookings` so the rows stay DatevBooking objects and carry
  # every original column PLUS the leg_side / leg_account /
  # leg_account_kind / signed_leg_amount columns -- no database view,
  # so it round-trips through schema.rb. `id` repeats per booking (A
  # and O leg), so use `legs` for aggregation/listing, not for
  # find/update.
  def self.legs
    konto = select("datev_bookings.*, 'A' AS leg_side, account_number AS leg_account_number, " \
      "account_kind AS leg_account_kind, signed_base_amount AS signed_leg_amount")
    gegen = where.not(offsetting_account_number: nil)
      .select("datev_bookings.*, 'O' AS leg_side, offsetting_account_number AS leg_account_number, " \
        "offsetting_account_kind AS leg_account_kind, signed_offsetting_base_amount AS signed_leg_amount")
    unscoped.from(Arel.sql("(#{konto.to_sql} UNION ALL #{gegen.to_sql}) AS datev_bookings"))
  end
end
