# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # What a script reports once it has sent a person's Abmelde-Formular by
  # e-mail (POST /people/:id/deregistration/form_sent.json), and the traces
  # the app leaves of it, in one transaction:
  #
  # - a person note ("Notizen"), written by the API key's acting person,
  # - a log entry: a wsjrdp_note of CATEGORY, the mail's data and the
  #   deregistration JSON the script built the mail from in wsjrdp_data,
  # - an event of the deregistration (notify, action form_sent) holding the
  #   mail and naming the two -- what deregistration_form_mailings reads,
  # - with the first mail: the row's form_sent_at and its status form_sent;
  #   the form as sent is the one prepare_form.json or "PDF erzeugen" kept
  #   (DeregistrationFormDocument); a report while there is none is refused
  #   (form_document_missing), nothing is kept here. From then on what the
  #   form says is fixed
  #   (WsjrdpDeregistration::FIXED_ATTRS).
  #
  # The row's save writes no PaperTrail version: the log entry is the
  # change's record.
  #
  # The report names the deregistration it was built from
  # (deregistration.deregistration_id); one for another version is refused.
  #
  # A mail is known by its Message-ID: a report of one already recorded
  # writes nothing and answers the element it left -- a script may report
  # again after a failed answer. doc/wsjrdp/deregistration.md has an example.
  class DeregistrationFormSent
    CATEGORY = "deregistration_form"
    # The slot of a mail the form went out with, as an EML (the report's
    # email_eml_base64): secondary key form_mail, numbered per mail.
    FORM_MAIL_SECONDARY_KEY = "form_mail"
    LIST_KEYS = %w[email_to email_cc email_bcc].freeze

    # A report that cannot be recorded: the reason, a code for the script and
    # the HTTP status the answer carries -- 409 where the deregistration is not
    # in the state the report needs, 422 where the report itself is wanting.
    class Invalid < StandardError
      attr_reader :code, :status

      def initialize(message, code: "invalid_report", status: :unprocessable_entity)
        super(message)
        @code = code
        @status = status
      end
    end

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
      # One report of a row at a time: the slot of the mail's EML follows
      # from the mails recorded so far, so a second report waits for the
      # first to be written down (#with_report_lock).
      self.class.with_report_lock(row) do
        # Read the row anew (its events too): a report this one waited for
        # may have recorded a mail and marked the form sent meanwhile.
        row.reload
        @mailing = recorded_mailings.find { |m| m["email_message_id"] == message_id }
        @duplicate = @mailing.present?
        next if @duplicate

        # A mail recorded already is answered as it was, whatever became of
        # the form since; a new one needs the kept form.
        validate_form_document!
        record!
      end
      row.events.reset
      self
    end

    # What kind of mail it is: the event's action and the log entry's
    # category. A subclass reports another mail (DeregistrationConfirmationSent).
    def action = WsjrdpDeregistration::FORM_SENT_ACTION

    def category = CATEGORY

    # The form's mails write a person note; the confirmation script writes
    # its own.
    def person_note? = true

    # The slot the mail's EML is kept in: deregistration <number>,
    # <mail_secondary_key> <n> -- the n-th mail of its kind.
    def mail_secondary_key = FORM_MAIL_SECONDARY_KEY

    # The mails of this kind recorded already, oldest first.
    def recorded_mailings
      return [] if row.nil?

      row.events.select { |e| e.event == "notify" && e.action == action }.map { |e| e.additional_info.to_h }
    end

    def row = @row ||= person.deregistration

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

    # How long a report (or a discard of the form) waits for another one of
    # the same row.
    REPORT_LOCK_TIMEOUT = 8.seconds

    # Runs the block under the lock of the row's reports: an advisory lock of
    # the session (Wsjrdp::SessionLock) -- not one of a transaction, since
    # the block writes documents, each a locked change of its own. The
    # reports of a row and a discard of its form ("Formular verwerfen") take
    # it, so a discard never sees the form unsent while a report records it.
    # Raises Wsjrdp::LockedChange::Busy when somebody else holds it longer
    # than REPORT_LOCK_TIMEOUT. Without a row there is nothing to lock.
    def self.with_report_lock(row, &)
      return yield if row.nil? || row.new_record?

      Wsjrdp::SessionLock.hold(report_lock_key(row), timeout: REPORT_LOCK_TIMEOUT, &)
    end

    def self.report_lock_key(row) = "deregistration_report:#{row.id}"

    private

    def acting_person = service_token&.acting_person

    def record!
      # The mail itself as it went out: a locked change of its own, so before
      # the transaction that names it.
      eml_document = store_eml!
      ActiveRecord::Base.transaction do
        note = Note.create!(subject: person, author: acting_person, text: note_text) if person_note?
        version = Wsjrdp::LogEntry.note!(person, category: category, message: log_message,
          data: log_data.merge("note_id" => note&.id, "eml_document_id" => eml_document&.id).compact,
          whodunnit: service_token.id.to_s, whodunnit_type: service_token.class.sti_name,
          additional_info: {"script" => payload["script"].to_s.strip.presence}.compact)
        @mailing = mail_data.merge("form_created_date" => form_created_date&.iso8601,
          "log_version_id" => version.id, "note_id" => note&.id, "eml_document_id" => eml_document&.id).compact
        WsjrdpDeregistrationEvent.create!(deregistration: row, event: "notify",
          action: action, occurred_at: sent_at,
          actor_type: service_token.class.sti_name, actor_id: service_token.id, additional_info: @mailing)
        recorded!
      end
      after_recorded!
    end

    # The mail as it went out (email_eml_base64, optional), kept as a document
    # of the row: deregistration <number>, mail_secondary_key <n> for the n-th
    # mail of this kind; nil without one. An EML left in that slot by a report
    # whose recording failed afterwards is replaced, so the report can be
    # sent again.
    def store_eml!
      return nil if eml.nil?

      number = recorded_mailings.size + 1
      left = WsjrdpDocument.current_for(person, key: "deregistration", key_number: row.number,
        secondary_key: mail_secondary_key, secondary_key_number: number)
      Wsjrdp2027::DocumentStore.store!(StringIO.new(eml),
        {subject: person, key: "deregistration", key_number: row.number, key_ref: row, replaces: left,
         secondary_key: mail_secondary_key, secondary_key_number: number,
         filename: Wsjrdp2027::TypstDocument.safe_file_name("#{payload["email_subject"].to_s.strip}.eml"),
         author: acting_person, origin: "api", origin_service_token: service_token},
        upload: false)
    end

    # The EML the report carries, decoded; nil without one.
    def eml
      return @eml if defined?(@eml)

      encoded = payload["email_eml_base64"].to_s
      @eml = encoded.empty? ? nil : Base64.strict_decode64(encoded)
    end

    # The Message-ID header of the EML, from its header block.
    def eml_message_id
      header = eml.to_s.split(/\r?\n\r?\n/, 2).first.to_s.gsub(/\r?\n[ \t]+/, " ")
      header[/^Message-ID:[ \t]*(\S+)/i, 1]
    end

    # The first mail fixes the form (#mark_sent!).
    def recorded!
      mark_sent! if row.form_sent_at.nil?
    end

    def after_recorded!
    end

    # The form must be made before it goes out.
    def form_required? = true

    # The form the mail carried is the stored one (prepare_form.json, "PDF
    # erzeugen"): the one the report names (deregistration.form.document_id),
    # which must be the row's and be there -- before the first mail the
    # current version of its slot, after it the one sent. Nothing is kept
    # here: a report without it is refused.
    def validate_form_document!
      return unless form_required?
      # A form that went out before forms were kept (a row migrated from
      # people.additional_info) has no document: its further mails are
      # recorded all the same. Any other sent row without its document is
      # refused below.
      return if row.form_sent_at && row.sent_form_document_id.nil? && row.migrated?

      form = payload["deregistration"]["form"]
      reported = form["document_id"] if form.is_a?(Hash)
      unless DeregistrationFormDocument.usable(row.sent_form_document, current: row.form_sent_at.nil?)
        raise Invalid.new(I18n.t("people.deregistration_form.document_missing",
          id: reported.presence || row.sent_form_document_id || "–"), code: "form_document_missing", status: :conflict)
      end
      return if reported.blank? || reported.to_s == row.sent_form_document_id.to_s

      raise Invalid.new("the report names form document #{reported.inspect}, the deregistration's is " \
        "#{row.sent_form_document_id.inspect}", code: "other_form_document", status: :conflict)
    end

    # The first mail fixes the form: the row is marked sent. The mail is out
    # already, so this is written down even where another value of the row no
    # longer passes validation.
    def mark_sent!
      row.form_sent_at = sent_at
      row.status = "form_sent" if %w[recorded form_created].include?(row.status)
      ::PaperTrail.request(enabled: false) { row.save!(validate: false) }
    end

    def validate!
      raise Invalid.new("no API key", code: "no_api_key", status: :forbidden) unless service_token
      raise Invalid.new("the API key has no acting person", code: "no_acting_person") unless acting_person
      raise Invalid.new("no deregistration is recorded", code: "no_deregistration", status: :conflict) unless row
      if form_required? && !form_created_date
        raise Invalid.new(I18n.t("people.deregistration_form.not_created"), code: "form_not_created", status: :conflict)
      end
      reported = payload["deregistration"].is_a?(Hash) ? payload["deregistration"]["deregistration_id"] : nil
      unless reported.to_s == row.id.to_s
        raise Invalid.new("the report is for deregistration #{reported.inspect}, the current one is #{row.id}",
          code: "other_deregistration", status: :conflict)
      end
      raise Invalid, "email_message_id is missing" if message_id.blank?
      raise Invalid, "email_subject is missing" if payload["email_subject"].to_s.strip.blank?
      raise Invalid, "email_to is missing" if list("email_to").empty?
      LIST_KEYS.each do |key|
        value = payload[key]
        next if value.nil? || (value.is_a?(Array) && value.all? { |a| a.is_a?(String) })

        raise Invalid, "#{key} must be a list of addresses"
      end
      raise Invalid, "deregistration must be an object" unless payload["deregistration"].is_a?(Hash)
      validate_eml!

      sent_at
    rescue ArgumentError
      raise Invalid.new("email_sent_at must be an ISO 8601 time")
    end

    # An EML that comes along must decode and be the mail reported.
    def validate_eml!
      return if eml.nil?
      return if eml_message_id == message_id

      raise Invalid.new("the EML's Message-ID #{eml_message_id.inspect} is not email_message_id #{message_id.inspect}")
    rescue ArgumentError
      raise Invalid.new("email_eml_base64 is no Base64")
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
        "form_created_date" => form_created_date&.iso8601,
        "deregistration" => payload["deregistration"]
      )
    end
  end
end
