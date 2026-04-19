# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class Fin::WsjrdpPaymentPlansController < ApplicationController
  include WsjrdpFormHelper
  include WsjrdpFinHelper
  include ContractHelper

  before_action :map_id_to_wsjrdp_payment_plan_id
  before_action :check_fin_params_and_cookies

  helper_method :can_fin_admin?
  helper_method :permitted_attrs
  helper_method :cancel_url, :return_url

  def index
    authorize!(:show, WsjrdpPaymentPlan)
    plans = WsjrdpPaymentPlan.all.to_a
    roles = ["CMT", "UL", "YP", "IST", "BMT", "EXT"]
    plans.sort_by! do |plan|
      [
        roles.find_index(plan.wsjrdp_role) || 1000,
        plan.wsjrdp_role,
        plan.single_payment ? 1 : 0
      ]
    end
    @payment_plans = plans
  end

  def show
    @wsjrdp_payment_plan ||= wsjrdp_payment_plan
    authorize!(:show, @wsjrdp_payment_plan)
  end

  def update
    @wsjrdp_payment_plan ||= wsjrdp_payment_plan
    authorize!(:update, @wsjrdp_payment_plan)
    @wsjrdp_payment_plan.attributes = permitted_params
    if @wsjrdp_payment_plan.save
      flash[:notice] = "Ratenplan #{@wsjrdp_payment_plan.id} erfolgreich aktualisiert."
      redirect_to return_url
    else
      render :show, status: :bad_request
    end
  end

  private

  def return_url
    return_url_or_fallback url_for(wsjrdp_payment_plan)
  end

  def cancel_url
    return_url
  end

  def map_id_to_wsjrdp_payment_plan_id
    params[:wsjrdp_payment_plan_id] = params[:id] unless params.key?(:wsjrdp_payment_plan_id)
  end

  def can_fin_admin?
    can?(:fin_admin, wsjrdp_payment_plan) && param_is_true(cookies, :fin_admin)
  end

  def wsjrdp_payment_plan
    @wsjrdp_payment_plan ||= WsjrdpPaymentPlan.find(params[:wsjrdp_payment_plan_id])
  end

  def model_params
    params.require(:wsjrdp_payment_plan)
  end

  def permitted_attrs
    [
      :comment,
      :status,
      :wsjrdp_role,
      :single_payment,
      :installments_string
    ]
  end

  def permitted_params
    model_params.permit(permitted_attrs)
  end
end
