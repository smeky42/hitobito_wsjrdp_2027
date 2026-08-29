# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Buchungsstapel (DATEV booking batch / Primanota) at /bookkeeping/booking_batches:
# the index lists all batches with their booking counts, and the detail page at
# /bookkeeping/booking_batches/:id shows the batch metadata plus the bookings it
# contains.
class Fin::BookingBatchesController < Fin::FinController
  include Fin::BookkeepingSummaries

  before_action :authorize_action

  SUMMARY_POLICY = wsjrdp_expandable_table_policy prefix: "",
    columns: Fin::BookingBatchesColumns::BATCHES.codec,
    sort: {default: [["period_to", "desc"], ["primanota_number", "desc"]]},
    cols: {default: Fin::BookingBatchesColumns::BATCHES.default_keys},
    per_page: {default: 50},
    filter: {policy: :remember, schema: Fin::BookingBatchesFilterSchema},
    pane: {default: 0}

  # The bookings table inside a batch's detail.
  ITEM_BOOKINGS_POLICY = wsjrdp_expandable_table_policy(
    **Fin::BookkeepingSummaries.item_bookings_policy_options(row_param: :id)
  )

  helper_method :booking_batches, :shown_booking_count, :booking_batch_bookings

  def summary_table_state = wsjrdp_expandable_table_state(SUMMARY_POLICY)

  def item_bookings_table_state = wsjrdp_expandable_table_state(ITEM_BOOKINGS_POLICY)

  # The Buchungsstapel list: every batch the filter leaves, ordered and paged by
  # the summary table's state.
  def booking_batches
    @booking_batches ||= Wsjrdp::ExpandableTableRows.new(summary_table_state,
      filtered_booking_batches,
      sort: Fin::BookingBatchesColumns::BATCHES.sort_expressions,
      tiebreaker: :id)
  end

  # How many bookings the shown batches have between them. A separate COUNT
  # because `booking_count` is a SELECT alias on the grouped relation, which
  # AR's .sum cannot reference directly.
  def shown_booking_count
    @shown_booking_count ||= DatevBooking
      .where(datev_booking_batch_id: filtered_booking_batches.reselect(:id))
      .count
  end

  def index
  end

  def show
    @batch = DatevBookingBatch.find(params[:id])
    @ctx = detail_format_context
    render_item_detail
  end

  # Apply target of the filter builder (PRG, generic implementation in
  # Wsjrdp::TableStateful). The page resets to 1.
  def apply
    wsjrdp_apply_table_filter(summary_table_state, redirect_to: booking_batches_path)
  end

  private

  def authorize_action
    authorize!(:fin_admin, DatevBookingBatch)
  end

  def detail_format_context
    if request.headers["Turbo-Frame"].present?
      Fin::AttrFormatContext.embedded(
        Wsjrdp::TableContext.new(level: summary_table_state.level, lazy: true)
      )
    else
      Fin::AttrFormatContext.regular
    end
  end

  # THE filtered relation -- all batches with their booking count, narrowed by
  # whatever the user's filter state selects.
  def filtered_booking_batches
    @filtered_booking_batches ||=
      summary_table_state.filter.scope(
        DatevBookingBatch.left_joins(:bookings)
          .select("datev_booking_batches.*, COUNT(datev_bookings.id) AS booking_count")
          .group("datev_booking_batches.id")
      )
  end

  # Every booking that belongs to the given Buchungsstapel (Konto perspective).
  def booking_batch_bookings(batch_id)
    item_bookings(DatevBooking.where(datev_booking_batch_id: batch_id))
  end
end
