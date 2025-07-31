# frozen_string_literal: true

class Person::AccountingController < ApplicationController
  include ContractHelper
  include ActionView::Helpers::NumberHelper
  before_action :authorize_action
  decorates :group, :person

  def index
    @group ||= Group.find(params[:group_id])
    @person ||= group.people.find(params[:id])

    @accounting = accounting
    @accounting_entries = accounting_entries
    @accounting_payment_value = get_number_to_currency(-1 * get_payment_value.to_f)
    @accounting_payment_array = accounting_payment_array
    @accounting_balance = accounting_balance
    @possible_sepa_states = Settings.sepa_status
    save_put
  end

  def accounting_value(value)
    text_value = value.to_f / 100
    number_to_currency(text_value, separator: ",", delimiter: ".", format: "%n %u")
  end
  helper_method :accounting_value

  private

  def person
    @person ||= Person.find(params[:id])
  end

  def group
    @group ||= Group.find(params[:group_id])
  end

  def accounting
    can?(:log, person)
  end

  def authorize_action
    authorize!(:edit, person)
  end

  # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity,Metrics/MethodLength,Metrics/AbcSize
  def save_put
    if @accounting && request.put?
      if params[:accounting_comment].empty?
        flash[:alert] = "Bitte gib einen Kommentar an."
        redirect_back(fallback_location: "/")
        return
      end

      accounting_ammount = if params[:accounting_ammount].empty?
        0
      else
        params[:accounting_ammount]
      end

      AccountingEntries.create(id: AccountingEntries.count + 1,
        subject_id: @person.id,
        author_id: current_user.id,
        ammount: accounting_ammount,
        comment: params[:accounting_comment],
        created_at: DateTime.now)

      @person.sepa_status = params[:sepa_status]
      @person.save

      flash[:notice] =
        "Buchung #{params[:sepa_status]} in Höhe von #{accounting_ammount} cent erfolgreich angelegt! \n
         Status auf #{params[:sepa_status]} gesetzt."
      redirect_back(fallback_location: "/")
    end
  end

  def accounting_entries
    AccountingEntries.where(subject_id: @person.id)
  end

  def accounting_payment_array
    array = []
    total = (-1 * get_payment_value.to_f)
    payment_array_table = payment_array_table(@person).dup
    payment_array_table[0].each_index { |x|
      if payment_array_table[0][x] != "Rolle" && payment_array_table[0][x] != "Gesamt"
        total += payment_array_table[1][x].to_f
        array.push({
          month: payment_array_table[0][x],
          ammount: get_number_to_currency(payment_array_table[1][x].to_f),
          total: get_number_to_currency(total)
        })
      end
    }
    array
  end
  # rubocop:enable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity,Metrics/MethodLength,Metrics/AbcSize

  def accounting_balance
    balance = 0 - (1 * get_payment_value.to_f)
    account_entries = accounting_entries
    account_entries.each { |x|
      balance += (x.ammount.to_f / 100)
    }
    get_number_to_currency(balance)
  end

  def get_number_to_currency(number)
    number_to_currency(number, separator: ",", delimiter: ".", format: "%n %u")
  end

  def get_payment_value
    payment_value(@person)
  end
end
