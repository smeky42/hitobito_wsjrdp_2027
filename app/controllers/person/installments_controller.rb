# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The individual installment plan of a person, maintained from the
# "Ratenplan" section of the person's Beitrag page (person/fee/_installments),
# also shown in a row of the Individuelle Ratenpläne list: a plan is planned
# first (the planned fee rule) and takes effect when activated
# (Wsjrdp2027::ParticipationFee#activate_installments!). Planning, activating
# and discarding change how the fee is paid, so they need :update_finance;
# seeing the section does not. Who created, changed, activated or discarded a
# plan is recorded on the fee rule.
class Person::InstallmentsController < ApplicationController
  include ContractHelper
  include PersonInPrimaryGroup
  include WsjrdpFormHelper

  # What the form starts from: a blank plan, the active plan, the standard
  # plan of the role, or the stored plan.
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
    when "from_standard" then person.participation_fee.plan_installments_from_standard
    end
  end

  # Abbrechen in the form: the section's buttons, back in their place.
  def buttons
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to person_fee_path(person) }
    end
  end

  # The form's three buttons: save the plan, save and activate it, or drop
  # the plan altogether (commit_action "save", "activate", "discard"). A
  # refused plan comes back into the form's place with its errors; anything
  # else refreshes the page, which shows the new state (#leave_form).
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

  # The plan in the form: as typed after a refused save, else the planned
  # plan as Wsj27RdpFeeRule writes it.
  def plan_text = @plan_text || person.planned_custom_installments_string

  # The planned fee rule with the typed plan and its authors, saved with the
  # person.
  def save_plan
    person.planned_custom_installments_string = @plan_text
    rule = person.ensure_planned_fee_rule
    rule.created_by ||= current_user if rule.new_record?
    rule.updated_by = current_user
    person.save
  end

  # The plan takes effect (Wsjrdp2027::ParticipationFee). Answers the notice.
  def activate_plan
    person.participation_fee.activate_installments!(by: current_user)
    "Ratenplan aktiviert."
  end

  # Answers the notice.
  def discard_plan
    if person.participation_fee.discard_installments!(by: current_user)
      "Geplanter Ratenplan verworfen."
    else
      "Es ist kein Ratenplan geplant."
    end
  end

  # Back to the page the change was made on. On the person's Beitrag page a
  # page refresh, which the page morphs keeping the scroll position. On the
  # Individuelle Ratenpläne list (context "fin") a full reload that keeps the
  # scroll position: a change there moves the row (the list sorts by
  # activation), and a morph matches the rows by position. Without Turbo a
  # redirect back. The notice shows in the section of this person only.
  def leave_form(notice)
    flash[:installments_notice] = {"person_id" => person.id, "text" => notice}
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.action((context == "fin") ? :reload_keep_scroll : :refresh, nil)
      end
      format.html { redirect_back_or_to person_fee_path(person) }
    end
  end

  # Where the section is shown: "person" (the Beitrag page) or "fin" (a row of
  # the Individuelle Ratenpläne list); the buttons and the form pass it on.
  def context = (params[:context] == "fin") ? "fin" : "person"

  # A plan is required, written as Wsj27RdpFeeRule takes it.
  def plan_string_valid?(value)
    return true if value.to_s.match?(Wsj27RdpFeeRule::CUSTOM_INSTALLMENTS_STRING_FORMAT)

    # On :base, so the message reads with the form's short label.
    person.errors.add(:base, value.blank? ? "Ratenplan muss ausgefüllt werden" :
      "Ratenplan hat nicht die Form „Jahr: Betrag; Betrag; …“")
    false
  end
end
