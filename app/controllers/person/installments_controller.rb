# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A plan is planned first and takes effect when activated.
class Person::InstallmentsController < ApplicationController
  include ContractHelper
  include PersonInPrimaryGroup
  include WsjrdpFormHelper

  # What the form starts from: blank, active, standard or stored plan.
  MODES = %w[new from_active from_standard edit].freeze

  PLANNED_ATTRS = %i[
    planned_custom_installments_string
    planned_custom_installments_issue
    planned_custom_installments_comment
    planned_custom_installments_payment_method
  ].freeze

  PLAN_SAVED = "Geplanter Ratenplan gespeichert – noch nicht wirksam."

  before_action :authorize_action

  helper_method :mode, :context, :plan_text

  def edit
    case mode
    when "new" then person.participation_fee.clear_planned_installments
    when "from_active" then person.participation_fee.plan_installments_from_active
    when "from_standard"
      person.participation_fee.plan_installments_from_standard
      # The fee rule's cents cannot hold a fraction of a cent: the text takes the
      # standard plan's own, unrounded, which saving then refuses.
      @plan_text = person.participation_fee.standard_payment_plan&.installment_plan&.text
    end
  end

  def buttons
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to person_fee_path(person) }
    end
  end

  def preview
    render partial: "person/installments/preview",
      locals: {person: person, plan_text: params[:plan].to_s, details_open: params[:open] == "1"}
  end

  def update
    return leave_form(discard_plan) if params[:commit_action] == "discard"

    attrs = params.require(:person).permit(PLANNED_ATTRS)
    @plan_text = attrs.delete(:planned_custom_installments_string)
    person.attributes = attrs
    if plan_string_valid?(@plan_text) && save_plan
      leave_form((params[:commit_action] == "activate") ? activate_plan : PLAN_SAVED)
    else
      respond_to do |format|
        format.turbo_stream { render :edit, status: :unprocessable_entity }
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  def activate
    if person.planned_fee_rule&.custom_installments_plan?
      leave_form(activate_plan)
    else
      leave_form("Es ist kein Ratenplan geplant.")
    end
  end

  def discard
    leave_form(discard_plan)
  end

  private

  def authorize_action
    authorize!(:update_finance, person)
  end

  def mode
    MODES.include?(params[:mode]) ? params[:mode] : "edit"
  end

  def plan_text = @plan_text || person.planned_custom_installments_string

  def save_plan
    person.planned_custom_installments_string = @plan_text
    rule = person.ensure_planned_fee_rule
    rule.created_by ||= current_user if rule.new_record?
    rule.updated_by = current_user
    person.save
  end

  def activate_plan
    person.participation_fee.activate_installments!(by: current_user)
    "Ratenplan aktiviert."
  end

  def discard_plan
    if person.participation_fee.discard_installments!(by: current_user)
      "Geplanter Ratenplan verworfen."
    else
      "Es ist kein Ratenplan geplant."
    end
  end

  # The fin list reloads instead of morphing: a change re-sorts its rows,
  # and a morph matches rows by position.
  def leave_form(notice)
    flash[:installments_notice] = {"person_id" => person.id, "text" => notice}
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.action((context == "fin") ? :reload_keep_scroll : :refresh, nil)
      end
      format.html { redirect_back_or_to person_fee_path(person) }
    end
  end

  def context = (params[:context] == "fin") ? "fin" : "person"

  def plan_string_valid?(value)
    Wsjrdp2027::InstallmentPlan.from_text(value)
    true
  rescue Wsjrdp2027::InstallmentPlan::Invalid => e
    # On :base, so the message reads with the form's short label.
    person.errors.add(:base, e.message)
    false
  end
end
