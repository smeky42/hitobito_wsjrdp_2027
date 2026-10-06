# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The total fee reduction of a person, maintained from the "Beitragshöhe"
# section of the person's Beitrag page (person/fee/_fee_reduction): a reduction
# is planned first (planned_total_fee_reduction*, a draft the person log does
# not record) and takes effect when activated (wsjrdp_total_fee_reduction*).
# Planning, activating and discarding change the fee, so they need
# :update_finance; seeing the section needs :log only.
class Person::FeeReductionController < ApplicationController
  include ContractHelper
  include WsjrdpFormHelper

  # What the form starts from: a blank plan, the active reduction, or the
  # stored plan.
  MODES = %w[new from_active edit].freeze

  PLAN_SAVED = "Geplante Beitragsreduktion gespeichert – noch nicht wirksam."

  before_action :authorize_action
  decorates :group, :person

  helper_method :mode, :amount_text, :context

  def edit
    person.participation_fee.plan_reduction_from_active if mode == "from_active"
    person.participation_fee.clear_planned_reduction if mode == "new"
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
  # refused plan comes back into the form's frame with its errors; anything
  # else refreshes the page, which shows the new state (#leave_form).
  def update
    return leave_form(discard_plan) if params[:commit_action] == "discard"

    attrs = params.require(:person).permit(Wsjrdp2027::ParticipationFee::PLANNED_REDUCTION_ATTRS)
    @amount_text = attrs.delete(:planned_total_fee_reduction)
    amount = parse_amount(@amount_text)
    person.attributes = attrs.merge(planned_total_fee_reduction: amount)
    if planned_amount_valid?(amount) && person.save
      leave_form((params[:commit_action] == "activate") ? activate_plan : PLAN_SAVED)
    else
      respond_to do |format|
        format.turbo_stream { render :edit, status: :unprocessable_entity }
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  def activate
    if person.planned_total_fee_reduction.nil?
      leave_form("Es ist keine Beitragsreduktion geplant.")
    else
      leave_form(activate_plan)
    end
  end

  def discard
    leave_form(discard_plan)
  end

  private

  def authorize_action
    authorize!(:update_finance, person)
  end

  def person
    @person ||= Person.find(params[:person_id])
  end

  def group
    @group ||= person.primary_group || Group.root
  end

  def mode
    MODES.include?(params[:mode]) ? params[:mode] : "edit"
  end

  # The amount in the form: as typed after a failed save, else the plan in
  # German notation.
  def amount_text
    return @amount_text if @amount_text

    eur = person.planned_total_fee_reduction
    helpers.number_with_precision(eur, precision: 2, separator: ",", delimiter: "") if eur
  end

  # The plan takes effect (Wsjrdp2027::ParticipationFee). Answers the notice.
  def activate_plan
    person.participation_fee.activate_reduction!
    "Beitragsreduktion aktiviert – Beitrag jetzt #{format_cents_de(person.total_fee_cents, space: "", zero_cents: "")}."
  end

  # Answers the notice.
  def discard_plan
    person.participation_fee.discard_reduction!
    "Geplante Beitragsreduktion verworfen."
  end

  # Back to the page the change was made on. On the person's Beitrag page a
  # page refresh, which the page morphs keeping the scroll position. On the
  # Reduktionen list (context "fin") a full reload that keeps the scroll
  # position: a change there moves the row (the list sorts by activation), and
  # a morph matches the rows by position. Without Turbo a redirect back. The
  # notice shows in the section of this person only.
  def leave_form(notice)
    flash[:fee_reduction_notice] = {"person_id" => person.id, "text" => notice}
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.action((context == "fin") ? :reload_keep_scroll : :refresh, nil)
      end
      format.html { redirect_back_or_to person_fee_path(person) }
    end
  end

  # Where the section is shown: "person" (the Beitrag page) or "fin" (a row of
  # the Reduktionen list); the buttons and the form pass it on.
  def context = (params[:context] == "fin") ? "fin" : "person"

  # The amount as typed, "250", "250,50", "1.700,00" or "250.50"; nil for
  # anything else.
  def parse_amount(value)
    text = value.to_s.strip
    text = text.delete(".").tr(",", ".") if text.include?(",")
    BigDecimal(text) if text.match?(/\A\d+(\.\d{1,2})?\z/)
  end

  # A plan takes something off the regular fee, at most all of it.
  def planned_amount_valid?(amount)
    # The regular fee, as the fee computation takes it (Person#total_fee_eur).
    max_eur = person.total_fee_eur + person.active_total_fee_reduction
    return true if amount.present? && amount.positive? && amount <= max_eur

    # On :base, so the message reads with the form's short label.
    person.errors.add(:base, "Betrag muss größer als 0 und höchstens #{format_eur_de(max_eur, space: "", zero_cents: "")} sein")
    false
  end
end
