# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Personenkonten (personal accounts) at /bookkeeping/personal_accounts --
# currently the Kreditoren (suppliers) view: per-supplier booking sums with a
# 2x3 visibility grid (Moss status x booking situation), one expandable detail
# row per supplier, plus a dedicated detail page per account number.
class Fin::PersonalAccountsController < Fin::FinController
  include Fin::BookkeepingSummaries

  before_action :authorize_action

  # The Kreditoren visibility grid: every supplier falls into exactly one cell,
  # spanned by its Moss status (active/deactivated) and its booking situation
  # (none = no booking, zero = booked but nets to 0, balance = open balance != 0).
  # Rows correspond to the checkbox grid in the view; see supplier_cell_key.
  SUPPLIER_MOSS_STATES = %w[active deactivated].freeze
  SUPPLIER_BOOKING_STATES = %w[none zero balance].freeze

  # Quick-select presets for the Kreditoren view: each maps to the set of grid
  # cells it makes visible. "all" (every cell) is the default and is expressed as
  # a plain reset (no grid param), so it is not listed here.
  SUPPLIER_PRESETS = {
    "booked" => %w[active_zero active_balance deactivated_zero deactivated_balance],
    "balance" => %w[active_balance deactivated_balance],
    "active_booked" => %w[active_zero active_balance]
  }.freeze

  helper_method :supplier_summaries, :supplier_info, :supplier_bookings_query,
    :supplier_records, :supplier_cell_visible?, :supplier_cell_counts,
    :current_supplier_preset

  def index
  end

  def show
    @number = params[:number]
    render_item_detail
  end

  private

  def authorize_action
    authorize!(:fin_admin, WsjrdpPersonalAccount)
  end

  # A creditor is just a (personal) account; the same two-sided legs balance nets
  # a fully settled supplier to 0. Shows ALL known suppliers by default -- those
  # without any booking appear with 0/0. A 2x3 visibility grid (Moss status x
  # booking situation, see supplier_cell_key) hides individual cells, and
  # ?sort/?dir orders it; grid unset / no sort by default (every supplier shown,
  # natural order by number).
  def supplier_summaries
    @supplier_summaries ||=
      sort_summary_rows(
        all_supplier_rows.select { |r| supplier_cell_visible?(supplier_cell_key(r)) },
        summary_row_extractors { |number| supplier_info.dig(number, :name) }
      )
  end

  # Every known supplier as a {number, sum, count} row (unfiltered, by number).
  def all_supplier_rows
    @all_supplier_rows ||= begin
      by_number = leg_summaries(WsjrdpPersonalAccount.select(:number)).index_by { |r| r[:number] }
      WsjrdpPersonalAccount.order(:number).pluck(:number).map do |number|
        by_number[number] || {number: number, sum: 0, count: 0}
      end
    end
  end

  # The Moss status ("active"/"deactivated") of a summary row's supplier.
  def supplier_status(row)
    supplier_info.dig(row[:number], :moss_status)
  end

  # The grid cell a supplier belongs to, e.g. "deactivated_zero". Moss status is
  # collapsed to active/deactivated (only these occur); booking situation is
  # none (no booking) / zero (booked, nets to 0) / balance (open balance != 0).
  def supplier_cell_key(row)
    moss = (supplier_status(row) == "deactivated") ? "deactivated" : "active"
    booking =
      if row[:count].zero?
        "none"
      elsif row[:sum].zero?
        "zero"
      else
        "balance"
      end
    "#{moss}_#{booking}"
  end

  # How many suppliers sit in each grid cell (over ALL suppliers) -- shown next to
  # each checkbox so the grid is self-documenting. Missing cells read 0.
  def supplier_cell_counts
    @supplier_cell_counts ||= all_supplier_rows.each_with_object(Hash.new(0)) do |row, counts|
      counts[supplier_cell_key(row)] += 1
    end
  end

  # The grid is only in effect once its form has been submitted (?grid=1). Before
  # that -- and for any cell whose checkbox is absent from the params -- default to
  # showing everything; a submitted-but-unchecked cell is the only way to hide one.
  def supplier_grid_active?
    params[:grid].present?
  end

  def supplier_cell_visible?(key)
    return true unless supplier_grid_active?
    params.dig(:show, key).present?
  end

  # All six grid cell keys, in row-major order (active first, then deactivated).
  def supplier_cell_keys
    SUPPLIER_MOSS_STATES.product(SUPPLIER_BOOKING_STATES).map { |moss, booking| "#{moss}_#{booking}" }
  end

  # The grid cells currently shown, as a Set (all cells when the grid is off).
  def supplier_visible_cells
    supplier_cell_keys.select { |key| supplier_cell_visible?(key) }.to_set
  end

  # Which quick-select preset the current selection matches: "all" when every
  # cell is shown, a SUPPLIER_PRESETS key on an exact match, else nil (custom).
  def current_supplier_preset
    visible = supplier_visible_cells
    return "all" if visible.size == supplier_cell_keys.size
    SUPPLIER_PRESETS.each { |name, keys| return name if visible == keys.to_set }
    nil
  end

  # Supplier detail lists show every booking that touches the account -- on
  # either side -- valued from the account's own perspective (leg_amount), so
  # the embedded list and its sum agree with the summary row.
  def supplier_bookings_query(number)
    DatevBookingsQuery.new(params, base: DatevBooking.legs.where(leg_account: number),
      sum_column: :leg_amount, default_per: Fin::BookkeepingSummaries::CONDENSED_DEFAULT_PER)
  end

  def supplier_info
    @supplier_info ||= WsjrdpPersonalAccount.pluck(:number, :name, :moss_status)
      .to_h { |number, name, moss_status| [number, {name: name, moss_status: moss_status}] }
  end

  def supplier_records
    @supplier_records ||= WsjrdpPersonalAccount.all.index_by(&:number)
  end
end
