# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class Fin::MossBalanceMovementsController < Fin::FinController
  include WsjrdpFormHelper
  include WsjrdpFinHelper
  include SubjectLinking

  prepend_before_action :map_id_to_moss_balance_movement_id
  before_action :authorize_action

  helper_method :can_fin_admin?
  helper_method :moss_balance_movement
  helper_method :permitted_attrs
  helper_method :cancel_url, :return_url
  helper_method :moss_balance_movement_path
  helper_method :matching_accounting_entries

  def show
    @moss_balance_movement ||= moss_balance_movement
    render :show
  end

  def update
    @moss_balance_movement ||= moss_balance_movement
    authorize!(:update, moss_balance_movement)
    moss_balance_movement.attributes = permitted_params
    if moss_balance_movement.save
      flash[:notice] = "Transaktion #{moss_balance_movement.id} erfolgreich aktualisiert."
      redirect_to return_url
    else
      render :show, status: :bad_request
    end
  end

  def create_accounting_entry
    authorize!(:update, moss_balance_movement)
    tx = moss_balance_movement
    subject = tx.subject
    authorize!(:update, subject)
    entry = AccountingEntry.create!(
      subject: subject,
      author: current_user,
      amount_cents: tx.amount_cents,
      amount_currency: tx.amount_currency,
      description: tx.payment_reference,
      comment: tx.comment,
      value_date: tx.value_date,
      booking_date: tx.booking_date,
      dbtr_name: tx.fin_account.owner_name,
      dbtr_address: tx.fin_account.owner_address,
      # cdtr_name:
      cdtr_iban: tx.recipient_account_number,
      cdtr_bic: tx.recipient_bank_code,
      moss_balance_movement_id: tx.id
    )
    tx.accounting_entry_id = entry.id
    tx.save!
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.action(:refresh, "") }
      format.html { redirect_to tx.fin_account }
    end
  end

  def link_accounting_entry
    authorize!(:update, moss_balance_movement)
    tx = moss_balance_movement
    subject = tx.subject
    authorize!(:update, subject)
    accounting_entry = AccountingEntry.find(params[:accounting_entry_id])
    accounting_entry.balance_movement_id = tx.id
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
    moss_balance_movement
  end

  def map_id_to_moss_balance_movement_id
    params[:moss_balance_movement_id] = params[:id] unless params.key?(:moss_balance_movement_id)
  end

  def authorize_action
    authorize!(:show, moss_balance_movement)
  end

  def moss_balance_movement
    @moss_balance_movement ||= MossBalanceMovement.find(params[:moss_balance_movement_id])
  end

  def moss_balance_movement_path(entry = nil)
    url_for(entry.nil? ? moss_balance_movement : entry)
  end

  def return_url
    return_url_or_fallback url_for(moss_balance_movement)
  end

  def cancel_url
    return_url
  end

  def can_fin_admin?
    can?(:fin_admin, moss_balance_movement) && param_is_true(cookies, :fin_admin)
  end

  def matching_accounting_entries
    @matching_accounting_entries ||= moss_balance_movement.accounting_entries_for_subject.select { |e|
      e.amount_cents == moss_balance_movement.amount_cents
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
    params.require(:moss_balance_movement)
  end

  def permitted_attrs
    [
      :comment,
      :subject, :subject_id, :subject_type,
      :accounting_entry, :accounting_entry_id
    ]
  end

  def permitted_params
    _transform_tx_params(model_params.permit(permitted_attrs))
  end
end
