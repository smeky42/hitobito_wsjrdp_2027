# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # What a script reports once it has sent a person's Abmelde-Formular by
  # e-mail (POST /people/:id/deregistration/form_sent.json), and the three
  # traces the app leaves of it, in one transaction:
  #
  # - a person note ("Notizen"), written by the API key's acting person,
  # - a log entry: a wsjrdp_note of CATEGORY, the mail's data and the
  #   deregistration JSON the script built the mail from in wsjrdp_data,
  # - an element of the person's deregistration_form_mailings, naming the two.
  #
  # The person's own save writes no PaperTrail version: the log entry is the
  # change's record, and the list is no line of the log
  # (DeregistrationRecord::LOGGED_ATTRS).
  #
  # A mail is known by its Message-ID: a report of one already recorded
  # writes nothing and answers the element it left -- a script may report
  # again after a failed answer. doc/wsjrdp/deregistration.md has an example.
  class DeregistrationFormSent
    CATEGORY = "deregistration_form"
    LIST_KEYS = %w[email_to email_cc email_bcc].freeze

    class Invalid < StandardError; end

    attr_reader :person, :payload, :service_token, :mailing

    # payload: the parsed request body, a Hash with string keys.
    def initialize(person, payload, service_token:)
      @person = person
      @payload = payload.is_a?(Hash) ? payload.stringify_keys : {}
      @service_token = service_token
    end

    def duplicate? = @duplicate

    # Writes the three traces, or finds them for a Message-ID already
    # recorded. Raises Invalid with the reason for a report that cannot be
    # recorded.
    def save!
      validate!
      @mailing = person.deregistration_form_mailings.find { |m| m["email_message_id"] == message_id }
      @duplicate = @mailing.present?
      return self if @duplicate

      ActiveRecord::Base.transaction do
        note = Note.create!(subject: person, author: acting_person, text: note_text)
        version = Wsjrdp::LogEntry.note!(person, category: CATEGORY, message: log_message,
          data: log_data.merge("note_id" => note.id),
          whodunnit: service_token.id.to_s, whodunnit_type: service_token.class.sti_name,
          additional_info: {"script" => payload["script"].to_s.strip.presence}.compact)
        @mailing = mail_data.merge("form_created_date" => form_created_date.iso8601,
          "log_version_id" => version.id, "note_id" => note.id)
        person.deregistration_form_mailings = person.deregistration_form_mailings + [@mailing]
        # The mail is out already, so what it left must be written down even
        # where some other value of the person no longer passes validation.
        ::PaperTrail.request(enabled: false) { person.save!(validate: false) }
      end
      self
    end

    def message_id = payload["email_message_id"].to_s.strip

    def sent_at = @sent_at ||= Time.zone.iso8601(payload["email_sent_at"].to_s)

    def issue = person.deregistration_issue.presence

    def form_created_date = person.deregistration_form_created_date

    # "Abmelde-Formular am 15.11.2026 per E-Mail verschickt (HELP-123)"
    def note_text
      key = issue ? "note_with_issue" : "note"
      I18n.t("people.deregistration_form_mailing.#{key}", date: I18n.l(sent_at.to_date), issue: issue)
    end

    # "an max@…, erika@… · HELP-123": who it went to, Cc included.
    def log_message
      addresses = (list("email_to") + list("email_cc")).join(", ")
      key = issue ? "log_message_with_issue" : "log_message"
      I18n.t("people.deregistration_form_mailing.#{key}", addresses: addresses, issue: issue)
    end

    private

    def acting_person = service_token&.acting_person

    def validate!
      raise Invalid, "no API key" unless service_token
      raise Invalid, "the API key has no acting person" unless acting_person
      raise Invalid, I18n.t("people.deregistration_form.not_created") unless form_created_date
      raise Invalid, "email_message_id is missing" if message_id.blank?
      raise Invalid, "email_subject is missing" if payload["email_subject"].to_s.strip.blank?
      raise Invalid, "email_to is missing" if list("email_to").empty?
      LIST_KEYS.each do |key|
        value = payload[key]
        next if value.nil? || (value.is_a?(Array) && value.all? { |a| a.is_a?(String) })

        raise Invalid, "#{key} must be a list of addresses"
      end
      raise Invalid, "deregistration must be an object" unless payload["deregistration"].is_a?(Hash)

      sent_at
    rescue ArgumentError
      raise Invalid, "email_sent_at must be an ISO 8601 time"
    end

    def list(key) = Array(payload[key]).map { |address| address.to_s.strip }.compact_blank

    # What the element and the log entry share about the mail.
    def mail_data
      {
        "email_sent_at" => sent_at.iso8601,
        "email_to" => list("email_to"),
        "email_cc" => list("email_cc"),
        "email_bcc" => list("email_bcc"),
        "email_subject" => payload["email_subject"].to_s.strip,
        "email_message_id" => message_id
      }
    end

    def log_data
      mail_data.merge(
        "deregistration_issue" => issue,
        "form_created_date" => form_created_date.iso8601,
        "deregistration" => payload["deregistration"]
      )
    end
  end
end
