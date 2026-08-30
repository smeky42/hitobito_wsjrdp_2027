# frozen_string_literal: true

#  Copyright (c) 2025, 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class Fin::WsjrdpFinAccountsController < Fin::FinController
  include WsjrdpFormHelper
  include Fin::AccessHelper
  include WsjrdpNumberHelper

  decorates :person

  eur_attribute :closing_balance_eur, cents_attr: :closing_balance_cents

  before_action :authorize_action
  before_action :check_fin_params_and_cookies

  helper_method :can_fin_admin?
  helper_method :fin_account, :ordered_transactions
  helper_method :permitted_attrs
  helper_method :cancel_url, :return_url
  helper_method :fin_account_path
  helper_method :link_subject_path
  helper_method :disallow_link_subject_path

  def index
    authorize!(:fin_admin, WsjrdpFinAccount)
    @wsjrdp_fin_accounts = WsjrdpFinAccount.all
  end

  def show
    authorize!(:show, fin_account)
    @wsjrdp_fin_account ||= fin_account
    @ordered_transactions ||= ordered_transactions
    render :show
  end

  def update
    authorize!(:edit, fin_account)
    authorize!(:fin_admin, fin_account)
    @wsjrdp_fin_account ||= fin_account
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
    can?(:fin_admin, fin_account) && param_is_true(cookies, :fin_admin)
  end

  private

  def authorize_action
    authorize!(:show, WsjrdpFinAccount)
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

  def link_subject_path(tx, subject)
    "#{url_for(tx)}/link_subject/#{subject.id}/#{subject.class.name}"
  end

  def disallow_link_subject_path(tx, subject)
    "#{url_for(tx)}/disallow_link_subject/#{subject.id}/#{subject.class.name}"
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
