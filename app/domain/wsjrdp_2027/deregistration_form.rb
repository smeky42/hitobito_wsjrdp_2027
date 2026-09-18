# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # The declaration a person signs to withdraw from the contract for the World
  # Scout Jamboree 2027: the wagon's copy of the scripts' Abmelde-Formular,
  # prefilled with what the Abmeldung page knows.
  #
  # What the page does not know stays a line to fill in by hand -- the day the
  # withdrawal takes effect, the bank account a refund goes to, and the two
  # amounts that follow from a compensation nobody has agreed on yet. Where
  # there is a compensation, the form states what comes back or what is still
  # open, and below it, in grey, the bracket of section 7.2 T&R.
  #
  # Everything the template receives is a String; an empty one is what the
  # template reads as "not known". See doc/typst_documents.md.
  class DeregistrationForm
    include ContractHelper

    TEMPLATE = "deregistration_form.typ"

    attr_reader :person

    # Whether the document states the bracket of section 7.2 T&R is the person's
    # own flag; a caller that says so outright decides for itself.
    def initialize(person, show_contractual_compensation: nil)
      @person = person
      @show_contractual_compensation = if show_contractual_compensation.nil?
        person.deregistration_form_show_contractual_compensation?
      else
        show_contractual_compensation
      end
    end

    def show_contractual_compensation? = @show_contractual_compensation

    def role = person.wsjrdp_role

    # The scripts' role_id_name: role, registration id and short name.
    def role_id_name = "#{role} #{person.id} #{person.short_full_name}"

    # Why the page offers no document, as keys the page puts into words: the
    # form is the person's own declaration of a withdrawal, so there is none
    # for a termination by the contingent -- and none before the day the
    # withdrawal takes effect is known, which the declaration names. Both can
    # apply at once.
    def unavailable_reasons
      reasons = []
      reasons << :termination if person.deregistration_termination?
      reasons << :no_effective_date if person.deregistration_effective_date.blank?
      reasons
    end

    def available? = unavailable_reasons.empty?

    # Who signs: the person, and the guardians where somebody signs with them.
    def contract_names = [person.full_name, *guardian_names]

    # Guardians sign for a youth participant and for anybody under 18 -- one of
    # them where only one was given, both otherwise.
    def guardian_names
      return [] unless person.yp? || minor?

      names = if person.additional_contact_single
        [person.additional_contact_name_a]
      else
        [person.additional_contact_name_a, person.additional_contact_name_b]
      end
      names.map(&:to_s).map(&:strip).compact_blank
    end

    # No birthday counts as not of legal age, the way the registration contract
    # reads it.
    def minor? = person.years.to_i < 18

    def birthday_text = date_text(person.birthday)

    def cancellation_date_text = date_text(person.deregistration_effective_date)

    def amount_paid_cents = person.amount_paid_cents

    def actual_compensation_cents = person.deregistration_actual_compensation_cents

    def contractual_compensation_cents
      show_contractual_compensation? ? person.deregistration_contractual_compensation_cents : nil
    end

    # What comes back, and what is still open: both follow from the
    # compensation that was agreed on, so without one the form leaves both
    # amounts to fill in.
    def refund_cents
      actual_compensation_cents.nil? ? nil : person.deregistration_refund_cents
    end

    def missing_cents
      actual_compensation_cents.nil? ? nil : person.deregistration_open_cents
    end

    def iban = SepaAccount.iban(person)

    def account_holder = SepaAccount.account_holder(person)

    def to_sys_inputs
      {
        role_id_name: role_id_name,
        hitobitoid: person.id,
        full_name: person.full_name,
        birthday_de: birthday_text,
        cancellation_date_de: cancellation_date_text,
        contract_names: contract_names.to_json,
        amount_paid_cents: amount_paid_cents,
        actual_compensation_cents: actual_compensation_cents,
        contractual_compensation_cents: contractual_compensation_cents,
        refund_amount_cents: refund_cents,
        missing_amount_cents: missing_cents,
        amount_paid_display: eur(amount_paid_cents),
        actual_compensation_display: eur(actual_compensation_cents),
        contractual_compensation_display: eur(contractual_compensation_cents),
        refund_amount_display: eur(refund_cents),
        missing_amount_display: eur(missing_cents),
        refund_iban: iban,
        refund_account_holder: account_holder
      }.transform_values(&:to_s)
    end

    def to_pdf = TypstDocument.compile_pdf(TEMPLATE, sys_inputs: to_sys_inputs)

    # The first page as a picture, for the preview on the Abmeldung page.
    def to_png(ppi: TypstDocument::THUMBNAIL_PPI)
      TypstDocument.compile_png(TEMPLATE, sys_inputs: to_sys_inputs, ppi: ppi)
    end

    def file_name
      TypstDocument.safe_file_name(
        "WSJ27 Abmeldung #{role} #{person.id} #{person.short_full_name}.pdf"
      )
    end

    private

    # The amount as the scripts write it: "1.600,— €" with a non-breaking
    # space before the euro sign, and ",—" for whole euros.
    def eur(cents) = cents.nil? ? "" : format_cents_de(cents, space: " ")

    def date_text(date) = date ? I18n.l(date) : ""
  end
end
