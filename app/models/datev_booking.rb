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
  # The two Moss sides of the posting chain, on the two levels DATEV posts at:
  # step 1 (Sachkonto -> creditor) is per SPLIT, step 2 (creditor -> 36100) is
  # per TRANSACTION. Both target the STI base classes, so they resolve for every
  # Moss kind (card, invoice, reimbursement, top-up).
  has_one :moss_booking_as_expense,
    class_name: "MossBooking",
    foreign_key: :expense_datev_booking_id,
    inverse_of: :expense_datev_booking
  has_one :moss_transaction_as_clearing,
    class_name: "MossTransaction",
    foreign_key: :clearing_datev_booking_id,
    inverse_of: :clearing_datev_booking
  # rubocop:enable Rails/HasManyOrHasOneDependent

  # account (Konto) / offsetting_account (Gegenkonto) as polymorphic associations
  belongs_to :account, polymorphic: true, optional: true,
    foreign_key: :account_number, primary_key: :number
  belongs_to :offsetting_account, polymorphic: true, optional: true,
    foreign_key: :offsetting_account_number, primary_key: :number

  # The sub cost center this booking is assigned to (Hitobito-owned, not from
  # DATEV). A sub cost center number is unique WITHIN its cost center only, so
  # the link needs BOTH numbers: `sub_cost_center_number` names the row and the
  # booking's own `cost_center_number` says under which cost center to read it.
  # The instance-dependent scope supplies that second half.
  #
  # There is deliberately no foreign key on the pair. `cost_center_number` is
  # DATEV's KOST field and the importer rewrites it on every import; a composite
  # FK would make that import fail for every booking carrying a sub cost center.
  # A pair that stopped resolving is therefore a legal state: the association
  # reads as nil, the raw number stays, and the booking still saves. Only the
  # validation below guards it, and only while the assignment itself changes.
  #
  # The price of the instance-dependent scope: the association preloads, but can
  # never be eager-loaded or joined ("The association scope ... is instance
  # dependent"). Use `preload`/`includes`; a join is written out in SQL:
  #   LEFT JOIN wsjrdp_sub_cost_centers scc
  #          ON scc.cost_center_number = datev_bookings.cost_center_number
  #         AND scc.number = datev_bookings.sub_cost_center_number
  #
  # `inverse_of: false` on both sides: the counterpart carries an
  # instance-dependent scope of its own, so Rails must not wire the two records
  # to each other behind the scopes' backs.
  belongs_to :sub_cost_center,
    ->(booking) { where(cost_center_number: booking.cost_center_number) },
    class_name: "WsjrdpSubCostCenter", foreign_key: :sub_cost_center_number,
    primary_key: :number, optional: true, inverse_of: false

  # Every booking with its sub cost center's names as REAL columns:
  #
  #   sub_cost_center_name        the sub cost center's `name`
  #   sub_cost_center_short_name  its `display_short_name`
  #
  # Both are NULL where the stored pair names no row. Computed in ONE derived
  # table aliased back to `datev_bookings`, over the same LEFT JOIN on both
  # numbers the associations describe, so the rows stay DatevBooking objects and
  # carry every original column PLUS these two.
  #
  # This is the one-query alternative to `preload(:sub_cost_center)` for a list
  # that only shows the sub cost center's name: the association's scope is
  # instance dependent and can therefore never be joined or eager-loaded, only
  # preloaded -- and that costs one query per distinct cost center in the list.
  # Unlike the association, these columns can also be sorted and filtered on.
  scope :with_sub_cost_center, -> {
    from(Arel.sql(<<~SQL.squish))
      (SELECT b.*,
              scc.name AS sub_cost_center_name,
              scc.display_short_name AS sub_cost_center_short_name
         FROM datev_bookings b
         LEFT JOIN wsjrdp_sub_cost_centers scc
                ON scc.cost_center_number = b.cost_center_number
               AND scc.number = b.sub_cost_center_number)
      AS datev_bookings
    SQL
  }

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
