# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The "Abmeldung" sub-tab of a person's Finanzen section
# (/people/:id/deregistration). It reads like the Status and Medizin tabs: the
# page itself is read-only and its toolbar carries an edit button to the form.
#
# PersonInPrimaryGroup supplies the group its sheet and left navigation need --
# and maps :id to :person_id, which keeps the resource reachable under both
# spellings. That callback is registered before :authorize_action, so #person
# already finds its key when the authorization runs.
class Person::DeregistrationController < ApplicationController
  include PersonInPrimaryGroup
  include ContractHelper
  include WsjrdpFormHelper

  before_action :authorize_action

  helper_method :return_url
  helper_method :permitted_attrs

  # What the flash's change lines are made of: U+2192 between the two values,
  # an en dash where there is no value.
  CHANGE_ARROW = "→"
  BLANK_VALUE = "–"
  DATE_ATTRS = %i[deregistration_effective_date deregistration_requested_date].freeze
  CENTS_ATTRS = %i[deregistration_actual_compensation_cents].freeze

  def show
    @person ||= person
    @group ||= group
    # The page previews what the receipt will say, so it builds the same
    # object the PDF is made of -- and above it, what the creditor the refund
    # is paid to looks like in Moss.
    @refund_creditor = Wsjrdp2027::RefundCreditor.new(person)
    @refund_receipt = Wsjrdp2027::RefundReceipt.new(person, generated_by: current_user)
    render :show
  end

  def edit
    @person ||= person
    @group ||= group
    render :edit
  end

  # The slip the finance team pays the refund from: built from the person on
  # every request and never stored, so it says what the page says. A POST,
  # because the text the page carries is saved on the way -- the document is
  # what was last seen on the form.
  def refund_receipt
    save_receipt_settings
    receipt = Wsjrdp2027::RefundReceipt.new(person, generated_by: current_user)
    send_data receipt.to_pdf, type: "application/pdf", disposition: "inline",
      filename: receipt.file_name
  end

  # The same save without the document: for the small button next to the text.
  def refund_receipt_text
    flash[:notice] = t(save_receipt_settings ? "people.refund_receipt.saved" : "people.refund_receipt.unchanged")
    redirect_to person_deregistration_path(person)
  end

  def update
    @person ||= person
    @person.attributes = permitted_params
    # What the save is about to write: #save clears it, so it is read here.
    changes = @person.changes
    if !@person.changed?
      redirect_after_update notice: "Angaben zur Abmeldung wurden nicht verändert"
    elsif @person.save
      redirect_after_update notice: change_notice(changes)
    else
      render :edit, status: :bad_request
    end
  end

  private

  # What the receipt says is written here and nowhere else: neither key is part
  # of permitted_attrs, so the edit form can neither carry nor clear them. Each
  # is touched only where the form actually sent it. Answers whether anything
  # was written.
  def save_receipt_settings
    settings = params[:person]
    return false if settings.blank?

    if settings.key?(:deregistration_refund_receipt_text)
      person.deregistration_refund_receipt_text = settings[:deregistration_refund_receipt_text]
    end
    if settings.key?(:deregistration_refund_receipt_show_default_explanation)
      person.deregistration_refund_receipt_show_default_explanation = explanation_flag(settings)
    end
    return false unless person.changed?

    person.save!
    true
  end

  # Absent is what "show it" looks like in the store, so a checked box clears
  # the key and only an explicit "off" is kept.
  def explanation_flag(settings)
    checked = ActiveModel::Type::Boolean.new
      .cast(settings[:deregistration_refund_receipt_show_default_explanation])
    checked ? nil : false
  end

  def authorize_action
    @person ||= person
    @group ||= group
    authorize!(:log, person)
  end

  def permitted_attrs
    [
      :deregistration_kind,
      :deregistration_actual_compensation_cents,
      :deregistration_actual_compensation_eur,
      :deregistration_effective_date,
      :deregistration_issue,
      :deregistration_requested_date,
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

  def return_url
    return_url_or_fallback person_deregistration_path(person)
  end

  # Where a saved form leads: the read-only page, or wherever the form was
  # opened from (the return_url the form carries). One redirect for every
  # format -- Turbo submits the form as POST with _method=put and follows the
  # redirect with a full visit, so leaving the edit page needs no turbo_stream
  # action of its own.
  def redirect_after_update(notice: nil)
    flash[:notice] = notice if notice.present?
    redirect_to return_url
  end

  # What the save changed, field by field. The flash partial joins an array with
  # newlines and runs it through simple_format, so each element becomes its own
  # line -- plain text, since the partial sanitizes tags away.
  def change_notice(changes)
    lines = change_lines(changes)
    return "Angaben zur Abmeldung wurden erfolgreich angepasst" if lines.empty?

    ["Angaben zur Abmeldung angepasst:", *lines]
  end

  # In the order this form lists its fields, so the lines do not shuffle from
  # one save to the next.
  def change_lines(changes)
    flat = flat_changes(changes)
    permitted_attrs.filter_map do |attr|
      next unless flat.key?(attr.to_s)

      before, after = flat[attr.to_s]
      "#{Person.human_attribute_name(attr)}: " \
        "#{format_change_value(attr, before)} #{CHANGE_ARROW} " \
        "#{format_change_value(attr, after)}"
    end
  end

  # Every deregistration field is a jsonb accessor on additional_info, which
  # Rails tracks as ONE change of that column -- so the per-field before and
  # after have to be read out of the two hashes. The plain columns
  # (sepa_status, status) are tracked on their own and pass through.
  #
  # Either hash can be empty and still carry the change: clearing the last
  # remaining field leaves {} behind, because a blank value drops its key.
  # What decides is whether the column changed at all, not what is left in it.
  def flat_changes(changes)
    flat = changes.except("additional_info")
    return flat unless changes.key?("additional_info")

    before, after = changes["additional_info"]
    before = before.to_h
    after = after.to_h
    (before.keys | after.keys).each do |key|
      flat[key] = [before[key], after[key]] if before[key] != after[key]
    end
    flat
  end

  # The values are the jsonb payload: an ISO string for a date, cents for the
  # amount, free text for the ticket.
  def format_change_value(attr, value)
    return format_kind_value(value) if attr == :deregistration_kind
    return BLANK_VALUE if value.blank?

    case attr
    when *DATE_ATTRS then I18n.l(value.to_date)
    when *CENTS_ATTRS then format_cents_de(value)
    else value.to_s.squish
    end
  end

  # The kind has a default (Person#deregistration_kind_or_default), so a blank
  # side of its change is that default's label, never "no value": the page did
  # show "Abmeldung" while the key was absent.
  def format_kind_value(value)
    I18n.t("people.deregistration_kinds.#{value.presence || "withdrawal"}")
  end
end
