# frozen_string_literal: true

class Person::AccountingController < ApplicationController
  include ContractHelper
  include ActionView::Helpers::NumberHelper

  before_action :authorize_action
  decorates :group, :person

  helper_method :get_accounting_entry_path
  helper_method :can_accounting?
  helper_method :format_cents_de
  helper_method :get_accounting_payment_array
  helper_method :sum_entries_amount_cents

  def index
    @person ||= person
    @group ||= group

    @accounting_entries = accounting_entries
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
        @warnings.concat @person.errors.full_messages
      end
    end

    flash[:alert] = @alerts.join("\n")
    flash[:notice] = @notices.join("\n")
    flash[:warning] = @warnings.join("\n")
    redirect_back_or_to(accounting_group_person_path)
  end

  def new_accounting_entry(params)
    if params[:accounting_entry].blank?
      entry = AccountingEntry.new(
        subject: @person,
        author: current_user,
        amount_currency: "EUR",
        new_sepa_status: @person.sepa_status
      )
    else
      acc_entry_params = params[:accounting_entry].permit(
        :amount_eur,
        :amount_currency,
        :description,
        :comment,
        :end_to_end_identifier,
        :new_sepa_status,
        :value_date
      )
      entry = AccountingEntry.new(
        subject: @person,
        author: current_user,
        amount_currency: "EUR", **acc_entry_params
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

  def get_accounting_entry_path(entry)
    accounting_entry_path(entry)
  end

  def can_accounting?
    can?(:log, person)
  end

  def authorize_action
    authorize!(:edit, person)
  end

  def accounting_entries
    entries = AccountingEntry.where(subject: @person).to_a
    entries << AccountingEntry.new(
      created_at: @person.created_at,
      subject: @person,
      author: nil,
      description: "Teilnahmebetrag Gesamt",
      amount_cents: -(payment_value(@person).to_f * 100).round,
      amount_currency: "EUR"
    )
    entries.sort_by! { |elt| elt.created_at }
    entries
  end

  def get_accounting_payment_array
    array = []
    total = -payment_value_cents(@person)
    payment_array_table = payment_array_table(@person).dup
    payment_array_table[0].each_index { |x|
      if payment_array_table[0][x] != "Rolle" && payment_array_table[0][x] != "Gesamt"
        total += (payment_array_table[1][x].to_i * 100)
        array.push({
          month: payment_array_table[0][x],
          amount: format_cents_de(payment_array_table[1][x].to_i * 100),
          total: format_cents_de(total)
        })
      end
    }
    array
  end

  def format_cents_de(cents, currency = "EUR")
    if currency == "EUR"
      currency = "€"
    end
    number = cents.to_f / 100.0
    number_to_currency(number, separator: ",", delimiter: ".", unit: currency, format: "%n %u")
  end

  def sum_entries_amount_cents(entries)
    balance = 0
    entries.each { |e|
      balance += e.amount_cents
    }
    balance
  end
end
