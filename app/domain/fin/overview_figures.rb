# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Key figures of the Finanzen entry page (/fin): the two or three numbers and
# the "Stand" date each area's card shows -- Konten & Wallets, Beiträge, Moss,
# Buchhaltung and Abstimmung (Controlling has no figures). Read-only; every
# figure is ONE aggregate query, memoized per instance (one instance per
# request).
#
# Every figure is a COUNT or a DATE, never a personal datum: the card says how
# much an area holds and how fresh it is, and links on from there for the rest.
# No formatting, no I18n and no HTML live here -- numbers and Dates go out, the
# page decides how they look.
class Fin::OverviewFigures
  # --- Konten & Wallets ---

  def accounts_count
    @accounts_count ||= WsjrdpFinAccount.count
  end

  def camt_transactions_count
    @camt_transactions_count ||= WsjrdpCamtTransaction.count
  end

  # Newest Valuta of any bank transaction: how far the imported statements
  # reach. An empty table has no date, and that nil is memoized as well.
  def camt_last_value_date
    return @camt_last_value_date if defined?(@camt_last_value_date)

    @camt_last_value_date = WsjrdpCamtTransaction.maximum(:value_date)
  end

  # --- Beiträge ---

  def accounting_entries_count
    @accounting_entries_count ||= AccountingEntry.count
  end

  # Contribution bookings not yet reconciled with a DATEV booking. The
  # Abstimmung card shows the same number -- it is the open work there.
  def accounting_entries_unlinked_count
    @accounting_entries_unlinked_count ||= AccountingEntry.where(datev_booking_id: nil).count
  end

  # --- Moss ---

  # The Moss figures come from the section's OWN overview, so the entry page
  # and /fin/moss can never disagree; it memoizes its aggregates itself.
  def moss
    @moss ||= Fin::MossOverview.new
  end

  def moss_transactions_count = moss.total_count

  def moss_bookings_count = moss.bookings_count

  def moss_last_booking_date = moss.last_booking_date

  # Transactions without their clearing booking (Sammelkreditor -> Moss-Konto).
  def moss_clearing_unlinked_count = moss.clearing_unlinked_count

  # Moss bookings without their expense booking (Sachkonto -> Sammelkreditor);
  # shown on the Moss card and again on the Abstimmung card.
  def moss_expense_unlinked_count = moss.expense_unlinked_count

  # --- Buchhaltung ---

  def datev_bookings_count
    @datev_bookings_count ||= DatevBooking.count
  end

  def datev_batches_count
    @datev_batches_count ||= DatevBookingBatch.count
  end

  # Newest Belegdatum of any DATEV booking: the "Stand" of the bookkeeping.
  # An empty table has no date, and that nil is memoized as well.
  def datev_last_booking_date
    return @datev_last_booking_date if defined?(@datev_last_booking_date)

    @datev_last_booking_date = DatevBooking.maximum(:booking_date)
  end

  def cost_centers_count
    @cost_centers_count ||= WsjrdpCostCenter.count
  end

  def personal_accounts_count
    @personal_accounts_count ||= WsjrdpPersonalAccount.count
  end
end
