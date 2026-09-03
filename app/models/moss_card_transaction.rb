# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A Moss CARD payment (STI subclass of MossTransaction).
#
# The card payment IS the expense, so it always has exactly ONE MossExpense; its
# splits are that expense's bookings. Since the unification the card side also
# carries the Moss wallet in `fin_account`, so card payments appear in the wallet
# statement next to the balance movements.
#
# Its DATEV date anchor is `booking_date`, matched against
# datev_bookings.booking_date (the DATEV Belegdatum).
class MossCardTransaction < MossTransaction
  # The card section of the Moss app; the export view uses its own path.
  def moss_record_url = "#{MOSS_APP_URL}/transactions/all/#{moss_transaction_uuid}"

  def moss_export_url = "#{MOSS_APP_URL}/export/card-transactions/#{moss_transaction_uuid}"

  # File name of the combined receipt PDF in the attachments export.
  def transaction_id_pdf_filename = "#{moss_transaction_uuid}.pdf"

  # The card payment IS its expense (as in Moss's CardTransactionMetadata), so
  # the merchant and the receipt file live on the transaction.
  def merchant = [merchant_name, merchant_city, merchant_country].compact_blank.join(", ")

  # The one expense of this card payment (the payment IS the expense).
  def expense = expenses.first

  # The date DATEV books this transaction under (see the class comment).
  def datev_date_anchor = booking_date

  def display_name = merchant_name
end
