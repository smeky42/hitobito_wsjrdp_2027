# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class Person::DeregistrationController < ApplicationController
  include ContractHelper
  include WsjrdpFinHelper
  include WsjrdpFormHelper

  before_action :authorize_action
  decorates :group, :person

  helper_method :target_turbo_frame
  helper_method :return_url
  helper_method :permitted_attrs

  def edit
  end

  def update
    @person ||= person
    @person.attributes = permitted_params
    if !@person.changed?
      reload_or_return notice: "Angaben zur Abmeldung wurden nicht verändert"
    elsif @person.save
      reload_or_return notice: "Angaben zur Abmeldung wurden erfolgreich angepasst"
    else
      render :edit, status: :bad_request
    end
  end

  private

  def authorize_action
    authorize!(:log, person)
  end

  def person
    @person ||= Person.find(params[:person_id])
  end

  def group
    @group ||= person.primary_group
  end

  def permitted_attrs
    [
      :deregistration_actual_compensation_cents,
      :deregistration_actual_compensation_eur,
      :deregistration_effective_date,
      :deregistration_issue,
      :sepa_status,
      :status
    ]
  end

  def model_params
    params.require(:person)
  end

  def permitted_params
    model_params.permit(permitted_attrs)
  end

  def target_turbo_frame
    params[:target_turbo_frame]
  end

  def return_url
    return_url_or_fallback person_accounting_path(person)
  end

  def reload_or_return(notice: nil)
    if notice.present?
      flash.now[:notice] = notice
      flash.keep
    end
    respond_to do |format|
      format.html { redirect_back_or_to return_url }
      format.turbo_stream { render turbo_stream: turbo_stream.action(:location_reload, "") }
    end
  end
end
