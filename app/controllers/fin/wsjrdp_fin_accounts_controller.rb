# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class Fin::WsjrdpFinAccountsController < ApplicationController
  include WsjrdpFormHelper
  include WsjrdpFinHelper
  include WsjrdpNumberHelper

  eur_attribute :closing_balance_eur, cents_attr: :closing_balance_cents

  before_action :authorize_action

  helper_method :can_fin_admin?
  helper_method :fin_account, :ordered_transactions
  helper_method :permitted_attrs
  helper_method :cancel_url, :return_url
  helper_method :fin_account_path

  def show
    @wsjrdp_fin_account ||= fin_account
    @ordered_transactions ||= ordered_transactions
    render :show
  end

  def update
    @wsjrdp_fin_account ||= fin_account
    authorize!(:fin_admin, fin_account)
    @wsjrdp_fin_account.attributes = permitted_params
    if @wsjrdp_fin_account.save
      redirect_to return_url
    else
      render :show, status: :bad_request
    end
  end

  def fin_account
    @wsjrdp_fin_account ||= WsjrdpFinAccount.find(params[:id])
  end

  def ordered_transactions
    @ordered_transactions ||= fin_account.transactions.sort_by { |t| [t.value_date, t.id] }.reverse
  end

  def can_fin_admin?
    @can_fin_admin = get_can_fin_admin(fin_account, params: params) if @can_fin_admin.nil?
    @can_fin_admin
  end

  private

  def authorize_action
    authorize!(:show, fin_account)
  end

  def return_url
    return_url_or_fallback url_for(fin_account)
  end

  def cancel_url
    return_url
  end

  def fin_account_path(entry = nil)
    url_for(entry.nil? ? fin_account : entry)
  end

  def model_params
    params.require(:wsjrdp_fin_account)
  end

  def permitted_attrs
    [:short_name, :description]
  end

  def permitted_params
    model_params.permit(permitted_attrs)
  end
end
