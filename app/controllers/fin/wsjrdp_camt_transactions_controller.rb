# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class Fin::WsjrdpCamtTransactionsController < ApplicationController
  include WsjrdpFormHelper
  include WsjrdpFinHelper

  before_action :authorize_action

  helper_method :can_fin_admin?
  helper_method :camt_transaction
  helper_method :permitted_attrs
  helper_method :camt_transaction_return_url
  helper_method :camt_transaction_path

  def show
    @wsjrdp_camt_transaction ||= camt_transaction
    render "fin/camt_transaction_show"
  end

  def update
    @wsjrdp_camt_transaction ||= camt_transaction
    authorize!(:update, camt_transaction)
    camt_transaction.attributes = params.require(:wsjrdp_camt_transaction).permit(permitted_attrs)
    if camt_transaction.save
      if camt_transaction_return_url == camt_transaction_path
        flash.now[:notice] = "Transaktion #{camt_transaction.id} erfolgreich aktualisiert."
        render "fin/camt_transaction_show"
      else
        redirect_to camt_transaction_return_url
      end
    else
      render "fin/camt_transaction_show", status: :bad_request
    end
  end

  def camt_transaction
    @camt_transaction ||= WsjrdpCamtTransaction.find(params[:id])
  end

  def authorize_action
    authorize!(:show, camt_transaction)
  end

  def can_fin_admin?
    @can_fin_admin = get_can_fin_admin(camt_transaction, params: params) if @can_fin_admin.nil?
    @can_fin_admin
  end

  private

  def camt_transaction_path(entry = nil)
    fin_wsjrdp_camt_transaction_path(entry.nil? ? camt_transaction : entry)
  end

  def camt_transaction_return_url(entry = nil)
    params[:return_url].presence || camt_transaction_path(entry)
  end

  def permitted_attrs
    [:comment]
  end
end
