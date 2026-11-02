# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The key figures of the Zahlungsverkehr overview (/fin/payments) and of the
# area's card on /fin: the orders by kind, the debits and the returns. The
# debit and return figures are person-level sums and only computed for whoever
# may see them (`person_level:`). Every figure is memoized.
class Fin::PaymentsOverview
  Kind = Struct.new(:kind, :count, :sum_cents, :transactions, keyword_init: true)

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
    @direct_debit_returns ||= begin
      orders = Fin::PaymentQueries.orders
        .where(Arel.sql("#{WsjrdpPaymentInitiation.kind_sql} = '#{WsjrdpPaymentInitiation::DIRECT_DEBIT}'"))
      Fin::PaymentQueries.order_totals(orders).slice(:return_count, :return_sum_cents)
    end
  end

  def last_order_date
    @last_order_date ||= WsjrdpPaymentInitiation.maximum(:created_at)&.to_date
  end

  def debits_count
    @debits_count ||= WsjrdpDirectDebitPreNotification.count
  end

  def debits_skipped_count
    @debits_skipped_count ||= WsjrdpDirectDebitPreNotification.where(payment_status: "skipped").count
  end

  # {count:, sum_cents:, unassigned_count:}
  def returns
    @returns ||= Fin::PaymentQueries.return_totals(Fin::PaymentQueries.returns)
  end
end
