# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # A person's deregistration as the scripts read it
  # (GET /people/:id/deregistration.json): what the Abmelde-Formular says and
  # what the mail that carries it needs, so the script builds that mail from
  # the same values the form was made of. doc/wsjrdp/deregistration.md lists
  # the keys.
  class DeregistrationState
    attr_reader :person

    def initialize(person)
      @person = person
    end

    def form = @form ||= DeregistrationForm.new(person)

    def recipients = @recipients ||= DeregistrationMailRecipients.new(person, role: form.role)

    # Why there is no form, in the words the page uses; nil where there is one.
    def not_available_reason
      return nil if form.available?

      form.unavailable_reasons.map { |reason| I18n.t("people.deregistration_form.reasons.#{reason}") }.join(" ")
    end

    def as_json(*)
      {
        "person_id" => person.id,
        "kind" => person.deregistration_kind_or_default,
        "available" => form.available?,
        "not_available_reason" => not_available_reason,
        "issue" => person.deregistration_issue.presence,
        "status" => person.status,
        "contract_status" => person.contract_status,
        "role_id_name" => form.role_id_name,
        "birthday" => person.birthday&.iso8601,
        "deregistration_requested_date" => person.deregistration_requested_date&.iso8601,
        "deregistration_effective_date" => person.deregistration_effective_date&.iso8601,
        "contract_names" => form.contract_names,
        "amounts" => amounts,
        "form" => {
          "created_date" => person.deregistration_form_created_date&.iso8601,
          "reply_due_date" => form.reply_due_date&.iso8601,
          "file_name" => form.file_name,
          # The account a refund goes to, as the form prints it: captured when
          # it was made, the person's bank data before.
          "refund_iban" => form.iban.presence,
          "refund_account_holder" => form.account_holder.presence,
          "show_contractual_compensation" => form.show_contractual_compensation?
        },
        "mail" => recipients.as_json,
        "form_mailings" => person.deregistration_form_mailings
      }
    end

    # The person's amounts under their Rails names, in euros: one currency for
    # all of them, the ledger currency (base_currency, doc/fin/money_conventions.md
    # R1). The compensation is the one the form and the page read -- for the
    # day the deregistration was requested.
    def amounts
      {
        "base_currency" => "EUR",
        "regular_full_fee" => eur(person.regular_full_fee_cents),
        "total_fee_reduction" => eur((person.active_total_fee_reduction * 100).round),
        "total_fee" => eur(person.total_fee_cents),
        "amount_paid" => eur(person.amount_paid_cents),
        "deregistration_contractual_compensation" => eur(person.deregistration_contractual_compensation_cents),
        "deregistration_actual_compensation" => eur(person.deregistration_actual_compensation_cents),
        "deregistration_refund" => eur(person.deregistration_refund_cents),
        "deregistration_open" => eur(person.deregistration_open_cents)
      }
    end

    private

    # Cents as a JSON number of euros: whole euros as an Integer, others as a
    # Float -- read from the cents, so exact to the cent; nil stays nil.
    def eur(cents)
      return nil if cents.nil?

      (cents % 100).zero? ? cents / 100 : cents / 100.0
    end
  end
end
