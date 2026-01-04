# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class CamtTransaction::ActionsController < ApplicationController
  include WsjrdpFormHelper
  include WsjrdpFinHelper

  before_action :authorize_action

  def create_accounting_entry
    tx = camt_transaction
    subject = tx.subject
    authorize!(:update, subject)
    entry = AccountingEntry.create!(
      subject: subject,
      author: current_user,
      amount_cents: tx.amount_cents,
      amount_currency: tx.amount_currency,
      description: tx.description,
      comment: tx.comment,
      value_date: tx.value_date,
      booking_date: tx.booking_date,
      mandate_id: tx.mandate_id,
      endtoend_id: tx.endtoend_id,
      cdtr_name: tx.cdtr_name,
      cdtr_iban: tx.cdtr_iban,
      cdtr_bic: tx.cdtr_bic,
      cdtr_address: tx.cdtr_address,
      dbtr_name: tx.dbtr_name,
      dbtr_iban: tx.dbtr_iban,
      dbtr_bic: tx.dbtr_bic,
      dbtr_address: tx.dbtr_address,
      return_reason: tx.return_reason,
      camt_transaction_id: tx.id
    )
    tx.accounting_entry_id = entry.id
    tx.save!
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.action(:refresh, "") }
      format.html { redirect_to tx.fin_account }
    end
  end

  def link_accounting_entry
    tx = camt_transaction
    subject = tx.subject
    authorize!(:update, subject)
    accounting_entry = AccountingEntry.find(params[:accounting_entry_id])
    accounting_entry.camt_transaction_id = tx.id
    tx.accounting_entry_id = accounting_entry.id
    tx.save!
    accounting_entry.save!
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.action(:refresh, "") }
      format.html { redirect_to tx.fin_account }
    end
  end

  private

  def authorize_action
    authorize!(:update, camt_transaction)
  end

  def camt_transaction
    @camt_transaction ||= WsjrdpCamtTransaction.find(params[:wsjrdp_camt_transaction_id])
  end
end
