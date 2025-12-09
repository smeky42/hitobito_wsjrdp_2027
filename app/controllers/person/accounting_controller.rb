# frozen_string_literal: true

class Person::AccountingController < ApplicationController
  include ContractHelper

  before_action :authorize_action
  decorates :group, :person

  helper_method :get_accounting_entry_path
  helper_method :can_accounting?
  helper_method :format_cents_de
  helper_method :get_installments_table_entries
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
    active_fee_rule = @person.active_fee_rule
    total_fee_reduction_cents = active_fee_rule&.total_fee_reduction_cents || 0
    description = "Ausstehender Teilnahmebetrag"
    if total_fee_reduction_cents != 0
      fee_reduction_display = format_cents_de(total_fee_reduction_cents)
      reduction_comment = "reduziert um #{fee_reduction_display}"
      if !active_fee_rule&.total_fee_reduction_comment.blank?
        reduction_comment = "#{active_fee_rule.total_fee_reduction_comment}: #{reduction_comment}"
      end
      description += " (#{reduction_comment})"
    end
    total_fee_entry = AccountingEntry.new(
      created_at: @person.created_at,
      subject: @person,
      author: nil,
      description: description,
      amount_cents: -get_total_fee_cents(@person, active_fee_rule),
      amount_currency: "EUR"
    )
    total_fee_entry.readonly!
    entries = AccountingEntry.where(subject: @person).to_a
    entries.sort_by! { |elt| elt.created_at }
    entries.unshift(total_fee_entry)
    entries
  end

  def get_installments_table_entries
    active_fee_rule = @person.active_fee_rule
    total = -get_total_fee_cents(@person, active_fee_rule)
    installments = get_installments_cents(@person, active_fee_rule)
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

  def sum_entries_amount_cents(entries)
    balance = 0
    entries.each { |e|
      balance += e.amount_cents
    }
    balance
  end
end
