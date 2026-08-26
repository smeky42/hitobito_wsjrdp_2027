# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Shared plumbing of the Buchhaltung pages (Fin::LedgerAccountsController,
# Fin::CostCentersController, Fin::PersonalAccountsController,
# Fin::BookingBatchesController): the expandable-table summary sorting, the
# two-sided per-account totals over DatevBooking.legs, the grand totals shown
# under every summary table, and the shared full-page/turbo-frame rendering of
# the per-item detail pages.
module Fin::BookkeepingSummaries
  extend ActiveSupport::Concern

  # Default page size of the condensed bookings tables inside the detail views
  # (the full bookings list keeps DatevBookingsQuery::DEFAULT_PER).
  CONDENSED_DEFAULT_PER = 25

  included do
    helper_method :open_keys, :total_sum, :total_count
  end

  private

  # The detail views are shown both as a full page (eye icon) and lazy-loaded into
  # an inline expandable row via a turbo frame; the latter is a frame request and
  # needs no layout (the frame partial carries its own markup).
  def render_item_detail
    render layout: false if request.headers["Turbo-Frame"].present?
  end

  # Keys whose detail row is open, driven by the ?open=a,b,c param.
  def open_keys
    @open_keys ||= params[:open].to_s.split(",").map(&:strip).compact_blank.to_set
  end

  # --- summary-table sorting (server-side, in-memory; see doc/expandable_table.md)
  #
  # All summary tables use the widget's MULTI-column sort: one `?sort` param,
  # RISON-encoded by ExpandableTableSort, holding several column symbols (the
  # columns' `abbr`) + per-column direction in priority order. These extractors
  # map each sortable symbol to a ->(row){ comparable } and whitelist the symbols.

  # nr / sum / cnt are identical for every summary row; only the name (bez) lookup
  # differs, so the caller passes a ->(number){ name } block. Keys are the column
  # `abbr` tokens that appear in the URL.
  def summary_row_extractors(&name_for)
    {
      "nr" => ->(r) { r[:number].to_i },
      "bez" => ->(r) { name_for.call(r[:number]).to_s.downcase },
      "sum" => ->(r) { r[:sum] },
      "cnt" => ->(r) { r[:count] }
    }
  end

  # Stable multi-key sort: compare on each sorted column in priority order (with
  # its direction), tie-broken by number so equal rows stay deterministic. An
  # empty / unparseable ?sort keeps the incoming natural order (by number).
  def sort_summary_rows(rows, extractors)
    list = ExpandableTableSort.decode(params[:sort].to_s).select { |sym, _| extractors.key?(sym) }
    return rows if list.empty?
    rows.sort do |a, b|
      cmp = 0
      list.each do |sym, dir|
        c = extractors[sym].call(a) <=> extractors[sym].call(b)
        c = 0 if c.nil?
        c = -c if dir == "desc"
        (cmp = c).zero? || break
      end
      cmp.zero? ? (a[:number].to_i <=> b[:number].to_i) : cmp
    end
  end

  # Two-sided per-account totals over DatevBooking.legs, restricted to the given
  # account numbers (a relation or array). leg_amount carries the per-account
  # baked sign, so SUM is directly meaningful; COUNT is the number of bookings
  # touching the account.
  def leg_summaries(numbers)
    DatevBooking.legs.where(leg_account: numbers)
      .group(:leg_account).order(:leg_account)
      .pluck(:leg_account, Arel.sql("SUM(leg_amount)"), Arel.sql("COUNT(*)"))
      .map { |number, sum, count| {number: number, sum: sum, count: count} }
  end

  def total_sum
    @total_sum ||= DatevBooking.sum(:amount)
  end

  def total_count
    @total_count ||= DatevBooking.count
  end
end
