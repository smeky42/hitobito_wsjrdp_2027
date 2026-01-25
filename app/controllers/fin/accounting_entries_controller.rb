# frozen_string_literal: true

class Fin::AccountingEntriesController < ApplicationController
  include WsjrdpFormHelper
  include WsjrdpFinHelper
  include FormatHelper
  include UtilityHelper
  include ::ActionView::Helpers::TagHelper

  before_action :authorize_action
  decorates :group, :person

  helper_method :entry

  helper_method :accounting_entry
  helper_method :can_fin?
  helper_method :can_fin_admin?
  helper_method :get_accounting_entry_path
  helper_method :person
  helper_method :permitted_attrs
  helper_method :cancel_url, :return_url
  helper_method :target_turbo_frame

  def entry
    @accounting_entry
  end

  def index
    authorize!(:show, AccountingEntry)
    @accounting_entries = AccountingEntry.limit(20).order(id: "desc")
  end

  def new
    authorize!(:create, AccountingEntry)
    attrs = {amount_currency: "EUR", additional_info: {}}
    attrs.update(permitted_params)
    @accounting_entry = AccountingEntry.new(attrs)
  end

  def new_sepa_status
    authorize!(:create, AccountingEntry)
    attrs = {amount_eur: 0, amount_currency: "EUR", additional_info: {}}
    attrs.update(permitted_params)
    @accounting_entry = AccountingEntry.new(attrs)
    @accounting_entry.author = current_user
    if request.post?
      save_new_sepa_status
    end
  end

  def create
    authorize!(:create, AccountingEntry)
    @accounting_entry = AccountingEntry.new(permitted_params)
    @accounting_entry.author = current_user
    if @accounting_entry.save
      notice = "Neue Buchung in Höhe von #{@accounting_entry.amount_eur_display} € erfolgreich angelegt."
      flash.now[:notice] = notice
      flash.keep
      respond_to do |format|
        format.html { redirect_back_or_to accounting_entries_path }
        format.turbo_stream { render turbo_stream: turbo_stream.action(:location_reload, "") }
      end
    else
      render :new, status: :bad_request
    end
  end

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
    redirect_to return_url
  end

  def destroy
    @accounting_entry ||= accounting_entry
    authorize!(:destroy, @accounting_entry)
    raise "Missing fin_admin to destroy accounting_entry" unless can_fin_admin?
    @accounting_entry.destroy!
    redirect_to "#{accounting_group_person_path(group, person)}?fin_admin=1"
  end

  def permitted_attrs
    if can?(:fin_admin, AccountingEntry)
      if action_name == "new_sepa_status"
        [
          :amount_cents, :amount_eur,
          :subject_type, :subject_id,
          :description, :comment,
          :new_sepa_status,
          :booking_date, :value_date
        ]
      else
        [
          :amount_cents, :amount_eur,
          :pre_notified_amount_cents, :pre_notified_amount_eur,
          :subject_type, :subject_id,
          :description, :comment,
          :new_sepa_status,
          :booking_date, :value_date,
          :endtoend_id,
          :dbtr_name, :dbtr_iban, :dbtr_bic, :dbtr_address,
          :cdtr_name, :cdtr_iban, :cdtr_bic, :cdtr_address,
          :mandate_id, :mandate_date, :debit_sequence_type
        ]
      end
    else
      [:comment]
    end
  end

  def model_params
    params.require(:accounting_entry)
  end

  def permitted_params
    model_params.permit(permitted_attrs)
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
    authorize!(:show, AccountingEntry)
  end

  def can_fin?
    can?(:show, AccountingEntry) && !param_is_false(params, :can_fin)
  end

  def can_fin_admin?
    can?(:fin_admin, AccountingEntry) && param_is_true(params, :fin_admin)
  end

  private

  def save_new_sepa_status
    subject = @accounting_entry.subject
    new_sepa_status = @accounting_entry.new_sepa_status
    if new_sepa_status != subject.sepa_status
      new_sepa_status_msg = "Finanzstatus auf #{Settings.sepa_status[new_sepa_status]} gesetzt"
      @accounting_entry.description = new_sepa_status_msg if @accounting_entry.description.blank?
      ActiveRecord::Base.transaction do
        @accounting_entry.save!
        subject.sepa_status = new_sepa_status
        subject.save!
      end
      if new_sepa_status == "ok"
        flash.now[:notice] = new_sepa_status_msg
      else
        flash.now[:warning] = new_sepa_status_msg
      end
    else
      flash.now[:notice] = "Finanzstatus bleibt #{Settings.sepa_status[new_sepa_status]}"
    end
    flash.keep
    respond_to do |format|
      format.html { redirect_back_or_to accounting_entries_path }
      format.turbo_stream { render turbo_stream: turbo_stream.action(:location_reload, "") }
    end
  rescue ActiveRecord::RecordInvalid
    render :new_sepa_status, status: :bad_request
  end

  def safe_join(array, sep = $OUTPUT_FIELD_SEPARATOR, &block)
    if block
      array = array.collect(&block).compact
    end
    super(array, sep)
  end

  def get_accounting_entry_path(entry = nil)
    accounting_entry_path(entry.nil? ? accounting_entry : entry)
  end

  def return_url
    return_url_or_fallback url_for(accounting_entry)
  end

  def cancel_url
    return_url
  end

  def target_turbo_frame
    params[:target_turbo_frame] || :new_accounting_entry_frame
  end
end
