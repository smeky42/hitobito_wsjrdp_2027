# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The model half of the Buchungsstapel detail (fin/booking_batches/_detail): one
# formatter per field of a DatevBookingBatch that shows more than its stored
# value, found by the name rule of Fin::AttrFormatHelper
# (fin_format_datev_booking_batch_<attr>).
#
# The labels of the fields live in
# de.activerecord.attributes.datev_booking_batch; a field without a formatter
# takes the finance type rules of Fin::AttrFormatHelper -- which is why the
# label, consultant_number, client_number, financial_year_start and the other
# plain strings and dates need none.
module Fin::BookingBatchesHelper
  # Zeitraum: combine period_from and period_to into a range display.
  # We use :period_from as the attribute and override its label to "Zeitraum"
  # in the detail partial. The formatter reads both dates from the record.
  def fin_format_datev_booking_batch_period_from(batch)
    [fin_date(batch.period_from), fin_date(batch.period_to)]
      .compact.join(" – ")
  end

  # Festschreibung: boolean → German yes/no.
  def fin_format_datev_booking_batch_is_finalized(batch)
    batch.is_finalized ? "ja" : "nein"
  end
end
