# frozen_string_literal: true

class Person::AccountingController < ApplicationController
  include ContractHelper
  include ActionView::Helpers::NumberHelper

  before_action :authorize_action
  decorates :group, :person

  helper_method :accounting_entry_path
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

    @notices << "Neue Buchung in Höhe von #{@new_accounting_entry.amount_eur_display} erfolgreich angelegt."

    new_sepa_status = @new_accounting_entry.sepa_status
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
      entry = AccountingEntries.new(
        people_id: @person.id,
        author_id: current_user.id,
        amount_currency: "EUR",
        sepa_status: @person.sepa_status
      )
    else
      acc_entry_params = params[:accounting_entry].permit(
        :amount_eur, :amount_currency,
        :description, :comment,
        :end_to_end_identifier,
        :sepa_status, :value_date
      )
      entry = AccountingEntries.new(people_id: @person.id,
        author_id: current_user.id,
        amount_currency: "EUR", **acc_entry_params)
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

  def accounting_entry_path(entry)
    group_person_accounting_entry_path(group, person, entry)
  end

  def can_accounting?
    can?(:log, person)
  end

  def authorize_action
    authorize!(:edit, person)
  end

  # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity,Metrics/MethodLength,Metrics/AbcSize
  def save_put
    unless can_accounting?
      flash.now[:error] = "Fehlende Rechte Buchhaltungs-Einträge anzulegen"
      return
    end

    if params[:button] == "fill-form-for-reverse"
      if params[:reverses_accounting_entry_id].blank?
        flash.now[:alert] = "Keine Buchung für Storno ausgewählt!"
        render :index, status: :bad_request
        return
      end
      entry = AccountingEntries.find(params[:reverses_accounting_entry_id])
      if !entry.reversed_by_accounting_entry_id.blank?
        flash.now[:alert] = "Ausgewählte Buchung wurde bereits storniert!"
        render :index, status: :bad_request
        return
      end
      # @accounting_amount_eur = -(entry.amount_cents.to_f / 100)
      # @accounting_comment = "Storno: #{entry.comment}"
      @accounting_reverses = entry.id
      flash.now[:notice] = "Storno Buchung vorbereitet aber noch nicht gespeichtert."
      render :index, status: :bad_request
      return
    end

    # # if params[:accounting_comment].blank?
    # #   flash.now[:alert] = "Bitte gib einen Kommentar an."
    # #   render :index, status: :bad_request
    # #   return
    # # end

    # accounting_amount_eur = if params[:accounting_amount_eur].empty?
    #                           0.0
    #                         else
    #                           params[:accounting_amount_eur].to_f
    #                         end
    # accounting_amount_cents = (accounting_amount_eur * 100).round
    # accounting_amount_display = number_to_currency(accounting_amount_eur, separator: ",", delimiter: ".", format: "%n %u")

    # now = DateTime.now

    # sepa_status = params[:sepa_status]
    # value_date = if params[:value_date].blank? then
    #                now.to_date
    #              else
    #                params[:value_date].to_date
    #              end

    # entry = AccountingEntries.new(
    #   people_id: @person.id,
    #   author_id: current_user.id,
    #   amount_cents: accounting_amount_cents,
    #   amount_currency: "EUR",
    #   comment: params[:accounting_comment],
    #   value_date: value_date,
    #   sepa_status: sepa_status,
    # )

    entry = @new_accounting_entry
    # if entry.amount_cents.nil?
    #   entry.amount_cents = 0
    # end

    reversed_entry = nil

    if !params[:accounting_reverses].blank?
      reverses = params[:accounting_reverses].to_i

      reversed_entry = AccountingEntries.find(reverses)
      if reversed_entry.reversed_by_accounting_entry_id.blank?
        entry.reverses_accounting_entry_id = reverses
      end
    end
    if !entry.save
      return
    end

    # updating reversed_entry (if any) after saving entry to be able
    # to fetch the id.
    if !reversed_entry.blank?
      reversed_entry.reversed_by_accounting_entry_id = entry.id
      reversed_entry.save
    end

    if @person.sepa_status != entry.sepa_status
      @person.sepa_status = entry.sepa_status
      @person.save
    end

    flash[:notice] =
      "Buchung #{entry.id} in Höhe von #{entry.amount_eur_display} erfolgreich angelegt!\n
       Finanzstatus auf #{Settings.sepa_status[entry.sepa_status]} gesetzt."
    redirect_back_or_to(accounting_group_person_path)
  end

  def accounting_entries
    entries = AccountingEntries.where(people_id: @person.id).to_a
    entries << AccountingEntries.new(
      created_at: @person.created_at,
      people_id: @person.id,
      author_id: 0,
      description: "Teilnehmendenbetrag Gesamt",
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
  # rubocop:enable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity,Metrics/MethodLength,Metrics/AbcSize

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
