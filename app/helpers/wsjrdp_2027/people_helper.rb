# frozen_string_literal: true

#  Copyright (c) 2025, 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027::PeopleHelper
  include ContractHelper

  def person_accounting_path_with_group(group, *args)
    person_accounting_path(args[0], args[-1])
  end

  def person_fee_path_with_group(group, *args)
    person_fee_path(args[0], args[-1])
  end

  def person_finance_path_with_group(group, *args)
    person_finance_path(args[0], args[-1])
  end

  def person_spend_path_with_group(group, *args)
    person_spend_path(args[0], args[-1])
  end

  def person_deregistration_path_with_group(group, *args)
    person_deregistration_path(args[0], args[-1])
  end

  def format_person_sepa_mail(person)
    format_email_or_nil(person.sepa_mail)
  end

  def format_person_additional_contact_email_a(person)
    format_email_or_nil(person.additional_contact_email_a)
  end

  def format_person_additional_contact_email_b(person)
    format_email_or_nil(person.additional_contact_email_b)
  end

  def format_person_wsjrdp_email(person)
    format_email_or_nil(person.wsjrdp_email)
  end

  def format_person_moss_email(person)
    format_email_or_nil(person.moss_email)
  end

  def format_person_moss_invited_at(person)
    l(person.moss_invited_at)
  end

  def format_person_is_preallocated_ist(person)
    person.is_preallocated_ist ? t(:"global.yes") : t(:"global.no")
  end

  def format_person_wsj_role(person)
    if (role = person.wsj_role).present?
      role
    else
      person.short_payment_role
    end
  end

  def format_person_buddy_id(person)
    if person.buddy_id.present?
      "#{person.buddy_id}-#{person.id}"
    else
      content_tag(:span, "Nicht gesetzt", class: "muted fw-light")
    end
  end

  def format_person_unit_code(person)
    make_unit_code_display(person.unit_code, not_set_text: "Nicht gesetzt", search_link: true)
  end

  def format_person_cluster_code(person)
    make_unit_code_display(person.cluster_code, not_set_text: "Nicht gesetzt", attribute: :cluster_code, search_link: true)
  end

  def format_person_status(person)
    Settings.status[person.status].presence || person.status
  end

  def format_person_sepa_status(person)
    Settings.sepa_status[person.sepa_status].presence || person.sepa_status
  end

  def format_person_active_total_fee_reduction(person)
    format_eur_with_hint_and_comment(
      person.active_total_fee_reduction,
      hint: person.active_total_fee_reduction_hint,
      comment: person.active_total_fee_reduction_comment
    )
  end

  def format_person_planned_total_fee_reduction(person)
    format_eur_with_hint_and_comment(
      person.planned_total_fee_reduction,
      hint: person.planned_total_fee_reduction_hint,
      comment: person.planned_total_fee_reduction_comment
    )
  end

  # An absent value means a withdrawal, so the page never shows an empty "Art".
  def format_person_deregistration_kind(person)
    I18n.t("people.deregistration_kinds.#{person.deregistration_kind_or_default}")
  end

  def deregistration_kind_options
    Person::DEREGISTRATION_KINDS.map { |kind| [kind, I18n.t("people.deregistration_kinds.#{kind}")] }
  end

  def format_person_deregistration_issue(person)
    auto_link_escaped_multiline(person.deregistration_issue) if person.deregistration_issue.present?
  end

  def format_person_debit_return_issue(person)
    auto_link_escaped_multiline(person.debit_return_issue) if person.debit_return_issue.present?
  end

  def format_person_deregistration_contractual_compensation_cents(person)
    format_cents_de(person.deregistration_contractual_compensation_cents, zero_cents: "")
  end

  # Which day the bracket was read for, said out loud: without a request date
  # the share follows the calendar, so the amount above changes from one day to
  # the next and the page has to say why.
  def deregistration_compensation_date_hint(person)
    date = l(person.deregistration_compensation_date)
    if person.deregistration_requested_date.present?
      "Berechnet zum #{date} (Abmeldung angefragt am)."
    else
      "Berechnet zum #{date} (heute)"
    end
  end

  # Why the Abmelde-Formular button is greyed out, one sentence per reason --
  # the same words next to the button, in its tooltip and in the flash a
  # request typed in by hand comes back with.
  def deregistration_form_unavailable_text(form)
    form.unavailable_reasons
      .map { |reason| t("people.deregistration_form.reasons.#{reason}") }
      .join(" ")
  end

  def format_person_deregistration_actual_compensation_cents(person)
    cents = person.deregistration_actual_compensation_cents
    if cents.present?
      eur = format_cents_de(person.deregistration_actual_compensation_cents, zero_cents: "")
      "#{eur} (Eingetragener Vorschlag)"
    else
      eur = format_cents_de(person.deregistration_contractual_compensation_cents, zero_cents: "")
      "#{eur} (nach Teilnahme- und Reisebedingungen)"
    end
  end

  # The sum behind what comes back or is still owed, in one muted line: paid
  # minus Einbehalt for a refund, Einbehalt minus paid for a claim. The
  # Einbehalt is a plain amount here; the rows above say where it comes from.
  def deregistration_settlement_formula(person)
    compensation_cents = person.deregistration_actual_compensation_cents ||
      person.deregistration_contractual_compensation_cents
    paid = "#{format_person_amount_paid_cents(person)} (bezahlt)"
    compensation = "#{format_cents_de(compensation_cents, zero_cents: "")} (Einbehalt)"
    if person.deregistration_open_cents > 0
      "= #{compensation} − #{paid}"
    else
      "= #{paid} − #{compensation}"
    end
  end

  # What the Abmelde-Formular will say, in the one line above its preview: who
  # signs it, the day the withdrawal takes effect, and whether it names the
  # compensation of section 7.2 T&R.
  def deregistration_form_facts(form)
    compensation = form.show_contractual_compensation? ? "compensation_named" : "compensation_not_named"
    [
      "#{t("people.deregistration_documents.signatures")}: #{form.contract_names.join(", ")}",
      "#{Person.human_attribute_name(:deregistration_effective_date)} #{form.cancellation_date_text}",
      t("people.deregistration_documents.#{compensation}")
    ].compact_blank.join(" · ")
  end

  # What the Moss receipt will say, in the one line above its preview: the amount
  # it pays back, the booking text Moss files it under, whether the explanation
  # paragraph is printed, and that a text of its own stands above it.
  def deregistration_receipt_facts(receipt)
    explanation = receipt.show_explanation? ? "explanation_printed" : "explanation_not_printed"
    facts = [receipt.amount_text, receipt.booking_text,
      t("people.deregistration_documents.#{explanation}")]
    facts << t("people.deregistration_documents.with_text") if receipt.greeting.present?
    facts.compact_blank.join(" · ")
  end

  # What one of the two document flags says on the read-only page.
  def deregistration_flag_text(shown)
    t("people.deregistration_form.#{shown ? "show" : "hide"}")
  end

  def format_person_deregistration_refund_cents(person)
    format_cents_de(person.deregistration_refund_cents, zero_cents: "")
  end

  def format_person_deregistration_open_cents(person)
    format_cents_de(person.deregistration_open_cents, zero_cents: "")
  end

  def format_person_amount_paid_cents(person)
    format_cents_de(person.amount_paid_cents, zero_cents: "")
  end

  def format_person_diet(person)
    Settings.diets[person.diet].presence || person.diet
  end

  private

  def format_email_or_nil(email_addr)
    mail_to(email_addr, email_addr) if email_addr.present?
  end

  def format_eur_with_hint_and_comment(eur, hint: nil, comment: nil, not_set_text: "Nicht gesetzt")
    if eur.nil?
      content_tag(:span, "Nicht gesetzt", class: "muted fw-light")
    else
      s = format_eur_de(eur)
      s = "#{s} (#{hint})" if hint.present?
      s
    end
  end
end
