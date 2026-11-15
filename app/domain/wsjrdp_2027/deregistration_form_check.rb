# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # Whether the Abmelde-Formular can go out as it stands, all at once:
  #
  # - errors -- the form would not be complete, or there is none: no form for
  #   the kind or without a day (DeregistrationForm#unavailable_reasons), no
  #   agreed compensation (the form then leaves the refund, the claim and the
  #   account to be filled in by hand), no birthday, no account for a refund.
  #   prepare_form.json changes nothing while there is one.
  # - warnings -- worth a second look, not in the way: no helpdesk ticket (the
  #   mail lands in no ticket), the form's deadline is over, the form went out
  #   before, nobody signs for a minor.
  #
  # Each is {"code" => ..., "message" => ...}: the code for a script to act
  # on, the message in the words of the page (people.deregistration_check).
  class DeregistrationFormCheck
    attr_reader :person

    def initialize(person, today: Date.current)
      @person = person
      @today = today
    end

    def form = @form ||= DeregistrationForm.new(person)

    def errors
      codes = form.unavailable_reasons.map { |reason| :"unavailable_#{reason}" }
      codes << :no_compensation if person.deregistration_actual_compensation_cents.nil?
      codes << :no_birthday if person.birthday.blank?
      codes << :no_refund_account if refund? && (form.iban.blank? || form.account_holder.blank?)
      codes.map { |code| entry(code) }
    end

    def warnings
      codes = []
      codes << [:no_issue, {}] if person.deregistration_issue.blank?
      if form.created? && form.reply_due_date < @today
        codes << [:deadline_over, {date: I18n.l(form.reply_due_date)}]
      end
      person.deregistration_form_mailings.each do |mailing|
        codes << [:sent_before, {date: mailing_date(mailing), addresses: Array(mailing["email_to"]).join(", ")}]
      end
      codes << [:no_guardian, {}] if (person.yp? || form.minor?) && form.guardian_names.empty?
      codes.map { |code, args| entry(code, **args) }
    end

    def errors? = errors.any?

    def as_json(*) = {"errors" => errors, "warnings" => warnings}

    private

    # Whether the form names a refund: the agreed compensation leaves money to
    # pay back.
    def refund? = !person.deregistration_actual_compensation_cents.nil? && person.deregistration_refund_cents.positive?

    def mailing_date(mailing)
      I18n.l(Time.zone.iso8601(mailing["email_sent_at"].to_s).to_date)
    rescue ArgumentError
      mailing["email_sent_at"].to_s
    end

    def entry(code, **args)
      {"code" => code.to_s, "message" => I18n.t("people.deregistration_check.#{code}", **args)}
    end
  end
end
