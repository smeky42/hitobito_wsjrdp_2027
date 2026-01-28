# frozen_string_literal: true

#  Copyright (c) 2025, 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class Fin::WsjrdpDirectDebitPreNotificationsController < ApplicationController
  include WsjrdpFormHelper
  include WsjrdpFinHelper

  before_action :authorize_action

  helper_method :can_fin?
  helper_method :can_fin_admin?
  helper_method :pre_notification
  helper_method :permitted_attrs
  helper_method :cancel_url, :return_url
  helper_method :get_pre_notification_path

  def show
    @wsjrdp_direct_debit_pre_notification = pre_notification
    @person = person
    @group = group
    render :show
  end

  def update
    @wsjrdp_direct_debit_pre_notification = pre_notification
    @person = person
    @group = group
    authorize!(:log, person)
    pre_notification.attributes = permitted_params

    if pre_notification.save
      redirect_to return_url
    else
      render :show, status: :bad_request
    end
  end

  def pre_notification
    @wsjrdp_direct_debit_pre_notification ||= WsjrdpDirectDebitPreNotification.find(params[:id])
  end

  def person
    @person ||= pre_notification.person
  end

  def group
    @group ||= pre_notification.group
  end

  def authorize_action
    authorize!(:log, person)
  end

  def can_fin?
    @can_fin = get_can_fin(person, params: params) if @can_fin.nil?
    @can_fin
  end

  def can_fin_admin?
    @can_fin_admin = get_can_fin_admin(person, params: params) if @can_fin_admin.nil?
    @can_fin_admin
  end

  private

  def get_pre_notification_path(entry = nil)
    wsjrdp_direct_debit_pre_notification_path(entry.nil? ? pre_notification : entry)
  end

  def return_url
    return_url_or_fallback url_for(pre_notification)
  end

  def cancel_url
    return_url
  end

  def model_params
    params.require(:wsjrdp_direct_debit_pre_notification)
  end

  def permitted_attrs
    if pre_notification.payment_status == "pre_notified"
      [
        :try_skip,
        # :payment_status,  # forbidden to not screw up states
        :dbtr_name, :dbtr_iban, :dbtr_bic, :dbtr_address,
        :amount_cents, :amount_eur,
        # :debit_sequence_type,  # in PmtInf
        # :collection_date,  # in PmtInf
        # :mandate_id  # constant for the whole jamboree
        :mandate_date,  # allow writing in case a new mandate was issued
        :description,
        :comment,
        :endtoend_id,
        # :cdtr_name, :cdtr_iban, :cdtr_bic, :cdtr_address,  # in PmtInf
        # :creditor_id,  # in GrpHdr
        :payment_role
      ]
    else
      [:comment]
    end
  end

  def permitted_params
    model_params.permit(permitted_attrs)
  end
end
