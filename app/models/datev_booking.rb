# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A single booking extracted from a DATEV "Primanota" export (Buchungsstapel).
#
# At most one DatevBooking may be linked to a given AccountingEntry; the link
# is optional (a booking need not be linked to an accounting entry). The
# uniqueness is additionally enforced by a unique index on accounting_entry_id.
#
# Identity: every booking carries the DATEV "Buchungs GUID" (buchungs_guid,
# unique, NOT NULL). The DTVF importer upserts on it, so there is no soft-delete
# flag -- a booking that vanishes from a re-export is simply gone. Each booking
# optionally belongs to the datev_booking_batch it was imported from.
class DatevBooking < ActiveRecord::Base
  # Amount family (2 currencies x {absolute, signed Konto, signed Gegenkonto}):
  #   base (EUR):        absolute_base_amount  -> amount / offsetting_amount
  #   transaction (ccy): absolute_transaction_amount -> transaction_amount / offsetting_transaction_amount
  # The `absolute_*` columns are the raw sign-less DATEV inputs; the four signed
  # columns are STORED GENERATED (incoming +, outgoing -), derived from the matching
  # absolute amount, the `debit_credit` (S/H) flag and the denormalised account type.
  # `amount` (base, Konto side) is the canonical ledger value: SUM(amount) is
  # directly meaningful and ALWAYS in EUR (no currency mixing). The transaction
  # columns equal the base ones for EUR bookings and differ only when
  # `transaction_currency` != `base_currency`. See the create migration for the
  # exact generation expressions.

  belongs_to :accounting_entry, optional: true
  belongs_to :person, optional: true
  belongs_to :camt_transaction, optional: true, class_name: "WsjrdpCamtTransaction"
  # The Buchungsstapel / Primanota this booking was imported from (optional).
  belongs_to :datev_booking_batch, optional: true

  # Strict 1:1 back-links from a Moss card-transaction booking: a Moss booking
  # posts two DATEV bookings (expense = Sachkonto -> Sammelkreditor; clearing =
  # Sammelkreditor -> Moss-Konto). At most one of each references this booking.
  has_one :expense_moss_card_transaction_booking,
    class_name: "MossCardTransactionBooking",
    foreign_key: :expense_datev_booking_id,
    inverse_of: :expense_datev_booking,
    dependent: :nullify
  has_one :clearing_moss_card_transaction_booking,
    class_name: "MossCardTransactionBooking",
    foreign_key: :clearing_datev_booking_id,
    inverse_of: :clearing_datev_booking,
    dependent: :nullify

  # Konto / Gegenkonto as guides-style polymorphic associations
  # (doc/bookkeeping_schema_review.md §4): the *_ref_type columns are STORED
  # GENERATED from the DATEV Kontenart (CREDITOR -> WsjrdpPersonalAccount, everything
  # else -> WsjrdpLedgerAccount), and both targets are matched on their unique
  # `number` column instead of the id. Note the deliberate near-miss:
  # `account_type` (the Kontenart) is NOT the association's type column --
  # `foreign_type: :account_ref_type` overrides the `#{name}_type` convention.
  #
  # `optional: true` although the columns are NOT NULL: the reference tables
  # are imported separately (a fresh prod dump has bookings before accounts /
  # suppliers exist), and a booking update must not fail on a temporarily
  # unresolvable number. `includes(:account, :offsetting_account)` preloads
  # without N+1; `joins`/`eager_load` raise for polymorphic associations by
  # design -- SQL needing the join uses the explicit two-column form.
  belongs_to :account, polymorphic: true, optional: true,
    foreign_key: :account_number, foreign_type: :account_ref_type,
    primary_key: :number
  belongs_to :offsetting_account, polymorphic: true, optional: true,
    foreign_key: :offsetting_account_number, foreign_type: :offsetting_account_ref_type,
    primary_key: :number

  validates :accounting_entry_id, uniqueness: true, allow_nil: true

  # --- General ledger "legs" (see doc/bookkeeping.md) -----------------------
  # Each booking touches two accounts (Konto + Gegenkonto). `amount` is signed
  # from the Konto's perspective only, so summing over the Gegenkonto side (or an
  # account that appears on both sides) with SUM(amount) is wrong. `legs` expands
  # every booking into two rows -- one per account -- each valued from that
  # account's OWN perspective (`amount` for the Konto leg, `offsetting_amount`
  # for the Gegenkonto leg). Grouping/filtering by `leg_account` then yields the
  # correct, two-sided account and supplier balances.
  #
  # Realised as a UNION-ALL subquery via #from, aliased `AS datev_bookings` so the
  # rows stay DatevBooking objects and carry every original column PLUS the
  # leg_side / leg_account / leg_account_type / leg_amount columns -- no database
  # view, so it round-trips through schema.rb. `id` repeats per booking (K and G
  # leg), so use `legs` for aggregation/listing, not for find/update.
  LEG_BASE_COLUMNS = "datev_bookings.*"

  def self.legs
    konto = select("#{LEG_BASE_COLUMNS}, 'K' AS leg_side, account_number AS leg_account, " \
      "account_type AS leg_account_type, amount AS leg_amount")
    gegen = where.not(offsetting_account_number: nil)
      .select("#{LEG_BASE_COLUMNS}, 'G' AS leg_side, offsetting_account_number AS leg_account, " \
        "offsetting_account_type AS leg_account_type, offsetting_amount AS leg_amount")
    unscoped.from(Arel.sql("(#{konto.to_sql} UNION ALL #{gegen.to_sql}) AS datev_bookings"))
  end
end
