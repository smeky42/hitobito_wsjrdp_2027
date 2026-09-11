# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Kostenstellen (cost centers) at /bookkeeping/cost_centers: the per-cost-center
# booking sums with the generic CNF filter above them, one expandable detail row
# per cost center, plus a dedicated detail page per number. Cost-center numbers
# may contain letters, so the show route is deliberately unconstrained.
#
# The list is RELATION-backed (WsjrdpCostCenter.with_booking_summary), like the
# other two summary pages: that is what lets the
# filter compile its conditions into SQL, the headers sort on the aggregates and
# the footer count the FILTERED set. It therefore lists every cost center of the
# master data, those without a single booking included (0 / 0,00 EUR); a
# cost-center number that only ever appears on bookings, with no master record of
# its own, is not a row of this list.
class Fin::CostCentersController < Fin::FinController
  include Fin::BookkeepingSummaries

  before_action :authorize_action

  # The one cost center this list never shows, pinned out as a HIDDEN fixed slot
  # below: "9" is a placeholder number carried by a few imported bookings, not a
  # cost center of the plan.
  HIDDEN_COST_CENTER_NUMBER = "9"

  # The "Schnellauswahl" above the filter: each preset is a list of user slots
  # that a click adds or removes (doc/wsjrdp/expandable_table.md, "Presets").
  # "Nur mit Buchungen" is the one click back to what the list showed while it
  # was built from the bookings alone.
  PRESETS = [
    {key: "with_bookings", label: "Nur mit Buchungen",
     slots: [[["booking_count", "nonzero"]]]}
  ].freeze

  # The Kostenstellen list and the bookings table inside a cost center's detail.
  # The list declares its own policy, filter included.
  #
  # The fixed slot is HIDDEN: it is not a filter the user set, so it appears
  # neither as a chip nor in the URL, and no user filter and no "Filter
  # zurücksetzen" can widen the list past it -- fixed slots and user slots are
  # ANDed (D2e). It keeps the cost center out of the rows AND out of the footer
  # totals, because both read the same filtered relation.
  SUMMARY_POLICY = wsjrdp_expandable_table_policy prefix: "",
    columns: Fin::BookkeepingSummaryColumns::COST_CENTERS.codec,
    # No sort by default: the rows arrive in their natural order, by number.
    sort: {default: []},
    cols: {default: Fin::BookkeepingSummaryColumns::COST_CENTERS.default_keys},
    per_page: {default: Fin::BookkeepingSummaries::SUMMARY_DEFAULT_PER},
    filter: {policy: :remember, schema: Fin::CostCentersFilterSchema, presets: PRESETS,
             fixed: [{slots: [[["number", "not_in", HIDDEN_COST_CENTER_NUMBER]]],
                      show: :hidden}]},
    pane: {default: 1}
  ITEM_BOOKINGS_POLICY = wsjrdp_expandable_table_policy(**Fin::BookkeepingSummaries
    .item_bookings_policy_options(row_param: :number, nested: true))

  helper_method :cost_centers, :cost_center_bookings,
    :shown_booking_count, :shown_booking_sum

  def summary_table_state = wsjrdp_expandable_table_state(SUMMARY_POLICY)

  def item_bookings_table_state = wsjrdp_expandable_table_state(ITEM_BOOKINGS_POLICY)

  # The Kostenstellen list: every cost center the filter leaves, ordered and
  # paged by the summary table's state.
  def cost_centers
    @cost_centers ||= Wsjrdp::ExpandableTableRows.new(summary_table_state, filtered_cost_centers,
      sort: Fin::BookkeepingSummaryColumns::COST_CENTERS.sort_expressions,
      tiebreaker: :number)
  end

  # How many BOOKINGS the shown cost centers have between them (the footer's
  # second number; the first is the rows object's count). #to_i because a SUM
  # over a derived table comes back as a BigDecimal -- a count is an Integer.
  def shown_booking_count
    @shown_booking_count ||= filtered_cost_centers.sum(:booking_count).to_i
  end

  # What the shown cost centers add up to (the footer's third number).
  def shown_booking_sum
    @shown_booking_sum ||= filtered_cost_centers.sum(:booking_sum)
  end

  def index
  end

  # One Kostenstelle's detail, as its own page and as the pane the list
  # lazy-loads. A number without master data still shows its bookings, so a
  # cost-center number that only ever appears on bookings becomes a stub record
  # carrying just the number.
  def show
    @cost_center = WsjrdpCostCenter.find_by(number: params[:number]) ||
      WsjrdpCostCenter.new(number: params[:number])
    @ctx = detail_format_context
    render_item_detail
  end

  def update
    @cost_center = WsjrdpCostCenter.find_by!(number: params[:number])
    authorize!(:update, @cost_center)
    if @cost_center.update(cost_center_params)
      redirect_to cost_center_path(@cost_center.number),
        notice: "Kostenstelle wurde aktualisiert."
    else
      @ctx = detail_format_context
      render :show, status: :unprocessable_entity
    end
  end

  # Apply target of the filter builder (PRG, generic implementation in
  # Wsjrdp::TableStateful). The page resets to 1.
  def apply
    wsjrdp_apply_table_filter(summary_table_state, redirect_to: cost_centers_path)
  end

  private

  def authorize_action
    authorize!(:show, WsjrdpCostCenter)
  end

  def cost_center_params
    params.require(:wsjrdp_cost_center).permit(
      :budget_2025, :budget_2026, :budget_2027, :budget_2028, :explicit_total_budget
    )
  end

  # THE filtered relation -- the only way from the state to the rows
  # (state.filter.scope, which applies the hidden fixed slot first), and what
  # both footer totals aggregate over.
  def filtered_cost_centers
    @filtered_cost_centers ||=
      summary_table_state.filter.scope(WsjrdpCostCenter.with_booking_summary)
  end

  # Cost centers stay on the plain bookings (Konto perspective): the detail's
  # list and its sum are the same net cash-flow of the tagged bookings the
  # summary row shows.
  def cost_center_bookings(number)
    item_bookings(DatevBooking.where(cost_center_number: number))
  end

  # WHERE the detail partial renders (Fin::AttrFormatContext): the cost center's
  # own page, or the pane a summary row lazy-loads into its turbo frame -- the
  # same frame request #render_item_detail recognises, at the nesting level the
  # list put into the frame's URL.
  def detail_format_context
    if request.headers["Turbo-Frame"].present?
      Fin::AttrFormatContext.embedded(
        Wsjrdp::TableContext.new(level: summary_table_state.level, lazy: true)
      )
    else
      Fin::AttrFormatContext.regular
    end
  end
end
