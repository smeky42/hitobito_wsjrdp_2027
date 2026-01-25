# frozen_string_literal: true

#  Copyright (c) 2025. 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class Fin::WsjrdpCamtTransactionsController < ApplicationController
  include WsjrdpFormHelper
  include WsjrdpFinHelper

  before_action :map_id_to_wsjrdp_camt_transaction_id
  before_action :authorize_action

  helper_method :can_fin_admin?
  helper_method :camt_transaction
  helper_method :permitted_attrs
  helper_method :cancel_url, :return_url
  helper_method :camt_transaction_return_url
  helper_method :camt_transaction_path
  helper_method :matching_accounting_entries

  def show
    @wsjrdp_camt_transaction ||= camt_transaction
    render :show
  end

  def update
    @wsjrdp_camt_transaction ||= camt_transaction
    authorize!(:update, camt_transaction)
    camt_transaction.attributes = permitted_params
    if camt_transaction.save
      flash[:notice] = "Transaktion #{camt_transaction.id} erfolgreich aktualisiert."
      redirect_to return_url
    else
      render :show, status: :bad_request
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
      amount_cents: tx.amount_cents,
      amount_currency: tx.amount_currency,
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

  def return_url
    return_url_or_fallback url_for(camt_transaction)
  end

  def cancel_url
    return_url
  end

  def camt_transaction_return_url(entry = nil)
    params[:return_url].presence || camt_transaction_path(entry)
  end

  def can_fin_admin?
    @can_fin_admin = get_can_fin_admin(camt_transaction, params: params) if @can_fin_admin.nil?
    @can_fin_admin
  end

  def matching_accounting_entries
    @matching_accounting_entries ||= camt_transaction.accounting_entries_for_subject.select { |e|
      e.amount_cents == camt_transaction.amount_cents
    }
  end

  def _transform_tx_params(params)
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
    [
      :comment,
      :subject, :subject_id, :subject_type,
      :accounting_entry, :accounting_entry_id,
      :return_status
    ]
  end

  def permitted_params
    _transform_tx_params(model_params.permit(permitted_attrs))
  end
end
