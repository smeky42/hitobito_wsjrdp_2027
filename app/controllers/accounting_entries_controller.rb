# frozen_string_literal: true

class AccountingEntriesController < ApplicationController
  include WsjrdpFormHelper
  include WsjrdpFinHelper
  include FormatHelper
  include UtilityHelper
  include ::ActionView::Helpers::TagHelper

  before_action :authorize_action
  decorates :group, :person

  helper_method :accounting_entry
  helper_method :can_fin?
  helper_method :can_fin_admin?
  helper_method :get_accounting_entry_cancel_url
  helper_method :get_accounting_entry_path
  helper_method :get_accounting_entry_return_url
  helper_method :person
  helper_method :permitted_attrs

  def show
    @group ||= group
    @person ||= person
    @accounting_entry ||= accounting_entry
    @permitted_attrs ||= permitted_attrs
    render "person/accounting_entries/show"
  end

  def update
    @group ||= group
    @person ||= person
    authorize!(:log, person)
    @accounting_entry ||= accounting_entry
    @permitted_attrs ||= permitted_attrs

    unless params[:accounting_entry].blank?
      accounting_entry.attributes = params.require(:accounting_entry).permit(permitted_attrs)
      unless accounting_entry.save
        render "person/accounting_entries/show", status: :bad_request
        return
      end
    end
    redirect_to get_accounting_entry_return_url
  end

  def permitted_attrs
    if can_fin_admin?
      [
        :amount_cents, :amount_eur,
        # :pre_notified_amount_cents, :pre_notified_amount_eur,
        :description, :comment,
        :value_date, :endtoend_id,
        :dbtr_name, :dbtr_iban, :dbtr_bic, :dbtr_address,
        :cdtr_name, :cdtr_iban, :cdtr_bic, :cdtr_address,
        :mandate_id, :mandate_date, :debit_sequence_type
      ]
    else
      [:comment]
    end
  end

  def accounting_entry
    @accounting_entry ||= AccountingEntry.find(params[:id])
  end

  def person
    @person ||= accounting_entry.person
  end

  def group
    @group ||= accounting_entry.group
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

  def safe_join(array, sep = $OUTPUT_FIELD_SEPARATOR, &block)
    if block
      array = array.collect(&block).compact
    end
    super(array, sep)
  end

  def get_accounting_entry_path(entry = nil)
    accounting_entry_path(entry.nil? ? accounting_entry : entry)
  end

  def _url_host_allowed?(url)
    URI(url.to_s).host == request.host
  rescue ArgumentError, URI::Error
    false
  end

  def get_accounting_entry_cancel_url
    get_accounting_entry_return_url
  end

  def get_accounting_entry_return_url
    if params[:return_url].present?
      params[:return_url]
    elsif request.referer && _url_host_allowed?(request.referer)
      request.referer
    else
      "#{group_person_path(group, person)}/accounting"
    end
  end
end
