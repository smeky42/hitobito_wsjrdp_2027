# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The relations behind the Zahlungsverkehr area (doc/fin/payments.md): the
# orders, the debits and the returns, each with the figures its list shows as
# ordinary columns, so that the lists sort, filter and sum them in SQL.
#
# A RETURN is a bank transaction (WsjrdpCamtTransaction) with a return reason
# -- the bank statement is the record; the accounting entry booked for it is
# derived from it. A return reaches its debit by the link it carries
# (direct_debit_pre_notification_id, set by the importer or by hand); an
# unlinked one by its end-to-end id, else -- where the bank sent an end-to-end
# id of its own -- by its mandate reference and a collection date at most
# MANDATE_DAYS before its value date. Through the debit it reaches its Sammler
# and order; a return that finds no debit keeps the order it names itself
# (payment_initiation_id), else it has none and is "not assignable".
#
# A CREDIT is the bank's collective credit of a Sammler: a current
# WsjrdpCamtTransaction.collections row naming the Sammler and its order.
module Fin::PaymentQueries
  MANDATE_DAYS = 5

  # A return, on the bank transactions aliased `camt`.
  def self.return_condition(camt)
    "#{camt}.return_reason IS NOT NULL AND #{camt}.deleted_at IS NULL AND #{camt}.replaced_by_id IS NULL"
  end

  # How a return found its debit (`notice.matched_by`).
  MATCHED_BY_LINK = "link"
  MATCHED_BY_ENDTOEND = "endtoend"
  MATCHED_BY_MANDATE = "mandate"

  # The debit of the return `camt` (an SQL alias) as `notice`: the one it links
  # to; an unlinked return's the one with its end-to-end id, else the newest
  # collected one of its mandate within MANDATE_DAYS before its value date.
  # `matched_by` says which way, `info_id` its Sammler
  # (.payment_info_debit_condition).
  def self.return_notice_join(camt)
    by_endtoend = "(#{camt}.direct_debit_pre_notification_id IS NULL AND notices.endtoend_id = #{camt}.endtoend_id)"
    <<~SQL.squish
      LEFT JOIN LATERAL (
        SELECT notices.id, notices.payment_initiation_id, notices.amount_cents, notices.collection_date,
               CASE WHEN notices.id = #{camt}.direct_debit_pre_notification_id THEN '#{MATCHED_BY_LINK}'
                    WHEN #{by_endtoend} THEN '#{MATCHED_BY_ENDTOEND}'
                    ELSE '#{MATCHED_BY_MANDATE}' END AS matched_by,
               COALESCE(notices.direct_debit_payment_info_id, (
                 SELECT infos.id FROM wsjrdp_direct_debit_payment_infos infos
                 WHERE #{payment_info_debit_condition("notices", "infos")}
                 ORDER BY infos.id LIMIT 1)) AS info_id
        FROM wsjrdp_direct_debit_pre_notifications notices
        WHERE notices.id = #{camt}.direct_debit_pre_notification_id
           OR #{by_endtoend}
           OR (#{camt}.direct_debit_pre_notification_id IS NULL AND notices.mandate_id = #{camt}.mandate_id
               AND notices.payment_status = 'xml_generated'
               AND notices.collection_date BETWEEN #{camt}.value_date - #{MANDATE_DAYS} AND #{camt}.value_date)
        ORDER BY (notices.id = #{camt}.direct_debit_pre_notification_id) IS TRUE DESC,
                 #{by_endtoend} IS TRUE DESC, notices.collection_date DESC, notices.id DESC
        LIMIT 1
      ) notice ON TRUE
    SQL
  end

  # The bank's collective credits of a Sammler or an order, grouped by the
  # `column` they name: counted, summed, the first one's id and the last
  # value date.
  def self.credits_join(column, on)
    <<~SQL.squish
      LEFT JOIN (
        SELECT credits.#{column} AS credit_key, COUNT(*) AS credit_count,
               SUM(#{return_cents("credits")}) AS credit_sum_cents, MIN(credits.id) AS credit_id,
               MAX(credits.value_date) AS credit_date
        FROM wsjrdp_camt_transactions credits
        WHERE credits.#{column} IS NOT NULL AND credits.deleted_at IS NULL AND credits.replaced_by_id IS NULL
          AND credits.return_reason IS NULL AND credits.debit_credit = 'C'
          AND credits.entry_or_details = 'entry'
        GROUP BY credits.#{column}
      ) credits ON credits.credit_key = #{on}
    SQL
  end

  # A bank transaction's amount in cents (a return's negative: money taken
  # back).
  def self.return_cents(camt) = "ROUND(#{camt}.signed_base_amount * 100)::bigint"

  # Whether the debit `notice` belongs to the payment info `info` (SQL
  # aliases): it names the payment info, or -- as the debits of the later
  # orders do, which name none -- it has the payment info's order, sequence
  # type and collection date.
  def self.payment_info_debit_condition(notice, info)
    "(#{notice}.direct_debit_payment_info_id = #{info}.id OR (#{notice}.direct_debit_payment_info_id IS NULL " \
      "AND #{notice}.payment_initiation_id = #{info}.payment_initiation_id " \
      "AND #{notice}.debit_sequence_type = #{info}.debit_sequence_type " \
      "AND #{notice}.collection_date = #{info}.requested_collection_date))"
  end

  # Every return with its debit, Sammler and order -- the one place the lists'
  # return figures come from.
  RETURN_DEBITS_SQL = <<~SQL.squish
    SELECT camt.id AS camt_id, #{return_cents("camt")} AS amount_cents, camt.return_reason,
           COALESCE(camt.booking_date, camt.value_date) AS return_date, notice.id AS notice_id,
           COALESCE(notice.payment_initiation_id, camt.payment_initiation_id) AS order_id,
           COALESCE(notice.info_id, camt.direct_debit_payment_info_id) AS info_id
    FROM wsjrdp_camt_transactions camt #{return_notice_join("camt")}
    WHERE #{return_condition("camt")}
  SQL

  # The order a return belongs to, in a query that joined its debit as
  # `notice` (#returns).
  RETURN_ORDER_SQL = "COALESCE(notice.payment_initiation_id, wsjrdp_camt_transactions.payment_initiation_id)"

  # Per order: the dates and sequence types of its payment infos (Sammler).
  ORDER_INFOS_JOIN = <<~SQL.squish
    LEFT JOIN LATERAL (
      SELECT MIN(infos.requested_collection_date) AS first_date,
             MAX(infos.requested_collection_date) AS last_date,
             STRING_AGG(DISTINCT infos.debit_sequence_type, ' ' ORDER BY infos.debit_sequence_type) AS sequence_types,
             COUNT(*) AS info_count
      FROM wsjrdp_direct_debit_payment_infos infos
      WHERE infos.payment_initiation_id = wsjrdp_payment_initiations.id
    ) infos ON TRUE
  SQL

  # Per order: its debits that were skipped.
  ORDER_NOTICES_JOIN = <<~SQL.squish
    LEFT JOIN LATERAL (
      SELECT COUNT(*) FILTER (WHERE notices.payment_status = 'skipped') AS skipped_count
      FROM wsjrdp_direct_debit_pre_notifications notices
      WHERE notices.payment_initiation_id = wsjrdp_payment_initiations.id
    ) notices ON TRUE
  SQL

  # Per order: its returns, counted and summed (negative cents).
  ORDER_RETURNS_JOIN = <<~SQL.squish
    LEFT JOIN (
      SELECT order_id, COUNT(*) AS return_count, SUM(amount_cents) AS return_sum_cents
      FROM (#{RETURN_DEBITS_SQL}) returns GROUP BY order_id
    ) returns ON returns.order_id = wsjrdp_payment_initiations.id
  SQL

  # The contingent's account the order was sent from: the one whose IBAN is the
  # initiating party's, compared without spaces and case.
  ORDER_ACCOUNT_JOIN = <<~SQL.squish
    LEFT JOIN LATERAL (
      SELECT accounts.id, accounts.short_name, accounts.account_identification
      FROM wsjrdp_fin_accounts accounts
      WHERE accounts.deleted_at IS NULL
        AND REPLACE(UPPER(COALESCE(accounts.iban, accounts.account_identification)), ' ', '') =
            REPLACE(UPPER(wsjrdp_payment_initiations.initiating_party_iban), ' ', '')
      ORDER BY accounts.id LIMIT 1
    ) accounts ON TRUE
  SQL

  ORDER_CREDITS_JOIN = credits_join("payment_initiation_id", "wsjrdp_payment_initiations.id")

  # Per payment info (Sammler): the returns of its debits.
  PAYMENT_INFO_RETURNS_JOIN = <<~SQL.squish
    LEFT JOIN (
      SELECT info_id, COUNT(*) AS return_count, SUM(amount_cents) AS return_sum_cents
      FROM (#{RETURN_DEBITS_SQL}) returns GROUP BY info_id
    ) returns ON returns.info_id = wsjrdp_direct_debit_payment_infos.id
  SQL

  PAYMENT_INFO_CREDITS_JOIN = credits_join("direct_debit_payment_info_id", "wsjrdp_direct_debit_payment_infos.id")

  # The status of a Sammler's order: a credit is due once its SEPA file went
  # to the bank.
  PAYMENT_INFO_ORDER_JOIN = "LEFT JOIN wsjrdp_payment_initiations info_orders " \
    "ON info_orders.id = wsjrdp_direct_debit_payment_infos.payment_initiation_id"

  # Per debit: its collection entry (the first, should there be more).
  DEBIT_ENTRY_JOIN = <<~SQL.squish
    LEFT JOIN LATERAL (
      SELECT entries.id, entries.amount_cents
      FROM accounting_entries entries
      WHERE entries.direct_debit_pre_notification_id = wsjrdp_direct_debit_pre_notifications.id
        AND entries.return_reason IS NULL
      ORDER BY entries.id LIMIT 1
    ) entry ON TRUE
  SQL

  # Per debit: its returns.
  DEBIT_RETURNS_JOIN = <<~SQL.squish
    LEFT JOIN (
      SELECT notice_id, COUNT(*) AS return_count, SUM(amount_cents) AS return_sum_cents,
             STRING_AGG(DISTINCT return_reason, ' ' ORDER BY return_reason) AS return_reasons,
             MAX(return_date) AS return_date
      FROM (#{RETURN_DEBITS_SQL}) returns GROUP BY notice_id
    ) returns ON returns.notice_id = wsjrdp_direct_debit_pre_notifications.id
  SQL

  DEBIT_PERSON_JOIN = "LEFT JOIN people ON people.id = wsjrdp_direct_debit_pre_notifications.subject_id " \
    "AND wsjrdp_direct_debit_pre_notifications.subject_type = 'Person'"

  RETURN_NOTICE_JOIN = return_notice_join("wsjrdp_camt_transactions")

  # Per return: the accounting entry booked for it (the first, should there
  # be more).
  RETURN_ENTRY_JOIN = <<~SQL.squish
    LEFT JOIN LATERAL (
      SELECT entries.id FROM accounting_entries entries
      WHERE entries.camt_transaction_id = wsjrdp_camt_transactions.id
      ORDER BY entries.id LIMIT 1
    ) entry ON TRUE
  SQL

  RETURN_PERSON_JOIN = "LEFT JOIN people ON people.id = wsjrdp_camt_transactions.subject_id " \
    "AND wsjrdp_camt_transactions.subject_type = 'Person'"

  module_function

  # Every order with its kind, its account and the figures of its payment
  # infos,
  # debits and returns.
  def orders
    WsjrdpPaymentInitiation
      .select("wsjrdp_payment_initiations.*", "#{WsjrdpPaymentInitiation.kind_sql} AS kind",
        "infos.first_date", "infos.last_date", "infos.sequence_types", "infos.info_count",
        "notices.skipped_count", "COALESCE(returns.return_count, 0) AS return_count",
        "COALESCE(returns.return_sum_cents, 0) AS return_sum_cents",
        "accounts.id AS fin_account_id", "accounts.short_name AS fin_account_short_name",
        "accounts.account_identification AS fin_account_identification",
        "COALESCE(credits.credit_count, 0) AS credit_count", "credits.credit_sum_cents", "credits.credit_id",
        "credits.credit_date")
      .joins(ORDER_INFOS_JOIN).joins(ORDER_NOTICES_JOIN).joins(ORDER_RETURNS_JOIN).joins(ORDER_ACCOUNT_JOIN)
      .joins(ORDER_CREDITS_JOIN)
  end

  # The sums under a list of orders: {count:, sum_cents:, return_count:,
  # return_sum_cents:}.
  def order_totals(orders)
    totals(orders, count: "SUM(o.number_of_transactions)", sum_cents: "SUM(o.control_sum_cents)",
      return_count: "SUM(o.return_count)", return_sum_cents: "SUM(o.return_sum_cents)")
  end

  # Every debit (pre-notification) with its collection entry, its returns and
  # its person.
  def debits
    WsjrdpDirectDebitPreNotification
      .select("wsjrdp_direct_debit_pre_notifications.*", "entry.id AS entry_id",
        "entry.amount_cents AS entry_amount_cents", "COALESCE(returns.return_count, 0) AS return_count",
        "COALESCE(returns.return_sum_cents, 0) AS return_sum_cents", "returns.return_reasons", "returns.return_date")
      .joins(DEBIT_ENTRY_JOIN).joins(DEBIT_RETURNS_JOIN).joins(DEBIT_PERSON_JOIN)
  end

  def debit_totals(debits)
    totals(debits, count: "COUNT(*)", sum_cents: "SUM(o.amount_cents)",
      return_count: "SUM(o.return_count)", return_sum_cents: "SUM(o.return_sum_cents)")
  end

  # Every return (a bank transaction) with its amount in cents, its debit --
  # `notice_matched_by` says how it found it --, Sammler and
  # order, the accounting entry booked for it and its person.
  def returns
    WsjrdpCamtTransaction.where(Arel.sql(return_condition("wsjrdp_camt_transactions")))
      .select("wsjrdp_camt_transactions.*", "#{return_cents("wsjrdp_camt_transactions")} AS amount_cents",
        "notice.id AS notice_id", "notice.collection_date AS notice_collection_date",
        "notice.matched_by AS notice_matched_by", "#{RETURN_ORDER_SQL} AS order_id",
        "COALESCE(notice.info_id, wsjrdp_camt_transactions.direct_debit_payment_info_id) AS info_id",
        "entry.id AS return_entry_id")
      .joins(RETURN_NOTICE_JOIN).joins(RETURN_ENTRY_JOIN).joins(RETURN_PERSON_JOIN)
  end

  def return_totals(returns)
    totals(returns, count: "COUNT(*)", sum_cents: "SUM(o.amount_cents)",
      unassigned_count: "COUNT(*) FILTER (WHERE o.order_id IS NULL)",
      without_entry_count: "COUNT(*) FILTER (WHERE o.return_entry_id IS NULL)")
  end

  # Every payment info (Sammler) with the returns of its debits, by date and
  # sequence type; those of the orders with `order_ids` if given.
  def payment_infos(order_ids = nil)
    infos = WsjrdpDirectDebitPaymentInfo
      .select("wsjrdp_direct_debit_payment_infos.*", "COALESCE(returns.return_count, 0) AS return_count",
        "COALESCE(returns.return_sum_cents, 0) AS return_sum_cents", "info_orders.status AS order_status",
        "COALESCE(credits.credit_count, 0) AS credit_count", "credits.credit_sum_cents", "credits.credit_id",
        "credits.credit_date")
      .joins(PAYMENT_INFO_RETURNS_JOIN).joins(PAYMENT_INFO_ORDER_JOIN).joins(PAYMENT_INFO_CREDITS_JOIN)
      .order(:requested_collection_date, :debit_sequence_type, :id)
    order_ids.nil? ? infos : infos.where(payment_initiation_id: order_ids)
  end

  # One payment info with the returns of its debits.
  def payment_info(id) = payment_infos.reorder(nil).find(id)

  # The debits of a payment info (.payment_info_debit_condition).
  def payment_info_debits(info)
    debits.joins("JOIN wsjrdp_direct_debit_payment_infos info ON info.id = #{Integer(info.id)}")
      .where(Arel.sql(payment_info_debit_condition("wsjrdp_direct_debit_pre_notifications", "info")))
  end

  def payment_info_totals(infos)
    totals(infos, count: "SUM(o.number_of_transactions)", sum_cents: "SUM(o.control_sum_cents)",
      return_count: "SUM(o.return_count)", return_sum_cents: "SUM(o.return_sum_cents)")
  end

  # The sums of `expressions` over a list's whole (filtered, unpaged)
  # relation, which the query wraps as `o`.
  def totals(relation, **expressions)
    values = WsjrdpPaymentInitiation.connection.select_one(
      "SELECT #{expressions.map { |key, sql| "#{sql} AS #{key}" }.join(", ")} " \
      "FROM (#{relation.unscope(:order, :limit, :offset).to_sql}) o"
    )
    expressions.keys.index_with { |key| values[key.to_s].to_i }
  end
end
