# frozen_string_literal: true

class WsjrdpDirectDebitPreNotificationsController < ApplicationController
  include WsjrdpFormHelper
  include WsjrdpFinHelper

  before_action :authorize_action
  # decorates :group, :person

  # helper_method :person, :group
  helper_method :can_fin?
  helper_method :can_fin_admin?
  helper_method :pre_notification
  helper_method :permitted_attrs
  helper_method :get_pre_notification_cancel_url, :get_pre_notification_return_url
  helper_method :get_pre_notification_path

  def show
    @person ||= person
    @group ||= group
    @wsjrdp_direct_debit_pre_notification ||= pre_notification
    render "direct_debit_pre_notifications/show"
  end

  def update
    @group ||= group
    @person ||= person
    @wsjrdp_direct_debit_pre_notification ||= pre_notification
    @permitted_attrs ||= permitted_attrs
    @pre_notification = pre_notification

    authorize!(:log, person)

    unless params[:wsjrdp_direct_debit_pre_notification].blank?
      pre_notification.attributes = params.require(:wsjrdp_direct_debit_pre_notification).permit(permitted_attrs)
      unless pre_notification.save
        render "direct_debit_pre_notifications/show", status: :bad_request
        return
      end
    end
    redirect_to get_pre_notification_return_url
  end

  def pre_notification
    @pre_notification ||= WsjrdpDirectDebitPreNotification.find(params[:id])
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

  def _url_host_allowed?(url)
    URI(url.to_s).host == request.host
  rescue ArgumentError, URI::Error
    false
  end

  def get_pre_notification_path(entry = nil)
    wsjrdp_direct_debit_pre_notification_path(entry.nil? ? pre_notification : entry)
  end

  def get_pre_notification_cancel_url
    get_pre_notification_return_url
  end

  def get_pre_notification_return_url
    if params[:return_url].present?
      params[:return_url]
    elsif request.referer && _url_host_allowed?(request.referer)
      request.referer
    else
      "#{group_person_path(group, person)}/accounting"
    end
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
end
