# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Sort / paginate / column-selection / sum layer for the Moss card transactions
# listing, driven by request params. Filtering is owned by the generic CNF
# filter (MossCardTransactionsFilter) whose compiled scope is passed in as
# `base` -- analogous to DatevBookingsQuery.
#
# `base` is the filtered scope, which LEFT JOINs the bookings (so booking-level
# filters can match). A transaction with several matching splits would appear
# more than once, so the query DE-DUPLICATES: it selects the matching transaction
# ids and re-queries moss_card_transactions by id (clean, index-friendly, no
# join in the outer sort/paginate). Bookings are eager-loaded to avoid N+1 in
# the table's aggregate columns and the expandable detail.
class MossCardTransactionsQuery
  # Column key => SQL sort expression (allow-list; only these reach ORDER BY).
  SORTABLE = %w[
    id booking_date payment_date settlement_date approval_date total_amount
    merchant_name cardholder transaction_state invoice_number
  ].index_with { |c| c }.freeze

  DEFAULT_SORT = "booking_date"
  DEFAULT_SORT_DIRECTION = "desc"
  DEFAULT_PER = 50
  MAX_PER = 500
  ALL_PER = 1_000_000

  # Column key <-> short URL abbreviation (also the picker order). Includes the
  # derived (non-sortable) aggregate columns so they too can be toggled.
  COLUMN_ABBREVIATIONS = {
    "booking_date" => "bdt",
    "payment_date" => "pdt",
    "settlement_date" => "sdt",
    "merchant_name" => "mer",
    "cardholder" => "ch",
    "total_amount" => "amt",
    "bookings_count" => "nb",
    "account_numbers" => "acc",
    "cost_centers" => "cc",
    "parent_booking_text" => "bt",
    "transaction_state" => "st",
    "invoice_number" => "inv",
    "has_receipt" => "rcpt"
  }.freeze
  ABBREVIATION_TO_COLUMN = COLUMN_ABBREVIATIONS.invert.freeze
  HIDDEN_MARKER = "~"

  attr_reader :params, :default_per, :default_column_keys, :prefix

  def initialize(params, base: MossCardTransaction.all, default_per: DEFAULT_PER,
    default_column_keys: nil, prefix: "")
    @params = params
    @base = base
    @default_per = default_per
    @default_column_keys = default_column_keys
    @prefix = prefix.to_s
  end

  def param_name(base)
    @prefix.empty? ? base.to_s : "#{@prefix}_#{base}"
  end

  def display_param(base)
    params[param_name(base)]
  end

  # De-duplicated transaction scope (drops the bookings join of the filtered
  # base): WHERE id IN (SELECT moss_card_transactions.id FROM <filtered base>).
  def scope
    @scope ||= MossCardTransaction.where(id: @base.reselect(MossCardTransaction.arel_table[:id]))
  end

  def result
    @result ||= paginate(sorted(scope.includes(:bookings)))
  end

  def limited(count)
    sorted(scope.includes(:bookings)).limit(count)
  end

  def total_count
    result.total_count
  end

  # Sum of the transaction totals over the whole filtered (de-duplicated) set.
  def total_sum
    @total_sum ||= scope.sum(:total_amount)
  end

  # --- column selection -----------------------------------------------------

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

  def self.encode_column_states(states)
    states.map { |key, active| "#{active ? "" : HIDDEN_MARKER}#{COLUMN_ABBREVIATIONS[key] || key}" }.join(",")
  end

  def column_states
    return nil if display_param(:cols).blank?
    self.class.decode_column_states(display_param(:cols))
  end

  def column_keys
    (column_states || []).filter_map { |key, active| key if active }
  end

  # --- sorting --------------------------------------------------------------

  def sort_list
    @sort_list ||= begin
      mapped = ExpandableTableSort.decode(display_param(:sort).to_s).filter_map do |token, dir|
        col = ABBREVIATION_TO_COLUMN[token] || (SORTABLE.key?(token) ? token : nil)
        col ? [col, dir] : nil
      end
      mapped.presence || [[DEFAULT_SORT, DEFAULT_SORT_DIRECTION]]
    end
  end

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

  def sorted(rel)
    order = sort_list.map { |col, dir| "#{SORTABLE.fetch(col)} #{dir.to_s.upcase} NULLS LAST" }
    order << "id ASC"
    rel.reorder(Arel.sql(order.join(", ")))
  end

  def paginate(rel)
    rel.page(display_param(:page)).per(per_page)
  end
end
