# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Buchungsstapel (DATEV booking batch / Primanota) detail pages at
# /bookkeeping/booking_batches/:id -- the batch metadata plus the bookings it
# contains.
class Fin::BookingBatchesController < Fin::FinController
  include Fin::BookkeepingSummaries

  before_action :authorize_action

  helper_method :booking_batch_bookings_query

  def show
    @batch = DatevBookingBatch.find(params[:id])
  end

  private

  def authorize_action
    authorize!(:fin_admin, DatevBookingBatch)
  end

  # Every booking that belongs to the given Buchungsstapel (Konto perspective).
  def booking_batch_bookings_query(batch_id)
    DatevBookingsQuery.new(params, base: DatevBooking.where(datev_booking_batch_id: batch_id),
      default_per: Fin::BookkeepingSummaries::CONDENSED_DEFAULT_PER)
  end
end
