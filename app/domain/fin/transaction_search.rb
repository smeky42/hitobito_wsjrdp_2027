# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The search behind the shared transaction picker (shared/wsjrdp/_transaction_picker,
# Fin::TransactionPickerController): bank transactions and Moss transactions of
# the own accounts, as Fin::InternalTransferLeg, narrowed by
#
#   sources   %w[camt moss] (both by default)
#   sign      "out" (money leaving), "in" (arriving) or nil (both)
#   accounts  WsjrdpFinAccount ids; empty = every account
#   from, to  the date range (inclusive); nil = open
#   amount    "677" (every amount from 677,00 to 677,99), "677,48" (exactly),
#             "600-700" (a range) -- on the magnitude, the sign is the sign's job
#   target    a signed amount; only rows of exactly that amount
#   text      words that must all appear in the row's text or counterparty
#   linked    true: also rows that are legs of an Umbuchung already
#   exclude   leg keys never to list (the rows already chosen)
#   anchor    the date the nearest rows come first to; today by default
#
# #legs answers at most LIMIT rows, nearest to the anchor first; #total_count
# says how many match.
class Fin::TransactionSearch
  LIMIT = 100

  def initialize(sources: nil, sign: nil, accounts: nil, from: nil, to: nil, amount: nil, target: nil,
    text: nil, linked: false, exclude: nil, anchor: nil)
    @sources = Array(sources).presence || %w[camt moss]
    @sign = sign
    @accounts = Array(accounts).compact_blank.map(&:to_i)
    @from = from
    @to = to
    @amount = parse_amount(amount)
    @target = target&.to_d
    @words = text.to_s.downcase.split.first(5)
    @linked = linked
    @exclude = Array(exclude).compact_blank
    @anchor = anchor || Date.current
  end

  def legs
    load_legs
    @legs
  end

  # How many rows match, the excluded ones left out (#legs shows LIMIT of them).
  def total_count
    load_legs
    @total_count
  end

  # Is the amount filter given but not understood?
  def invalid_amount? = @amount_text.present? && @amount.nil?

  private

  CAMT_TEXT = %w[description cdtr_name dbtr_name].freeze
  MOSS_TEXT = %w[transaction_name merchant_name top_up_sender transaction_posting_text payment_reference
    recipient_name].freeze

  def camt_scope = WsjrdpCamtTransaction.current

  def moss_scope = MossTransaction.all

  def load_legs
    return if @legs

    matches = 0
    records = []
    {"camt" => [camt_scope, "value_date", "signed_base_amount", CAMT_TEXT],
     "moss" => [moss_scope, "booking_date", "signed_total_base_amount", MOSS_TEXT]}.each do |source, args|
      next unless @sources.include?(source)

      scope = search(*args)
      matches += scope.count
      records += scope.limit(LIMIT + @exclude.size).to_a
    end
    legs = Fin::InternalTransferLeg.wrap(records)
    kept = legs.reject { |leg| @exclude.include?(leg.key) }
    @total_count = matches - (legs.size - kept.size)
    @legs = kept.sort_by { |leg| [(leg.date - @anchor).abs, leg.key] }.first(LIMIT)
  end

  def search(scope, date_column, amount_column, text_columns)
    table = scope.table_name
    scope = scope.where.not(fin_account_id: nil).where.not(date_column => nil).includes(:fin_account)
    scope = scope.where(fin_account_id: @accounts) if @accounts.any?
    scope = scope.without_internal_transfer unless @linked
    scope = scope.where("#{table}.#{amount_column} < 0") if @sign == "out"
    scope = scope.where("#{table}.#{amount_column} > 0") if @sign == "in"
    scope = scope.where("#{table}.#{date_column} >= ?", @from) if @from
    scope = scope.where("#{table}.#{date_column} <= ?", @to) if @to
    scope = scope.where("#{table}.#{amount_column} = ?", @target) if @target
    scope = scope.where("ABS(#{table}.#{amount_column}) BETWEEN ? AND ?", *@amount) if @amount
    @words.each do |word|
      like = "%#{ActiveRecord::Base.sanitize_sql_like(word)}%"
      scope = scope.where(text_columns.map { |column| "#{table}.#{column} ILIKE :like" }.join(" OR "), like: like)
    end
    scope.order(Arel.sql("ABS(#{table}.#{date_column} - DATE '#{@anchor.iso8601}')"), :id)
  end

  # "677" -> 677.00..677.99, "677,48" -> exactly, "600-700" -> the range.
  def parse_amount(value)
    @amount_text = value.to_s.strip
    text = value.to_s.delete(" .€").tr(",", ".")
    return nil if text.blank?

    if (range = text.match(/\A-?(\d+(?:\.\d+)?)-(\d+(?:\.\d+)?)\z/))
      [range[1].to_d, range[2].to_d].minmax
    elsif (single = text.match(/\A-?(\d+)(?:\.(\d{1,2}))?\z/))
      whole = single[1].to_d
      single[2] ? [whole + "0.#{single[2]}".to_d] * 2 : [whole, whole + BigDecimal("0.99")]
    end
  end
end
