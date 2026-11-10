# frozen_string_literal: true

#  Copyright (c) 2025, 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The page of one CAMT bank transaction.
#
# Another page may send the reader here with `return_url`
# (Fin::ReturnPath): the reading page then leads back there, the edit
# page keeps it, and a save returns to it.
#
# The reading page is also what an expandable table lazy-loads into a
# row (a turbo frame): it then answers as that frame, with the detail
# in its embedded mode, and a save comes back to the row.
class Fin::WsjrdpCamtTransactionsController < Fin::FinController
  include WsjrdpFormHelper
  include SubjectLinking
  include Fin::ReturnPath

  # The prefix of the frame a direct visit gets (wsjrdp_detail_frame); a table
  # that embeds the detail asks under its own.
  FRAME_PREFIX = "tx"

  before_action :map_id_to_wsjrdp_camt_transaction_id
  before_action :authorize_action

  helper_method :camt_transaction
  helper_method :permitted_attrs
  helper_method :camt_transaction_return_url
  helper_method :camt_transaction_path
  helper_method :matching_accounting_entries

  def show
    @wsjrdp_camt_transaction ||= camt_transaction
    @ctx = detail_format_context
    render :show
  end

  def edit
    @wsjrdp_camt_transaction ||= camt_transaction
    authorize!(:update, camt_transaction)
    @ctx = Fin::AttrFormatContext.regular
  end

  def update
    @wsjrdp_camt_transaction ||= camt_transaction
    authorize!(:update, camt_transaction)
    camt_transaction.attributes = permitted_params
    if save_transaction
      redirect_to after_save_path, notice: "Kontobewegung #{camt_transaction.id} erfolgreich aktualisiert."
    else
      flash.now[:alert] = validation_alert(camt_transaction)
      render_after_failed_save
    end
  end

  def create_accounting_entry
    authorize!(:update, camt_transaction)
    tx = camt_transaction
    subject = tx.subject
    authorize!(:update, subject)
    entry = AccountingEntry.create!(
      subject: subject,
      author: current_user,
      # AccountingEntry keeps integer cents; camt now stores numeric EUR.
      amount_cents: (tx.signed_base_amount * 100).round,
      amount_currency: tx.base_currency,
      description: tx.description,
      comment: tx.comment,
      value_date: tx.value_date,
      booking_date: tx.booking_date,
      mandate_id: tx.mandate_id,
      endtoend_id: tx.endtoend_id,
      cdtr_name: tx.cdtr_name,
      cdtr_iban: tx.cdtr_iban,
      cdtr_bic: tx.cdtr_bic,
      cdtr_address: tx.cdtr_address,
      dbtr_name: tx.dbtr_name,
      dbtr_iban: tx.dbtr_iban,
      dbtr_bic: tx.dbtr_bic,
      dbtr_address: tx.dbtr_address,
      return_reason: tx.return_reason,
      camt_transaction_id: tx.id
    )
    tx.accounting_entry_id = entry.id
    tx.save!
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.action(:refresh, "") }
      format.html { redirect_to tx.fin_account }
    end
  end

  def link_accounting_entry
    authorize!(:update, camt_transaction)
    tx = camt_transaction
    subject = tx.subject
    authorize!(:update, subject)
    accounting_entry = AccountingEntry.find(params[:accounting_entry_id])
    accounting_entry.camt_transaction_id = tx.id
    tx.accounting_entry_id = accounting_entry.id
    tx.save!
    accounting_entry.save!
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.action(:refresh, "") }
      format.html { redirect_to tx.fin_account }
    end
  end

  private

  def entry
    camt_transaction
  end

  def map_id_to_wsjrdp_camt_transaction_id
    params[:wsjrdp_camt_transaction_id] = params[:id] unless params.key?(:wsjrdp_camt_transaction_id)
  end

  def authorize_action
    authorize!(:show, camt_transaction)
  end

  def camt_transaction
    @camt_transaction ||= WsjrdpCamtTransaction.find(params[:wsjrdp_camt_transaction_id])
  end

  def camt_transaction_path(entry = nil)
    url_for(entry.nil? ? camt_transaction : entry)
  end

  # The record's own page, or a table row's detail (a turbo frame) at the
  # nesting level the table put into the frame's URL -- the shared
  # `expandable_table_level` param, read here directly because this controller
  # has no table of its own to resolve it (doc/fin/detail_partials.md §1).
  def detail_format_context
    return Fin::AttrFormatContext.regular unless turbo_frame_request?

    Fin::AttrFormatContext.embedded(Wsjrdp::TableContext.new(level: params[:expandable_table_level], lazy: true))
  end

  # Saves unless a person was typed but not chosen from the suggestions: the
  # search field then carries a name and no id, and saving would silently link
  # nobody.
  def save_transaction
    return camt_transaction.save unless subject_typed_but_not_chosen?

    camt_transaction.valid?
    camt_transaction.errors.add(:subject, "muss aus der Vorschlagsliste gewählt werden")
    false
  end

  def subject_typed_but_not_chosen?
    model_params[:subject].present? && model_params[:subject_id].blank?
  end

  def after_save_path
    return wsjrdp_camt_transaction_path(camt_transaction) if turbo_frame_request?
    return edit_wsjrdp_camt_transaction_path(camt_transaction, return_url: return_path) if params[:stay].present?

    return_path || wsjrdp_camt_transaction_path(camt_transaction)
  end

  # A row's inline edit shows its pane again (its form opens by itself on a
  # record with errors), a page the edit page.
  def render_after_failed_save
    if turbo_frame_request?
      @ctx = detail_format_context
      render :show, status: :unprocessable_entity
    else
      @ctx = Fin::AttrFormatContext.regular
      render :edit, status: :unprocessable_entity
    end
  end

  def camt_transaction_return_url(entry = nil)
    params[:return_url].presence || camt_transaction_path(entry)
  end

  def matching_accounting_entries
    camt_cents = (camt_transaction.signed_base_amount * 100).round
    @matching_accounting_entries ||= camt_transaction.accounting_entries_for_subject.select { |e|
      e.amount_cents == camt_cents
    }
  end

  # The person as the search field sends it: the name (`subject`) and the id
  # of the chosen one. An emptied field unlinks; a request that does not carry
  # the field at all leaves the person alone.
  def _transform_tx_params(params)
    return params unless params.key?(:subject) || params.key?(:subject_id)

    if params[:subject].blank? || params[:subject_id].blank?
      params[:subject_id] = nil
      params[:subject_type] = nil
    elsif params[:subject_type].blank?
      params[:subject_type] = "Person"
    end
    params.except(:subject)
  end

  def model_params
    params.require(:wsjrdp_camt_transaction)
  end

  def permitted_attrs
    return [] unless can?(:update, camt_transaction)

    # Comment and return status are the return's fields (Fin::ReturnEditing,
    # shared with the return's own page); the person is this page's.
    [
      *Fin::ReturnEditing::FIELDS.keys,
      :subject, :subject_id, :subject_type,
      :accounting_entry, :accounting_entry_id
    ]
  end

  def permitted_params
    _transform_tx_params(model_params.permit(permitted_attrs))
  end
end
