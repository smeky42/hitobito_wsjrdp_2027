# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Rückläufer" tab of the Zahlungsverkehr area at /fin/payments/returns:
# every return -- a bank transaction with a return reason, the accounting
# entry booked for it beside it --, with its debit (by end-to-end id, else by
# mandate reference) and that debit's order; one that finds no debit and names
# no order itself is "not assignable". A return's page
# (/fin/payments/returns/:id, the bank transaction's id) is also the row's
# lazy detail. Person-level
# payment data: :log on WsjrdpFinAccount. See doc/fin/payments.md.
class Fin::PaymentReturnsController < Fin::FinController
  include Wsjrdp::TableStateful

  before_action :authorize_action

  TIEBREAKER = "wsjrdp_camt_transactions.id DESC"

  POLICY = wsjrdp_expandable_table_policy prefix: "",
    columns: Fin::PaymentReturnsColumns::COLUMNS.codec,
    sort: {hidden: [["date", "desc"]]},
    cols: {default: Fin::PaymentReturnsColumns::COLUMNS.default_keys},
    per_page: {default: 50},
    filter: {schema: Fin::PaymentReturnsFilterSchema, presets: Fin::PaymentReturnsFilterSchema::PRESETS}

  helper_method :payment_returns, :payment_return_totals

  def index
  end

  def show
    @return = Fin::PaymentQueries.returns.find(params[:id])
    @ctx = detail_format_context
  end

  def apply
    wsjrdp_apply_table_filter(table_state, redirect_to: payment_returns_path)
  end

  private

  def authorize_action
    authorize!(:log, WsjrdpFinAccount)
  end

  def table_state = wsjrdp_expandable_table_state(POLICY)

  # The record's own page, or a list row's detail (a turbo frame) at the
  # nesting level the list put into the frame's URL (doc/fin/detail_partials.md).
  def detail_format_context
    return Fin::AttrFormatContext.regular unless turbo_frame_request?

    Fin::AttrFormatContext.embedded(Wsjrdp::TableContext.new(level: table_state.level, lazy: true))
  end

  def filtered_returns
    @filtered_returns ||= table_state.filter.scope(Fin::PaymentQueries.returns)
  end

  def payment_returns
    @payment_returns ||= Wsjrdp::ExpandableTableRows.new(table_state, filtered_returns,
      sort: Fin::PaymentReturnsColumns::COLUMNS.sort_expressions, tiebreaker: TIEBREAKER, preload: [{subject: [{roles: :group}, {roles_with_ended_readable: :group}, :groups_with_roles_ended_readable]}])
  end

  def payment_return_totals
    @payment_return_totals ||= Fin::PaymentQueries.return_totals(filtered_returns)
  end
end
