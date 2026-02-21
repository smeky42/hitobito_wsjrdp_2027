# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027::PeopleHelper
  include ContractHelper

  def person_accounting_path_with_group(group, person, params)
    person_accounting_path(person, params)
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

  def format_person_deregistration_issue(person)
    auto_link_escaped_multiline(person.deregistration_issue) if person.deregistration_issue.present?
  end

  def format_person_debit_return_issue(person)
    auto_link_escaped_multiline(person.debit_return_issue) if person.debit_return_issue.present?
  end

  def format_person_deregistration_contractual_compensation_cents(person)
    format_cents_de(person.deregistration_contractual_compensation_cents, zero_cents: "")
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
end
