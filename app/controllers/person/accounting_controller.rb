# frozen_string_literal: true

class Person::AccountingController < ApplicationController
  include ContractHelper

  before_action :authorize_action
  decorates :group, :person

  helper_method :get_entry_path
  helper_method :can_accounting?
  helper_method :get_installments_table_entries
  helper_method :permitted_attrs

  def index
    @person ||= person
    @group ||= group

    @accounting_entries = accounting_entries
    @direct_debit_pre_notifications = direct_debit_pre_notifications
    @new_accounting_entry = new_accounting_entry(params)

    render :index
  end

  def create
    @person ||= person
    @group ||= group

    unless can_accounting?
      redirect_back_or_to(accounting_group_person_path,
        alert: "Du darfst keine Buchungen anlegen!")
      return
    end

    @alerts = []
    @warnings = []
    @notices = []
    @new_accounting_entry = new_accounting_entry(params)
    @accounting_entries = accounting_entries

    unless @new_accounting_entry.save
      # Errors in @new_accounting_entry.errors are automatically shown
      # as part of the form and do not need to be put into the flash.
      flash.now[:alert] = @alerts.join("\n")
      flash.now[:notice] = @notices.join("\n")
      flash.now[:warning] = @warnings.join("\n")
      render :index, status: :bad_request
      return
    end

    @notices << "Neue Buchung in Höhe von #{@new_accounting_entry.amount_eur_display} € erfolgreich angelegt."

    new_sepa_status = @new_accounting_entry.new_sepa_status
    if new_sepa_status != @person.sepa_status
      @person.sepa_status = new_sepa_status
      new_sepa_status_msg = "Finanzstatus auf #{Settings.sepa_status[new_sepa_status]} gesetzt."
      if new_sepa_status == "ok"
        @notices << new_sepa_status_msg
      else
        @warnings << new_sepa_status_msg
      end
      unless @person.save
        @warnings.concat @person.errors.full_messages.map { |p| "Person: #{p}" }
      end
    end

    flash[:alert] = @alerts.join("\n")
    flash[:notice] = @notices.join("\n")
    flash[:warning] = @warnings.join("\n")
    redirect_back_or_to(accounting_group_person_path)
  end

  def permitted_attrs
    [
      :amount_eur,
      :amount_cents,
      :amount_currency,
      :description,
      :comment,
      :endtoend_id,
      :new_sepa_status,
      :value_date,
      :dbtr_name,
      :dbtr_iban,
      :dbtr_bic,
      :dbtr_address,
      :cdtr_name,
      :cdtr_iban,
      :cdtr_bic,
      :cdtr_address,
      :mandate_id,
      :mandate_date,
      :debit_sequence_type
    ]
  end

  def new_accounting_entry(params)
    if params[:accounting_entry].blank?
      entry = AccountingEntry.new(
        subject: @person,
        author: current_user,
        amount_currency: "EUR",
        new_sepa_status: @person.sepa_status,
        additional_info: {}
      )
    else
      acc_entry_params = params[:accounting_entry].permit(permitted_attrs)
      entry = AccountingEntry.new(
        subject: @person,
        author: current_user,
        amount_currency: "EUR",
        additional_info: {},
        **acc_entry_params
      )
    end
    entry
  end

  private

  def person
    @person ||= Person.find(params[:id])
  end

  def group
    @group ||= person.primary_group
  end

  def get_entry_path(entry)
    if entry.class.name.demodulize == WsjrdpDirectDebitPreNotification.name.demodulize
      wsjrdp_direct_debit_pre_notification_path(entry)
    else
      accounting_entry_path(entry)
    end
  end

  def can_accounting?
    # For testing and to imitate output without accounting rights,
    # accounting rights can be disabled using the can_accounting query
    # parameter. Important: It is not possible to gain accounting
    # rights this way.
    if @can_accounting.nil?
      can_accounting_param = (params[:can_accounting] || "").downcase
      @can_accounting = if ["false", "0", "no"].any?(can_accounting_param)
        false
      else
        can?(:log, person)
      end
    end
    @can_accounting
  end

  def authorize_action
    authorize!(:edit, person)
  end

  def accounting_entries
    @accounting_entries ||= person.accounting_entries.sort_by { |e|
      e.value_date || e.created_at.to_date
    }.reverse
  end

  def direct_debit_pre_notifications
    shown_payment_status = %w[pre_notified skipped]
    @direct_debit_pre_notifications ||= person.direct_debit_pre_notifications.select { |pn|
      shown_payment_status.any?(pn.payment_status)
    }.sort_by { |e|
      e.collection_date || e.created_at.to_date
    }.reverse
  end

  def get_installments_table_entries
    installments = person.installments_cents
    total = 0
    entries = []
    installments.each do |item|
      cents = item[1]
      total += cents
      date = Date.new(item[0][0], item[0][1], 5)
      entries << {
        date: I18n.l(date, format: "%b %Y"),
        amount: format_cents_de(cents),
        total: format_cents_de(total)
      }
    end
    entries
  end
end
