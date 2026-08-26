# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Reusable query object for listing DatevBookings with filtering, sorting and
# pagination driven by request params. Wrap any base scope:
#
#   DatevBookingsQuery.new(params)                       # all bookings
#   DatevBookingsQuery.new(params, base: account.bookings)
#
# and render it with the shared `fin/bookings/_bookings_table` partial.
class DatevBookingsQuery
  # Column key => SQL sort expression. Acts as an allow-list, so only these
  # (fixed, safe) expressions can ever reach ORDER BY.
  SORTABLE = %w[
    id booking_date service_date amount base_currency account_number
    offsetting_account_number account_type offsetting_account_type cost_center_number
    secondary_cost_center_number original_kost1 original_kost2 sphere_number description
    original_posting_text document_field_1 document_field_2 origin_indicator
    fiscal_year primanota_period primanota_number
  ].index_with { |c| c }.freeze

  DEFAULT_SORT = "booking_date"
  # Newest booking first by default (booking_date DESC), with id ASC always the
  # final tiebreaker (added in #sorted).
  DEFAULT_SORT_DIRECTION = "desc"
  DEFAULT_PER = 50
  MAX_PER = 500
  ALL_PER = 1_000_000 # "Alle" -- effectively unbounded page size

  # Every filter the UI can offer. A filter listed in `hidden_filters` is neither
  # rendered nor honoured from the params (its value is fixed by `base`), so a
  # page can lock e.g. the account it shows. See `filter_available?`.
  ALL_FILTERS = %i[
    account_number offsetting_account_number cost_center period
    booking_date service_date amount search
  ].freeze

  attr_reader :params, :hidden_filters, :default_per, :default_column_keys, :prefix

  # sum_column: the column #total_sum aggregates. Defaults to :amount (Konto
  # perspective). Account/supplier detail views wrap DatevBooking.legs and pass
  # :leg_amount, so the shown sum is the account's own two-sided balance.
  # default_per: page size used while no ?per= param is set; the condensed
  # (in-detail) views pass a smaller default than the full bookings list.
  # default_column_keys: shown columns while no ?cols= param is set (nil ->
  # the helper's DEFAULT_BOOKING_COLUMN_KEYS); hosts like the reconciliation
  # page pass a reduced set.
  # prefix: query-param namespace for the DISPLAY params (page/sort/sort_dir/
  # per/cols), so several bookings listings on one page page independently
  # ("" -> page/sort/...; "bk" -> bk_page/bk_sort/...). See ExpandableTableHelper.
  def initialize(params, base: DatevBooking.all, hidden_filters: [], sum_column: :amount,
    default_per: DEFAULT_PER, default_column_keys: nil, prefix: "")
    @params = params
    @base = base
    @hidden_filters = Array(hidden_filters).map(&:to_sym)
    @sum_column = sum_column
    @default_per = default_per
    @default_column_keys = default_column_keys
    @prefix = prefix.to_s
  end

  # The concrete param name for a namespaced DISPLAY param.
  def param_name(base)
    @prefix.empty? ? base.to_s : "#{@prefix}_#{base}"
  end

  def display_param(base)
    params[param_name(base)]
  end

  # Whether a filter may be set by the user (rendered + read from params).
  def filter_available?(filter)
    !@hidden_filters.include?(filter.to_sym)
  end

  def result
    @result ||= paginate(sorted(filtered))
  end

  # Sorted + filtered scope limited to `count` rows (no pagination); used for the
  # inline preview tables inside another table's expandable detail row.
  def limited(count)
    sorted(filtered).limit(count)
  end

  def total_count
    result.total_count
  end

  # Sum over the whole filtered set (not just the current page). The summed
  # column (`amount` for the Konto perspective, or `leg_amount` for a legs-backed
  # account/supplier view) already carries a baked sign, so a plain SUM is correct.
  def total_sum
    @total_sum ||= filtered.sum(@sum_column)
  end

  # --- current filter / sort state (for the form and headers) ---

  def account_numbers = filter_available?(:account_number) ? array_param(:account_number) : []

  def offsetting_account_numbers
    filter_available?(:offsetting_account_number) ? array_param(:offsetting_account_number) : []
  end

  def cost_centers = filter_available?(:cost_center) ? array_param(:cost_center) : []

  def periods = filter_available?(:period) ? array_param(:period) : []

  def fiscal_years = array_param(:fiscal_year)

  def search = filter_available?(:search) ? params[:q].to_s.strip.presence : nil

  def booking_date_from = filter_available?(:booking_date) ? date_param(:booking_date_from) : nil

  def booking_date_to = filter_available?(:booking_date) ? date_param(:booking_date_to) : nil

  def service_date_from = filter_available?(:service_date) ? date_param(:service_date_from) : nil

  def service_date_to = filter_available?(:service_date) ? date_param(:service_date_to) : nil

  def amount_from = filter_available?(:amount) ? decimal_param(:amount_from) : nil

  def amount_to = filter_available?(:amount) ? decimal_param(:amount_to) : nil

  # Column key <-> short URL abbreviation, in the default column order. Only
  # selectable columns are listed; anything not here cannot be selected.
  COLUMN_ABBREVIATIONS = {
    "booking_date" => "bdt",
    "service_date" => "sdt",
    "amount" => "amt",
    "description" => "description",
    "cost_center_number" => "cc",
    "secondary_cost_center_number" => "cc2",
    "account_number" => "acc",
    "offsetting_account_number" => "oacc",
    "document_field_1" => "df1",
    "document_field_2" => "df2",
    "primanota_period" => "priper",
    "sphere_number" => "sphere"
  }.freeze
  ABBREVIATION_TO_COLUMN = COLUMN_ABBREVIATIONS.invert.freeze

  # Prefix in the `cols` param that marks a HIDDEN column (shown columns are
  # unmarked). "~" is URL-safe (unreserved), so it needs no percent-encoding.
  HIDDEN_MARKER = "~"

  # Decode a `cols` value into ordered [key, active] pairs (all columns, shown
  # and hidden), dropping anything that is not a selectable column.
  def self.decode_column_states(value)
    tokens = value.is_a?(Array) ? value : value.to_s.split(",")
    tokens.filter_map do |t|
      t = t.to_s.strip
      next if t.blank?
      active = !t.start_with?(HIDDEN_MARKER)
      token = active ? t : t[HIDDEN_MARKER.length..]
      key = ABBREVIATION_TO_COLUMN[token] || (COLUMN_ABBREVIATIONS.key?(token) ? token : nil)
      key ? [key, active] : nil
    end
  end

  # Encode ordered [key, active] pairs into the `cols` param form
  # (e.g. bdt,amt,~sdt,description).
  def self.encode_column_states(states)
    states.map do |key, active|
      "#{active ? "" : HIDDEN_MARKER}#{COLUMN_ABBREVIATIONS[key] || key}"
    end.join(",")
  end

  # The [key, active] pairs from the URL, or nil when the param is absent.
  def column_states
    return nil if display_param(:cols).blank?
    self.class.decode_column_states(display_param(:cols))
  end

  # The shown column keys, in order (derived from the column states).
  def column_keys
    (column_states || []).filter_map { |key, active| key if active }
  end

  # The active multi-column sort as [[column, dir], ...] (primary first), decoded
  # from the single RISON <prefix>_sort param (ExpandableTableSort) and mapped
  # from the short column abbreviation to the real column via the allow-list.
  # Falls back to the default single sort when the param yields no valid column.
  def sort_list
    @sort_list ||= begin
      mapped = ExpandableTableSort.decode(display_param(:sort).to_s).filter_map do |token, dir|
        col = ABBREVIATION_TO_COLUMN[token] || (SORTABLE.key?(token) ? token : nil)
        col ? [col, dir] : nil
      end
      mapped.presence || [[DEFAULT_SORT, DEFAULT_SORT_DIRECTION]]
    end
  end

  # Primary sort column / direction (the first level), for callers that only care
  # about the top sort. The default booking_date sort is DESC (newest first).
  def sort_column = sort_list.first.first

  def sort_direction = sort_list.first.last

  def all_per? = display_param(:per).to_s == "all"

  def per_page
    return ALL_PER if all_per?
    per = display_param(:per).to_i
    per = default_per if per <= 0
    [per, MAX_PER].min
  end

  private

  def array_param(key)
    Array(params[key]).map { |v| v.to_s.strip }.compact_blank
  end

  def date_param(key)
    value = params[key].to_s.strip
    return nil if value.blank?
    Date.parse(value)
  rescue ArgumentError
    nil
  end

  # Accepts German (comma) or dot decimals.
  def decimal_param(key)
    value = params[key].to_s.strip.tr(",", ".")
    return nil if value.blank?
    BigDecimal(value)
  rescue ArgumentError
    nil
  end

  def filtered
    @filtered ||= begin
      scope = @base
      scope = scope.where(account_number: account_numbers) if account_numbers.any?
      if offsetting_account_numbers.any?
        scope = scope.where(offsetting_account_number: offsetting_account_numbers)
      end
      scope = scope.where(cost_center_number: cost_centers) if cost_centers.any?
      scope = scope.where(primanota_period: periods) if periods.any?
      scope = scope.where(fiscal_year: fiscal_years) if fiscal_years.any?
      scope = scope.where(booking_date: booking_date_from..) if booking_date_from
      scope = scope.where(booking_date: ..booking_date_to) if booking_date_to
      scope = scope.where(service_date: service_date_from..) if service_date_from
      scope = scope.where(service_date: ..service_date_to) if service_date_to
      scope = scope.where(amount: amount_from..) if amount_from
      scope = scope.where(amount: ..amount_to) if amount_to
      if search
        like = "%#{search}%"
        scope = scope.where(
          "description ILIKE :q OR original_posting_text ILIKE :q OR document_field_1 ILIKE :q",
          q: like
        )
      end
      scope
    end
  end

  # Multi-column ORDER BY built from sort_list, each level via the SORTABLE
  # allow-list (so only fixed, safe expressions reach SQL), NULLS LAST, with a
  # final id ASC tiebreaker for a stable, deterministic page order.
  def sorted(scope)
    order = sort_list.map { |col, dir| "#{SORTABLE.fetch(col)} #{dir.to_s.upcase} NULLS LAST" }
    order << "id ASC"
    scope.reorder(Arel.sql(order.join(", ")))
  end

  def paginate(scope)
    scope.page(display_param(:page)).per(per_page)
  end
end
