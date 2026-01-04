# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class WsjrdpFinAccountsController < ApplicationController
  include WsjrdpFormHelper
  include WsjrdpFinHelper
  include WsjrdpNumberHelper

  eur_attribute :closing_balance_eur, cents_attr: :closing_balance_cents

  before_action :authorize_action

  helper_method :can_fin_admin?
  helper_method :fin_account, :transactions
  helper_method :closing_balance_cents, :closing_balance_eur, :closing_balance_eur_display
  helper_method :permitted_attrs
  helper_method :fin_account_return_url
  helper_method :fin_account_path

  def show
    @wsjrdp_fin_account ||= fin_account
    @transactions ||= transactions
    render "fin/fin_account_show"
  end

  def fin_account
    @fin_account ||= WsjrdpFinAccount.find(params[:id])
  end

  def transactions
    @transactions ||= fin_account.transactions.sort_by { |t| [t.value_date, t.id] }.reverse
  end

  def closing_balance_cents
    fin_account.opening_balance_cents + transactions.map { |e| e.amount_cents }.sum
  end

  def can_fin_admin?
    @can_fin_admin = get_can_fin_admin(fin_account, params: params) if @can_fin_admin.nil?
    @can_fin_admin
  end

  private

  def authorize_action
    authorize!(:show, fin_account)
  end

  def fin_account_path(entry = nil)
    url_for(entry.nil? ? fin_account : entry)
  end

  def fin_account_return_url(entry = nil)
    params[:return_url].presence || fin_account_path(entry)
  end

  def permitted_attrs
    [:short_name, :description]
  end
end
