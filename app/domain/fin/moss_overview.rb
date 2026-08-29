# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Key figures of the Moss section overview (/fin/moss): counts and sums per
# kind, the structure (expenses / bookings), the link state towards DATEV and
# the Beitragsbuchungen, and the data freshness per export. Read-only; every
# figure is one aggregate query, memoized per instance (one per request).
class Fin::MossOverview
  KINDS = Fin::MossTransactionsFilterSchema::KINDS

  # Per kind: how many transactions, expenses (L2) and bookings (L3) it has,
  # how many of its transactions were paid in another currency, plus the sum
  # and the data freshness.
  KindStats = Struct.new(:kind, :count, :expenses_count, :bookings_count, :foreign_currency_count,
    :sum, :last_payment_date, :source_file, keyword_init: true) do
    # The average transaction amount, signed like the sum (0 without transactions).
    def average = count.positive? ? sum / count : 0
  end

  # One KindStats per kind, in KINDS order (kinds without a row report 0).
  def kinds
    @kinds ||= begin
      counts = MossTransaction.group(:type).count
      expenses = MossExpense.joins(:moss_transaction).group("moss_transactions.type").count
      bookings = MossBooking.joins(:moss_transaction).group("moss_transactions.type").count
      foreign = foreign_currency_transactions.group(:type).count
      sums = MossTransaction.group(:type).sum(:signed_total_base_amount)
      dates = MossTransaction.group(:type).maximum(:payment_date)
      files = MossTransaction.group(:type).maximum(:source_file)
      KINDS.map do |kind|
        KindStats.new(kind: kind, count: counts[kind] || 0, expenses_count: expenses[kind] || 0,
          bookings_count: bookings[kind] || 0, foreign_currency_count: foreign[kind] || 0,
          sum: sums[kind] || 0, last_payment_date: dates[kind], source_file: files[kind])
      end
    end
  end

  def total_count = kinds.sum(&:count)

  # Sum over all transactions, signed from the wallet's point of view (top-ups
  # positive, spend negative) -- the wallet balance implied by the Moss data.
  def total_sum = kinds.sum(&:sum)

  # The average transaction amount over all kinds, signed like the sum.
  def total_average = total_count.positive? ? total_sum / total_count : 0

  # The totals are the kinds' figures added up, so the structure block's
  # levels and its bars share one set of numbers.
  def expenses_count = kinds.sum(&:expenses_count)

  def bookings_count = kinds.sum(&:bookings_count)

  def foreign_currency_count = kinds.sum(&:foreign_currency_count)

  # Transactions paid in a currency other than the base currency (the same
  # rule as MossTransaction#foreign_currency?).
  def foreign_currency_transactions
    MossTransaction.where.not(currency_original: nil)
      .where("moss_transactions.currency_original <> moss_transactions.currency")
  end

  def clearing_linked_count
    @clearing_linked_count ||= MossTransaction.where.not(clearing_datev_booking_id: nil).count
  end

  def clearing_unlinked_count = total_count - clearing_linked_count

  def expense_linked_count
    @expense_linked_count ||= MossBooking.where.not(expense_datev_booking_id: nil).count
  end

  def expense_unlinked_count = bookings_count - expense_linked_count

  def contribution_linked_count
    @contribution_linked_count ||= AccountingEntry.where.not(moss_booking_id: nil).count
  end

  def last_payment_date = kinds.filter_map(&:last_payment_date).max

  # When the Moss tables were last written (import or manual edit).
  def last_import_at
    @last_import_at ||= [MossTransaction.maximum(:created_at), MossTransaction.maximum(:updated_at)].compact.max
  end

  # The Moss wallet fin account (the transactions' fin_account), if any.
  def wallet_account
    return @wallet_account if defined?(@wallet_account)

    @wallet_account = WsjrdpFinAccount.find_by(id: MossTransaction.where.not(fin_account_id: nil).distinct.pluck(:fin_account_id))
  end
end
