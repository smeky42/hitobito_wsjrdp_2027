# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Credentials
  # "Verbindung testen" for one moss_api version on the account's page
  # (doc/wsjrdp/credentials.md, "Testing a Moss connection"): hands the
  # version's values to Wsjrdp::Moss::ConnectionCheck, writes the outcome to
  # the Hitobito log and, for a database version, to its health columns.
  class MossConnectionTest
    include Undumpable

    KIND = "moss_api"
    # The event in the log entry's payload (doc/wsjrdp/credentials.md, "The
    # log entries"), and the version of the payload's form.
    LOG_EVENT = "moss_connection_test"
    PAYLOAD_VERSION = 1
    TESTED_STATES = [Lookup::USABLE, WsjrdpCredential::NOT_YET_VALID].freeze

    # Why a version is not tested, as a code.
    class Refused < Error
      attr_reader :code

      def initialize(code)
        @code = code
        super("not tested: #{code}")
      end
    end

    # Whether the page offers the test for this version.
    def self.offered?(kind_name, version)
      kind_name == KIND && TESTED_STATES.include?(version.state) && !version.credential.nil?
    end

    def self.base_uri(credential) = URI.parse(credential[:base_url].to_s)

    def self.insecure?(credential) = base_uri(credential).scheme == "http"

    # Whether an http base_url needs the admin's confirmation first.
    def self.confirmation_needed?(credential, development: Rails.env.development?)
      insecure?(credential) && !development
    end

    # The log entries of one version's tests, newest first: by the row for a
    # database version, by the payload for an override.
    def self.log_entries(kind_name, account_key, version)
      entries = HitobitoLogEntry.where(category: LOG_CATEGORY).where("payload->>'event' = ?", LOG_EVENT)
        .order(created_at: :desc, id: :desc)
      return entries.where(subject: version.record) if version.record

      entries.where(subject_id: nil)
        .where("payload->'account'->>'kind' = ? AND payload->'account'->>'account_key' = ? " \
               "AND payload->'account'->>'source' = ? AND payload->'account'->>'position' = ?",
          kind_name, account_key, version.source, version.position.to_s)
    end

    attr_reader :version

    # actor: the person who tests, for the log.
    def initialize(report, source:, id: nil, position: nil, confirmed: false, actor: nil,
      check: Wsjrdp::Moss::ConnectionCheck, development: Rails.env.development?)
      @report = report
      @actor = actor
      @confirmed = confirmed
      @check = check
      @development = development
      @version = report.versions.find do |version|
        version.source == source && (version.record ? version.id == id : version.position == position)
      end
      freeze
    end

    # The check's result; raises Refused.
    def call
      raise Refused.new(:not_found) unless version
      raise Refused.new(:not_offered) unless self.class.offered?(@report.kind, version)

      credential = version.credential
      if self.class.confirmation_needed?(credential, development: @development) && !@confirmed
        raise Refused.new(:not_confirmed)
      end

      result = @check.new(base_url: credential[:base_url], client_id: credential[:client_id],
        client_secret: credential.secret(:client_secret), scope: credential[:scope]).call
      record(result)
      log(result, insecure: self.class.insecure?(credential))
      result
    end

    def inspect = "#<#{self.class.name} #{version.inspect}>"
    alias_method :to_s, :inspect

    def as_json(*) = {"version" => version&.as_json}

    private

    # One entry in the Hitobito log; never a value of the version.
    def log(result, insecure:)
      HitobitoLogEntry.create!(category: LOG_CATEGORY, level: result.ok? ? "info" : "warn",
        subject: version.record, message: log_message(result), payload: log_payload(result, insecure))
    end

    def log_message(result)
      scope = "credentials.connection_test.log"
      account = "#{@report.kind}/#{@report.account_key}"
      if result.ok?
        I18n.t("#{scope}.ok", account: account)
      else
        I18n.t("#{scope}.failed", account: account, step: I18n.t("credentials.connection_test.steps.#{result.step}"),
          message: result.message)
      end
    end

    # The keys every entry of the category has (event, payload_version,
    # account, person_id), then this event's own: outcome and requests.
    def log_payload(result, insecure)
      {event: LOG_EVENT, payload_version: PAYLOAD_VERSION,
       account: {kind: @report.kind, account_key: @report.account_key, source: version.source,
                 version_id: version.id, position: version.position},
       person_id: @actor&.id,
       outcome: {ok: result.ok?, step: result.step, status: result.status, message: result.message,
                 tracing_id: result.tracing_id, scope: result.scope, host: result.host, insecure: insecure,
                 duration_ms: result.duration_ms}.compact,
       requests: result.exchanges.map(&:for_log)}
    end

    # The health columns, without touching updated_at: an open edit form
    # stays valid.
    def record(result)
      row = version.record
      return unless row

      if result.ok?
        row.update_columns(last_success_at: Time.current)
      else
        row.update_columns(last_failure_at: Time.current, last_failure_message: result.message.to_s.truncate(500))
      end
    end
  end
end
