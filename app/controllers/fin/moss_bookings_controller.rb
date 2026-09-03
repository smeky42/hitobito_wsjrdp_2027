# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class Fin::MossBookingsController < Fin::FinController
  include WsjrdpFormHelper
  include Fin::AccessHelper
  include SubjectLinking

  prepend_before_action :map_id_to_moss_booking_id
  before_action :authorize_action

  helper_method :can_fin_admin?
  helper_method :moss_booking
  helper_method :permitted_attrs
  helper_method :cancel_url, :return_url
  helper_method :moss_booking_path
  helper_method :matching_accounting_entries

  def show
    @moss_booking ||= moss_booking
    render :show
  end

  def update
    @moss_booking ||= moss_booking
    authorize!(:update, moss_booking)
    moss_booking.attributes = permitted_params
    if moss_booking.save
      flash[:notice] = "Moss Buchung #{moss_booking.id} erfolgreich aktualisiert."
      redirect_to return_url
    else
      render :show, status: :bad_request
    end
  end

  def create_accounting_entry
    authorize!(:update, moss_booking)
    tx = moss_booking
    subject = tx.contribution_subject
    authorize!(:update, subject)
    entry = AccountingEntry.create!(
      subject: subject,
      author: current_user,
      amount_cents: tx.amount_cents,
      amount_currency: tx.currency,
      description: tx.description,
      comment: tx.comment,
      value_date: tx.value_date,
      booking_date: tx.moss_transaction.booking_date,
      dbtr_name: tx.moss_transaction.fin_account&.owner_name,
      dbtr_address: tx.moss_transaction.fin_account&.owner_address,
      # cdtr_name:
      cdtr_iban: tx.moss_transaction.recipient_iban,
      cdtr_bic: tx.moss_transaction.recipient_bic,
      moss_booking_id: tx.id
    )
    tx.accounting_entry_id = entry.id
    tx.save!
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.action(:refresh, "") }
      format.html { redirect_to tx.moss_transaction.fin_account }
    end
  end

  def link_accounting_entry
    authorize!(:update, moss_booking)
    tx = moss_booking
    subject = tx.contribution_subject
    authorize!(:update, subject)
    accounting_entry = AccountingEntry.find(params[:accounting_entry_id])
    accounting_entry.moss_booking_id = tx.id
    tx.accounting_entry_id = accounting_entry.id
    tx.save!
    accounting_entry.save!
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.action(:refresh, "") }
      format.html { redirect_to tx.moss_transaction.fin_account }
    end
  end

  private

  def entry
    moss_booking
  end

  def map_id_to_moss_booking_id
    params[:moss_booking_id] = params[:id] unless params.key?(:moss_booking_id)
  end

  def authorize_action
    authorize!(:show, moss_booking)
  end

  def moss_booking
    @moss_booking ||= MossBooking.find(params[:moss_booking_id])
  end

  def moss_booking_path(entry = nil)
    url_for(entry.nil? ? moss_booking : entry)
  end

  def return_url
    return_url_or_fallback url_for(moss_booking)
  end

  def cancel_url
    return_url
  end

  def can_fin_admin?
    can?(:fin_admin, moss_booking) && param_is_true(cookies, :fin_admin)
  end

  def matching_accounting_entries
    @matching_accounting_entries ||= moss_booking.accounting_entries_for_subject.select { |e|
      e.amount_cents == moss_booking.amount_cents
    }
  end

  def _transform_tx_params(params)
    if params[:contribution_subject].blank? || params[:contribution_subject_id].blank?
      params[:contribution_subject_id] = nil
      params[:contribution_subject_type] = nil
    elsif params[:contribution_subject_type].blank?
      params[:contribution_subject_type] = "Person"
    end
    params.except(:contribution_subject)
  end

  def model_params
    params.require(:moss_booking)
  end

  def permitted_attrs
    [
      :comment,
      :contribution_subject, :contribution_subject_id, :contribution_subject_type,
      :accounting_entry, :accounting_entry_id
    ]
  end

  def permitted_params
    _transform_tx_params(model_params.permit(permitted_attrs))
  end
end
