# frozen_string_literal: true

#  Copyright (c) 2025, 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class Person::AccountingController < ApplicationController
  include ContractHelper
  include WsjrdpFinHelper

  before_action :map_id_to_person_id
  before_action :authorize_action
  decorates :group, :person

  helper_method :get_entry_path
  helper_method :can_fin?
  helper_method :can_fin_admin?
  helper_method :get_installments_table_entries
  helper_method :permitted_attrs
  helper_method :extra_entry_turbo_frame

  def show
    @person ||= person
    @group ||= group

    @accounting_entries = accounting_entries
    @direct_debit_pre_notifications = direct_debit_pre_notifications
    @new_accounting_entry = new_accounting_entry(params)
    @new_accounting_entry_path = new_accounting_entry_path + "?" + URI.encode_www_form({
      "accounting_entry[subject_id]": @person.id,
      target_turbo_frame: extra_entry_turbo_frame
    })
    @new_sepa_status_path = new_sepa_status_path + "?" + URI.encode_www_form({
      "accounting_entry[subject_id]": @person.id,
      "accounting_entry[amount_cents]": 0,
      "accounting_entry[new_sepa_status]": @person.sepa_status,
      target_turbo_frame: extra_entry_turbo_frame
    })
    @edit_deregistration_path = edit_person_deregistration_path(person) + "?" + URI.encode_www_form({
      target_turbo_frame: extra_entry_turbo_frame
    })
    @edit_debit_return_path = edit_person_debit_return_path(person) + "?" + URI.encode_www_form({
      target_turbo_frame: extra_entry_turbo_frame
    })
    render :show
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
    @person ||= Person.find(params[:person_id])
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

  def can_fin?
    @can_fin = get_can_fin(person, params: params) if @can_fin.nil?
    @can_fin
  end

  def can_fin_admin?
    @can_fin_admin = get_can_fin_admin(person, params: params) if @can_fin_admin.nil?
    @can_fin_admin
  end

  def authorize_action
    authorize!(:edit, person)
  end

  def map_id_to_person_id
    params[:person_id] = params[:id] unless params.key?(:person_id)
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

  def extra_entry_turbo_frame
    :accounting_extra_entry
  end
end
