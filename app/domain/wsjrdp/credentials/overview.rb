# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Credentials
  # What every source holds, for the pages (doc/wsjrdp/credentials.md,
  # "For the pages"): per account the versions of the variables, the
  # local file and the database with their states, the source in use, the
  # active version and its fallbacks; besides, what became of the local
  # file, where the keys came from, and every key by fingerprint, those of
  # other stages included.
  #
  #   overview = Wsjrdp::Credentials::Overview.new
  #   report = overview.account(:moss_api, "default")
  #   report.in_use                                   # => "file"
  #   report.versions.map { |v| [v.source, v.state, v.role, v.overridden_by] }
  #
  # A value is reachable only through a version's credential, the same
  # Credential the lookup hands out. No report holds a key, and no report
  # prints a version's name, a comment or a value.
  class Overview
    include Undumpable

    ACTIVE = :active
    FALLBACK = :fallback
    ACCEPTED = :accepted
    OTHER_STAGE = :other_stage

    # One version of one source. role: ACTIVE, FALLBACK, or nil (not usable,
    # or its source is not in use); overridden_by: the source in use when it
    # is another one. position is an override's, id and record a row's.
    VersionReport = Data.define(:source, :state, :role, :overridden_by, :name, :created_at, :valid_from,
      :expires_at, :position, :id, :credential, :errors, :warnings, :record) do
      include Undumpable

      def inspect
        parts = [source, state, role && "role=#{role}", overridden_by && "overridden_by=#{overridden_by}",
          position && "position=#{position}", id && "id=#{id}"].compact
        "#<#{self.class.name} #{parts.join(" ")}>"
      end
      alias_method :to_s, :inspect

      def as_json(*)
        {"source" => source, "state" => state.to_s, "role" => role&.to_s, "overridden_by" => overridden_by,
         "position" => position, "id" => id}
      end
    end

    SourceReport = Data.define(:source, :names_account, :in_use, :versions) do
      include Undumpable

      def inspect
        "#<#{self.class.name} #{source}#{" names_account" if names_account}#{" in_use" if in_use} " \
          "versions=#{versions.size}>"
      end
      alias_method :to_s, :inspect

      def as_json(*)
        {"source" => source, "names_account" => names_account, "in_use" => in_use,
         "versions" => versions.map(&:as_json)}
      end
    end

    # One account. The database names every account, so in_use is nil only
    # for a report made by hand.
    AccountReport = Data.define(:kind, :account_key, :in_use, :sources) do
      include Undumpable

      def versions = sources.flat_map(&:versions)

      # The sources below the one in use that name the account.
      def overridden_sources = sources.select { |source| source.names_account && !source.in_use }.map(&:source)

      def inspect
        counts = sources.map { |source| "#{source.source}=#{source.versions.size}" }.join(",")
        "#<#{self.class.name} #{shown_account} in_use=#{in_use} versions=#{counts}>"
      end
      alias_method :to_s, :inspect

      def as_json(*)
        {"kind" => Wsjrdp::Credentials.shown_name(kind), "account_key" => Wsjrdp::Credentials.shown_account_key(account_key),
         "in_use" => in_use, "sources" => sources.map(&:as_json)}
      end

      private

      def shown_account = "#{Wsjrdp::Credentials.shown_name(kind)}/#{Wsjrdp::Credentials.shown_account_key(account_key)}"
    end

    # What became of the local file, without its keys.
    FileReport = Data.define(:status, :source, :file_stage) do
      include Undumpable

      def inspect = "#<#{self.class.name} #{status}>"
      alias_method :to_s, :inspect

      def as_json(*) = {"status" => status.to_s, "source" => source, "file_stage" => file_stage}
    end

    # One key as the pages list it: its stage (nil where it may not be
    # shown), its fingerprint and its role here.
    KeyEntry = Data.define(:stage, :fingerprint, :role) do
      include Undumpable

      def inspect = "#<#{self.class.name} #{Wsjrdp::Credentials.shown_stage(stage)} #{fingerprint} #{role}>"
      alias_method :to_s, :inspect

      def as_json(*) = {"stage" => stage, "fingerprint" => fingerprint, "role" => role.to_s}
    end

    # Where the keys came from, and their label; keys by fingerprint only.
    # fingerprints are the keys accepted here; entries lists every key, this
    # stage's first (the active one first), then those of other stages.
    KeyReport = Data.define(:source, :label, :stage, :active_fingerprint, :fingerprints, :entries) do
      include Undumpable

      def inspect
        "#<#{self.class.name} #{source} active=#{active_fingerprint} accepted=#{fingerprints.join(",")} " \
          "other_stages=#{entries.count { |entry| entry.role == OTHER_STAGE }}>"
      end
      alias_method :to_s, :inspect

      def as_json(*)
        {"source" => source, "label" => label, "stage" => Wsjrdp::Credentials.shown_stage(stage),
         "active_fingerprint" => active_fingerprint, "fingerprints" => fingerprints,
         "entries" => entries.map(&:as_json)}
      end
    end

    attr_reader :at

    def initialize(overrides: Overrides.current, keys: Keys.current, kinds: Kinds.current, at: Time.current)
      @overrides = overrides
      @keys = keys
      @kinds = kinds
      @at = at
      freeze
    end

    def file
      local = overrides.file
      # nil where the file names no stage that may be shown.
      file_stage = local.file_stage && Wsjrdp::Credentials.shown_stage(local.file_stage, placeholder: nil)
      FileReport.new(status: local.status, source: local.source, file_stage: file_stage)
    end

    def keys
      own_stage = Wsjrdp::Credentials.shown_stage(stage, placeholder: nil)
      own = @keys.keys.map do |key|
        KeyEntry.new(stage: own_stage, fingerprint: key.fingerprint, role: (key == @keys.active) ? ACTIVE : ACCEPTED)
      end
      others = @keys.other_stage_keys.map do |key|
        KeyEntry.new(stage: key.stage, fingerprint: key.fingerprint, role: OTHER_STAGE)
      end
      KeyReport.new(source: @keys.source, label: @keys.label, stage: stage,
        active_fingerprint: @keys.active&.fingerprint, fingerprints: @keys.keys.map(&:fingerprint),
        entries: own + others)
    end

    def stage = @keys.stage

    def account(kind, account_key)
      kind = kind.to_s
      account_key = Wsjrdp::Credentials.account_key_of(account_key.to_s)
      overrides_reports = overrides.sources.map { |source| override_source(source, kind, account_key) }
      database = database_source(kind, account_key)
      reports = overrides_reports + [database]
      in_use = reports.find(&:names_account)&.source
      AccountReport.new(kind: kind, account_key: account_key, in_use: in_use,
        sources: reports.map { |report| finish(report, in_use) })
    end

    # Every account any source names, rows of every stage included.
    def accounts = account_names.map { |kind, account_key| account(kind, account_key) }

    # A variable names an account by its part (FOO_EXAMPLE_ORG): it is
    # listed under the key of the file or the database that maps to it,
    # and under the part in lower case only where none does.
    def account_names
      named = overrides.file.account_names + WsjrdpCredential.distinct.pluck(:kind, :account_key)
      parts = named.filter_map do |kind, account_key|
        [kind, Variables.account_part(account_key).downcase] if Wsjrdp::Credentials.account_key?(account_key)
      end
      names = overrides.variables.account_names.reject { |pair| parts.include?(pair) } + named
      names.uniq.sort_by { |kind, account_key| [kind.to_s, account_key.to_s] }
    end

    def inspect = "#<#{self.class.name} stage=#{Wsjrdp::Credentials.shown_stage(stage)} file=#{file.status}>"
    alias_method :to_s, :inspect

    def as_json(*) = {"stage" => Wsjrdp::Credentials.shown_stage(stage), "file" => file.as_json, "keys" => keys.as_json}

    private

    attr_reader :overrides, :kinds

    def override_source(source, kind, account_key)
      account = source.account(kind, account_key)
      unless account
        return SourceReport.new(source: source.source_name, names_account: false, in_use: false, versions: [])
      end

      versions = account.examine(at: at, stage: stage).map do |examination|
        version = examination.version
        VersionReport.new(source: source.source_name, state: examination.state, role: nil, overridden_by: nil,
          name: version.name, created_at: version.created_at, valid_from: version.valid_from,
          expires_at: version.expires_at, position: version.position, id: nil, credential: examination.credential,
          errors: examination.errors, warnings: examination.warnings, record: nil)
      end
      SourceReport.new(source: source.source_name, names_account: true, in_use: false, versions: versions)
    end

    def database_source(kind, account_key)
      versions = WsjrdpCredential.of_account(kind, account_key).newest_first.map do |row|
        examination = row.examine(at: at, keys: @keys, kinds: kinds)
        VersionReport.new(source: DatabaseSource::NAME, state: examination.state, role: nil, overridden_by: nil,
          name: row.name, created_at: row.created_at, valid_from: row.valid_from, expires_at: row.expires_at,
          position: nil, id: row.id, credential: examination.credential, errors: [], warnings: examination.warnings,
          record: row)
      end
      SourceReport.new(source: DatabaseSource::NAME, names_account: true, in_use: false, versions: versions)
    end

    # Gives the source in use its roles and marks every other source as
    # overridden by it.
    def finish(report, in_use)
      using = report.source == in_use
      seen_usable = false
      versions = report.versions.map do |version|
        next version.with(overridden_by: in_use) unless using
        next version unless version.state == Lookup::USABLE

        role = seen_usable ? FALLBACK : ACTIVE
        seen_usable = true
        version.with(role: role)
      end
      report.with(in_use: using, versions: versions)
    end
  end
end
