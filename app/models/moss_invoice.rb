# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# An incoming INVOICE paid through Moss (STI subclass of MossTransaction).
#
# The invoice IS the expense, so it has exactly ONE MossExpense; an invoice with
# several lines has one BOOKING per line (not one expense per line).
#
# Invoices are the kind that may be paid on a non-Moss route: those are booked in
# DATEV straight against the individual creditor and then have no 36100 clearing
# leg -- see `manually_paid`. Foreign-currency invoices are matched on the
# transaction amount (e.g. PLN), never on EUR, because Moss and DATEV each apply
# their own rate.
class MossInvoice < MossTransaction
  def moss_record_url
    return super if moss_invoice_uuid.blank?

    "#{MOSS_APP_URL}/invoices/all/#{moss_invoice_uuid}"
  end

  def moss_export_url
    return super if moss_invoice_uuid.blank?

    "#{MOSS_APP_URL}/export/invoices/#{moss_invoice_uuid}"
  end

  def expense = expenses.first

  # DATEV books an invoice under its INVOICE date, so `invoice_date` is the
  # anchor matched against datev_bookings.booking_date (the Belegdatum), with
  # `delivery_date` as the second-best anchor and a date window for the rest.
  # `invoice_date` is a transaction column, filled from the invoice export only.
  def datev_date_anchor = invoice_date || delivery_date || payment_date

  def display_name = invoice_number
end
