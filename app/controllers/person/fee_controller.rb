# frozen_string_literal: true

#  Copyright (c) 2025, 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class Person::FeeController < Fin::FinController
  include PersonInPrimaryGroup
  include ContractHelper

  before_action :authorize_action

  helper_method :get_entry_path
  helper_method :get_installments_table_entries
  helper_method :permitted_attrs
  helper_method :extra_entry_turbo_frame

  def show
    @person ||= person
    @group ||= group

    @journal_entries = journal_entries
    @new_accounting_entry = new_accounting_entry(params)
    # This page already carries the person's name, so the form in its frame
    # leaves it out (hide_subject).
    @new_accounting_entry_path = new_accounting_entry_path + "?" + URI.encode_www_form({
      "accounting_entry[subject_id]": @person.id,
      hide_subject: 1,
      target_turbo_frame: extra_entry_turbo_frame
    })
    @new_sepa_status_path = new_sepa_status_path + "?" + URI.encode_www_form({
      # The amount, the reconciliation flag and the choice of status are the
      # form's own business (Fin::AccountingEntriesController#new_sepa_status).
      "accounting_entry[subject_id]": @person.id,
      hide_subject: 1,
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
      :debit_sequence_type,
      # Support :excluded_from_fee_reconciliation both flat and
      # nested.
      :excluded_from_fee_reconciliation,
      additional_info: [:excluded_from_fee_reconciliation]
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

  def get_entry_path(entry)
    if entry.class.name.demodulize == WsjrdpDirectDebitPreNotification.name.demodulize
      wsjrdp_direct_debit_pre_notification_path(entry)
    else
      accounting_entry_path(entry)
    end
  end

  def authorize_action
    @person ||= person
    @group ||= group
    authorize!(:edit, person)
  end

  def journal_entries
    @journal_entries ||= (
      person.direct_debit_pre_notifications.where(payment_status: %w[pre_notified skipped]).to_a +
      person.accounting_entries.to_a
    ).sort_by { |e|
      e.value_date || e.booking_date || e.created_at.to_date
    }.reverse
  end

  def get_installments_table_entries
    total_eur = BigDecimal(0)
    person.yme_list.map do |item|
      total_eur += item.eur
      {
        date: I18n.l(item.to_time_with_zone(day: 5), format: "%b %Y"),
        amount: format_eur_de(item.eur),
        total: format_eur_de(total_eur)
      }
    end
  end

  def extra_entry_turbo_frame
    :accounting_extra_entry
  end
end
