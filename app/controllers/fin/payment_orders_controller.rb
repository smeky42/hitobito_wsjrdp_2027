# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Aufträge" tab of the Zahlungsverkehr area at /fin/payments/orders: every
# payment order (a SEPA file, direct debit or credit transfer) with its kind,
# its account and the sums of its debits and returns. An order's page
# (/fin/payments/orders/:id) shows its head, its Sammler (direct debit
# payment infos) and -- for a direct debit, with :log on WsjrdpFinAccount --
# its debits (Fin::DirectDebitsSection); the row's detail in the list shows
# the head and the Sammler only. An order of several Sammler brings one
# sub-row per Sammler. See doc/fin/payments.md.
#
# The list names nobody, so whoever sees the accounts sees it.
class Fin::PaymentOrdersController < Fin::FinController
  include Wsjrdp::TableStateful
  include Fin::DirectDebitsSection

  before_action :authorize_action

  TIEBREAKER = "wsjrdp_payment_initiations.id DESC"

  POLICY = wsjrdp_expandable_table_policy prefix: "",
    columns: Fin::PaymentOrdersColumns::COLUMNS.codec,
    sort: {hidden: [["created_at", "desc"]]},
    cols: {default: Fin::PaymentOrdersColumns::COLUMNS.default_keys},
    per_page: {default: 50},
    filter: {schema: Fin::PaymentOrdersFilterSchema, presets: Fin::PaymentOrdersFilterSchema::PRESETS}

  # The Sammler table of an order's head: all, in their order, without the
  # order (it is the head's); a row opens into the Sammler's detail.
  PAYMENT_INFOS_POLICY = wsjrdp_expandable_table_policy prefix: "si",
    columns: Fin::DirectDebitPaymentInfosColumns::COLUMNS.codec,
    cols: {default: Fin::DirectDebitPaymentInfosColumns::COLUMNS.default_keys - %w[order], exclude: %w[order]},
    per_page: {default: :all}

  helper_method :payment_orders, :payment_order_totals, :payment_order_infos_rows, :payment_order_sub_infos

  def index
  end

  # The order's page; inside the list's row (a turbo frame) its head and
  # Sammler.
  def show
    @order = Fin::PaymentQueries.orders.find(params[:id])
    @infos = Fin::PaymentQueries.payment_infos(@order.id).to_a
    @ctx = detail_format_context
  end

  # Apply target of the filter builder (PRG, Wsjrdp::TableStateful). The page
  # resets to 1.
  def apply
    wsjrdp_apply_table_filter(table_state, redirect_to: payment_orders_path)
  end

  private

  def authorize_action
    authorize!(:show, WsjrdpFinAccount)
  end

  def table_state = wsjrdp_expandable_table_state(POLICY)

  # The record's own page, or a list row's detail (a turbo frame) at the
  # nesting level the list put into the frame's URL (doc/fin/detail_partials.md).
  def detail_format_context
    return Fin::AttrFormatContext.regular unless turbo_frame_request?

    Fin::AttrFormatContext.embedded(Wsjrdp::TableContext.new(level: table_state.level, lazy: true))
  end

  def filtered_orders
    @filtered_orders ||= table_state.filter.scope(Fin::PaymentQueries.orders)
  end

  def payment_orders
    @payment_orders ||= Wsjrdp::ExpandableTableRows.new(table_state, filtered_orders,
      sort: Fin::PaymentOrdersColumns::COLUMNS.sort_expressions, tiebreaker: TIEBREAKER)
  end

  def payment_order_totals
    @payment_order_totals ||= Fin::PaymentQueries.order_totals(filtered_orders)
  end

  # The Sammler of the orders on the page that have several, by order id:
  # their sub-rows in the list.
  def payment_order_sub_infos
    @payment_order_sub_infos ||= begin
      ids = payment_orders.page.select { |order| order.info_count.to_i > 1 }.map(&:id)
      ids.any? ? Fin::PaymentQueries.payment_infos(ids).group_by(&:payment_initiation_id) : {}
    end
  end

  # The Einzüge section (Fin::DirectDebitsSection): the order's debits, for a
  # direct debit only.
  def section_debits_scope = Fin::PaymentQueries.debits.where(payment_initiation_id: @order.id)

  def section_debits? = @order.direct_debit? && super

  def section_path = payment_order_path(params[:id])

  def payment_order_infos_rows(infos)
    order = infos.each_with_index.to_h
    Wsjrdp::ExpandableTableRows.new(wsjrdp_expandable_table_state(PAYMENT_INFOS_POLICY), infos,
      sort: {}, tiebreaker: ->(info) { order[info] })
  end
end
