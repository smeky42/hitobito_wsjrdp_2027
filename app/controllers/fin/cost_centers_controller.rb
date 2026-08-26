# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Kostenstellen (cost centers) at /bookkeeping/cost_centers: the per-cost-center
# booking sums, one expandable detail row per cost center, plus a dedicated
# detail page per number. Cost-center numbers may contain letters, so the show
# route is deliberately unconstrained.
class Fin::CostCentersController < Fin::FinController
  include Fin::BookkeepingSummaries

  before_action :authorize_action

  helper_method :cost_center_summaries, :cost_center_info,
    :cost_center_bookings_query, :cost_center_records

  def index
  end

  def show
    @number = params[:number]
    render_item_detail
  end

  private

  def authorize_action
    authorize!(:fin_admin, WsjrdpCostCenter)
  end

  def cost_center_summaries
    @cost_center_summaries ||=
      sort_summary_rows(summarize_cost_centers,
        summary_row_extractors { |number| cost_center_info.dig(number, :name) })
  end

  # Cost-center totals sum `amount` (Konto perspective) -- net cash-flow of the
  # tagged bookings, unchanged for now (semantics pending; see doc/bookkeeping.md).
  def summarize_cost_centers
    DatevBooking.where.not(cost_center_number: nil)
      .group(:cost_center_number).order(:cost_center_number)
      .pluck(:cost_center_number, Arel.sql("SUM(amount)"), Arel.sql("COUNT(*)"))
      .map { |number, sum, count| {number: number, sum: sum, count: count} }
  end

  def cost_center_info
    @cost_center_info ||= WsjrdpCostCenter.pluck(:number, :name, :moss_status)
      .to_h { |number, name, moss_status| [number, {name: name, moss_status: moss_status}] }
  end

  # Cost centers stay on the plain bookings (Konto perspective), unchanged.
  def cost_center_bookings_query(number)
    DatevBookingsQuery.new(params, base: DatevBooking.where(cost_center_number: number),
      default_per: Fin::BookkeepingSummaries::CONDENSED_DEFAULT_PER)
  end

  def cost_center_records
    @cost_center_records ||= WsjrdpCostCenter.all.index_by(&:number)
  end
end
