# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The key figures of the Zahlungsverkehr overview (/fin/payments) and of the
# area's card on /fin: the orders by kind, the debits and the returns, the
# open work, the next collection, the collections by month and the return
# reasons. The debit and return figures are person-level sums and only
# computed for whoever may see them (`person_level:`). Every figure is
# memoized.
class Fin::PaymentsOverview
  Kind = Struct.new(:kind, :count, :sum_cents, :transactions, keyword_init: true)
  # The debits announced for the next collection date.
  NextCollection = Data.define(:date, :count, :sum_cents, :try_skip_count, :overdue_count)
  # The direct debits collected in one month, and their returns.
  Month = Data.define(:month, :count, :sum_cents, :return_count) do
    def return_rate = count.positive? ? return_count.fdiv(count) : 0.0
  end
  # A return reason, how often it occurs and its share of all reasons.
  Reason = Data.define(:code, :count, :share)

  def initialize(person_level: false)
    @person_level = person_level
  end

  def person_level? = @person_level

  def orders_count = orders_by_kind.sum(&:count)

  # [Kind, ...] for the kinds that occur, in the order of
  # WsjrdpPaymentInitiation::KINDS.
  def orders_by_kind
    @orders_by_kind ||= begin
      rows = WsjrdpPaymentInitiation.group(Arel.sql(WsjrdpPaymentInitiation.kind_sql))
        .pluck(Arel.sql(WsjrdpPaymentInitiation.kind_sql), Arel.sql("COUNT(*)"), Arel.sql("SUM(control_sum_cents)"),
          Arel.sql("SUM(number_of_transactions)"))
        .to_h do |kind, count, sum, transactions|
          [kind, Kind.new(kind: kind, count: count, sum_cents: sum.to_i, transactions: transactions.to_i)]
        end
      WsjrdpPaymentInitiation::KINDS.filter_map { |kind| rows[kind] }
    end
  end

  # The direct debit orders as one Kind (all zero without any).
  def direct_debit_orders
    orders_by_kind.find { |k| k.kind == WsjrdpPaymentInitiation::DIRECT_DEBIT } ||
      Kind.new(kind: WsjrdpPaymentInitiation::DIRECT_DEBIT, count: 0, sum_cents: 0, transactions: 0)
  end

  # The returns that belong to a direct debit order -- through their debit
  # or the order they name (Fin::PaymentQueries::RETURN_DEBITS_SQL) --, as
  # {return_count:, return_sum_cents:}; returns nothing assigns are left out.
  def direct_debit_returns
    @direct_debit_returns ||= Fin::PaymentQueries.order_totals(direct_debit_order_scope)
      .slice(:return_count, :return_sum_cents)
  end

  # The other returns (Fin::PaymentQueries.other_returns) that name no
  # original (Fin::ReturnOriginals) yet.
  def other_returns_unlinked_count
    @other_returns_unlinked_count ||= Fin::PaymentQueries.other_returns.where(reverses_id: nil).count(:all)
  end

  # {count:, sum_cents:, unassigned_count:}
  def returns
    @returns ||= Fin::PaymentQueries.return_totals(Fin::PaymentQueries.returns)
  end

  # --- the open work ---------------------------------------------------------

  # The returned direct debits still in review (Fin::PaymentReturnsColumns::STATUS_SQL).
  def returns_in_review_count
    @returns_in_review_count ||= Fin::PaymentQueries.returns
      .where(Arel.sql("#{Fin::PaymentReturnsColumns::STATUS_SQL} = 'in_review'")).count(:all)
  end

  # The direct debit orders the bank has whose collective credit is missing,
  # and those whose credits do not add up to the control sum.
  def orders_without_credit_count
    @orders_without_credit_count ||= direct_debit_order_scope
      .where(status: Fin::PaymentsHelper::CREDIT_DUE_STATUSES)
      .where("COALESCE(credits.credit_count, 0) = 0").count(:all)
  end

  def orders_credit_differs_count
    @orders_credit_differs_count ||= direct_debit_order_scope
      .where("credits.credit_count > 0 AND credits.credit_sum_cents <> wsjrdp_payment_initiations.control_sum_cents")
      .count(:all)
  end

  # --- the next collection ---------------------------------------------------

  # The debits only announced (pre_notified) for the next collection date from
  # today on, with those asking to be skipped; overdue_count counts the
  # announced ones whose date has passed. nil without any announced debit.
  def next_collection
    return @next_collection if defined?(@next_collection)

    announced = WsjrdpDirectDebitPreNotification.where(payment_status: Fin::DebitEditing::PRE_NOTIFIED)
    overdue = announced.where(collection_date: ...Date.current).count
    date = announced.where(collection_date: Date.current..).minimum(:collection_date)
    @next_collection = if date || overdue.positive?
      due = announced.where(collection_date: date)
      NextCollection.new(date: date, count: date ? due.count : 0, sum_cents: date ? due.sum(:amount_cents) : 0,
        try_skip_count: date ? due.where(try_skip: true).count : 0, overdue_count: overdue)
    end
  end

  # --- the collections by month ------------------------------------------------

  # The direct debits collected per month of their Sammler's collection date,
  # with the returns of their debits; oldest first.
  def months
    @months ||= WsjrdpDirectDebitPaymentInfo.connection.select_rows(<<~SQL.squish).map do |month, count, cents, returns|
      SELECT date_trunc('month', infos.requested_collection_date)::date, SUM(infos.number_of_transactions),
             SUM(infos.control_sum_cents), COALESCE(SUM(returns.return_count), 0)
      FROM wsjrdp_direct_debit_payment_infos infos
      LEFT JOIN (
        SELECT info_id, COUNT(*) AS return_count FROM (#{Fin::PaymentQueries::RETURN_DEBITS_SQL}) r GROUP BY info_id
      ) returns ON returns.info_id = infos.id
      GROUP BY 1 ORDER BY 1
    SQL
      Month.new(month: month.to_date, count: count.to_i, sum_cents: cents.to_i, return_count: returns.to_i)
    end
  end

  # --- the return reasons ------------------------------------------------------

  # The reasons of all returned direct debits, the most frequent first (a
  # return naming several counts for each).
  def return_reasons
    @return_reasons ||= begin
      tally = Fin::PaymentQueries.returns.pluck(:return_reason).flat_map { |codes| codes.to_s.split }.tally
      total = tally.values.sum
      tally.sort_by { |code, count| [-count, code] }
        .map { |code, count| Reason.new(code: code, count: count, share: count.fdiv(total)) }
    end
  end

  private

  def direct_debit_order_scope
    Fin::PaymentQueries.orders
      .where(Arel.sql("#{WsjrdpPaymentInitiation.kind_sql} = '#{WsjrdpPaymentInitiation::DIRECT_DEBIT}'"))
  end
end
