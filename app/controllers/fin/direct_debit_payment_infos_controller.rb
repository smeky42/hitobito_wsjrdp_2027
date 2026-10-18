# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Sammler" tab of the Zahlungsverkehr area at /fin/direct_debit_payment_infos:
# every direct debit payment info (a Sammler: one collection date and sequence
# type of a direct debit order) with the returns of its debits. A Sammler's
# page (/fin/direct_debit_payment_infos/:id) shows its head, its creditor and
# -- with :log on WsjrdpFinAccount -- its debits (Fin::DirectDebitsSection).
# The list names nobody, so whoever sees the accounts sees it. See
# doc/fin/payments.md.
class Fin::DirectDebitPaymentInfosController < Fin::FinController
  include Wsjrdp::TableStateful
  include Fin::DirectDebitsSection

  before_action :authorize_action

  TIEBREAKER = "wsjrdp_direct_debit_payment_infos.id DESC"

  POLICY = wsjrdp_expandable_table_policy prefix: "",
    columns: Fin::DirectDebitPaymentInfosColumns::COLUMNS.codec,
    sort: {hidden: [["collection_date", "desc"], ["sequence", "asc"]]},
    cols: {default: Fin::DirectDebitPaymentInfosColumns::COLUMNS.default_keys},
    per_page: {default: 50},
    filter: {schema: Fin::DirectDebitPaymentInfosFilterSchema,
             presets: Fin::DirectDebitPaymentInfosFilterSchema::PRESETS}

  helper_method :payment_infos, :payment_info_totals

  def index
  end

  def show
    @info = Fin::PaymentQueries.payment_info(params[:id])
    @ctx = detail_format_context
  end

  def apply
    wsjrdp_apply_table_filter(table_state, redirect_to: direct_debit_payment_infos_path)
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

  def filtered_payment_infos
    @filtered_payment_infos ||= table_state.filter.scope(Fin::PaymentQueries.payment_infos.reorder(nil))
  end

  def payment_infos
    @payment_infos ||= Wsjrdp::ExpandableTableRows.new(table_state, filtered_payment_infos,
      sort: Fin::DirectDebitPaymentInfosColumns::COLUMNS.sort_expressions, tiebreaker: TIEBREAKER)
  end

  def payment_info_totals
    @payment_info_totals ||= Fin::PaymentQueries.payment_info_totals(filtered_payment_infos)
  end

  # The Einzüge section (Fin::DirectDebitsSection): the Sammler's debits.
  def section_debits_scope = Fin::PaymentQueries.payment_info_debits(@info)

  def section_path = direct_debit_payment_info_path(params[:id])
end
