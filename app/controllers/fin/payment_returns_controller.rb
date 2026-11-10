# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Rückläufer" tab of the Zahlungsverkehr area at /fin/payments/returns, in
# two sections. "Rücklastschriften": every return of one of our direct debits
# -- a bank transaction, the accounting entry booked for it beside it --, with
# its debit (by end-to-end id, else by mandate reference) and that debit's
# order; one that finds no debit and names no order itself is "not
# assignable". "Weitere Rückläufer": every other payment that came back (a
# returned credit transfer, ...), by what came back
# (WsjrdpCamtTransaction#return_kind); its row leads to the bank
# transaction. A return's page -- of either kind --
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

  # The other returns: few, so all on one page.
  OTHER_POLICY = wsjrdp_expandable_table_policy prefix: "or",
    columns: Fin::OtherReturnsColumns::COLUMNS.codec,
    sort: {hidden: [["date", "desc"]]},
    cols: {default: Fin::OtherReturnsColumns::COLUMNS.default_keys},
    per_page: {default: :all}

  # The candidates for the original of another return (Fin::ReturnOriginals):
  # few, so all on one page, the best first.
  ORIGINALS_POLICY = wsjrdp_expandable_table_policy prefix: "oc",
    columns: Fin::ReturnOriginalColumns::COLUMNS.codec,
    sort: {hidden: [["score", "desc"]]},
    cols: {default: Fin::ReturnOriginalColumns::COLUMNS.default_keys},
    per_page: {default: :all}

  helper_method :payment_returns, :payment_return_totals, :other_returns, :original_candidates

  def index
  end

  def show
    @return = find_return
    @ctx = detail_format_context
  end

  # The edit page: the return's status and comment (Fin::ReturnEditing).
  def edit
    @return = find_return
    authorize!(:update, @return)
    @ctx = Fin::AttrFormatContext.regular
  end

  # Saves the status and comment and -- for another return -- its original
  # (Fin::ReturnOriginals): the chosen candidate, or the id typed beside the
  # candidates; none unlinks. A bank transaction that is no candidate saves
  # nothing.
  def update
    @return = find_return
    authorize!(:update, @return)
    original = chosen_original
    if original == :refused
      flash.now[:alert] = t("fin.payments.original_not_candidate")
      return render_edit
    end

    saved = WsjrdpCamtTransaction.transaction do
      @return.update(Fin::ReturnEditing.permitted(params.require(:wsjrdp_camt_transaction))) or raise ActiveRecord::Rollback
      save_original(original) unless original == :unchanged
      true
    end
    return render_edit unless saved

    # A list row's inline edit comes back to the row (its frame).
    target = (params[:stay].present? && !turbo_frame_request?) ? edit_payment_return_path(@return) : payment_return_path(@return)
    redirect_to target, notice: t("fin.payments.return_saved", id: @return.id)
  end

  def apply
    wsjrdp_apply_table_filter(table_state, redirect_to: payment_returns_path)
  end

  private

  def authorize_action
    authorize!(:log, WsjrdpFinAccount)
  end

  def table_state = wsjrdp_expandable_table_state(POLICY)

  def original_candidates
    @original_candidates ||= Wsjrdp::ExpandableTableRows.new(wsjrdp_expandable_table_state(ORIGINALS_POLICY),
      Fin::ReturnOriginals.candidates(@return),
      sort: Fin::ReturnOriginalColumns::COLUMNS.sort_expressions, tiebreaker: ->(c) { -c.id })
  end

  # The edit page again, with what was typed; a save that failed its
  # validation says why.
  def render_edit
    flash.now[:alert] ||= validation_alert(@return) if @return.errors.any?
    @ctx = Fin::AttrFormatContext.regular
    render :edit, status: :unprocessable_entity
  end

  # The original the form asks for: a bank transaction, nil for none,
  # :unchanged where the form has no choice (a returned direct debit), and
  # :refused for one that is no candidate.
  def chosen_original
    choice = params[:original_id_other].presence || params.dig(:wsjrdp_camt_transaction, :reverses_id)
    return :unchanged if @return.return_kind == "direct_debit" || choice.nil?
    return nil if choice.blank?

    original = WsjrdpCamtTransaction.find_by(id: choice.to_s.delete("#").strip)
    (original && Fin::ReturnOriginals.candidate?(@return, original)) ? original : :refused
  end

  def save_original(original)
    return if original&.id == @return.reverses_id

    original ? Fin::ReturnOriginals.link!(@return, original) : Fin::ReturnOriginals.unlink!(@return)
  end

  # A return of our direct debits, else any other return.
  def find_return
    Fin::PaymentQueries.returns.find_by(id: params[:id]) || Fin::PaymentQueries.other_returns.find(params[:id])
  end

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

  def other_returns
    @other_returns ||= Wsjrdp::ExpandableTableRows.new(wsjrdp_expandable_table_state(OTHER_POLICY),
      Fin::PaymentQueries.other_returns,
      sort: Fin::OtherReturnsColumns::COLUMNS.sort_expressions, tiebreaker: TIEBREAKER)
  end
end
