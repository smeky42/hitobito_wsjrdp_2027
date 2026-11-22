# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Credentials
  # What the two overrides (Variables and LocalFile) share: an account with
  # its versions, the choice of the version to use, and the reader of one
  # version (doc/wsjrdp/credentials.md, "Overrides").
  #
  # An override's values are plain text in memory; nothing is sealed, and a
  # version has no row, no id and no key. A field the kind does not have is
  # a further field, and public.
  class Override
    # The states of a version, in the order they are checked.
    REFUSED = :refused
    KIND_MISMATCH = :kind_mismatch
    EXPIRED = :expired
    NOT_YET_VALID = :not_yet_valid
    ACTIVE = Lookup::USABLE

    BY_CREATED_AT = :created_at
    BY_LIST = :list

    VERSION_KEYS = [*Kinds::RESERVED_FIELD_NAMES, "vars"].freeze
    INSTANTS = %w[created_at valid_from expires_at].freeze
    FURTHER_NAME_MESSAGES = {not_a_name: "the field is not lower-case snake of at most #{NAME_LENGTH} characters",
                             reserved: "the field name is reserved"}.freeze

    # One version as given. The values are handed out only through
    # #given_values; inspect and as_json show field names and instants,
    # never a value or the name (free text).
    class Version
      include Undumpable

      attr_reader :position, :name, :created_at, :valid_from, :expires_at

      def initialize(position:, values:, name: nil, created_at: nil, valid_from: nil, expires_at: nil)
        raise ArgumentError, "the values are not a hash" unless values.is_a?(Hash)

        @position = position
        @values = values.dup.freeze
        @name = name&.dup&.freeze
        @created_at = created_at
        @valid_from = valid_from
        @expires_at = expires_at
        freeze
      end

      # For Kind#cast.
      def given_values = @values

      def field_names = @values.keys.map { |name| Wsjrdp::Credentials.shown_name(name) }

      def inspect
        instants = instants_shown.filter_map { |attribute, time| "#{attribute}=#{time}" if time }
        ["#<#{self.class.name} #{position}", "fields=#{field_names.join(",")}", *instants].join(" ") + ">"
      end
      alias_method :to_s, :inspect

      def as_json(*)
        {"position" => position, "fields" => field_names}.merge(instants_shown)
      end

      private

      def instants_shown
        INSTANTS.to_h { |attribute| [attribute, public_send(attribute)&.getutc&.strftime("%FT%T%:z")] }
      end
    end

    # One version at an instant: its state, the Credential when its values
    # fit the kind (for an expired or planned version too, never for a
    # refused one: its broken part was dropped), and the errors and warnings
    # of the cast.
    Examination = Data.define(:version, :state, :credential, :errors, :warnings)

    # Reads one version from the shape both overrides give:
    # {"name", "created_at", "valid_from", "expires_at", "vars"}. Each
    # problem is yielded as (key, message): key is the part of the version
    # ("expires_at", "vars", "vars.<field>"), or nil for the version as a
    # whole; the caller turns it into its own place (a variable, a path in
    # the file). Messages never hold a value. Gives the Version, without the
    # parts that were wrong.
    def self.read_version(raw, kind:, position:)
      (raw.keys - VERSION_KEYS).each { |key| yield nil, "unknown key #{Wsjrdp::Credentials.shown_name(key)}" }
      instants = INSTANTS.to_h do |key|
        [key.to_sym, Wsjrdp::InstantInput.parse(raw[key])]
      rescue Wsjrdp::InstantInput::Invalid => e
        yield key, e.message
        [key.to_sym, nil]
      end
      valid_from, expires_at = instants.values_at(:valid_from, :expires_at)
      yield "expires_at", "is not after valid_from" if valid_from && expires_at && expires_at <= valid_from

      name = raw["name"]
      unless name.nil? || Wsjrdp::Credentials.text?(name)
        yield "name", name.is_a?(String) ? "is not valid text" : "is not a text"
        name = nil
      end

      vars = raw["vars"]
      unless vars.is_a?(Hash)
        yield "vars", vars.nil? ? "is missing" : "is not a mapping"
        vars = {}
      end
      # A field the kind does not have is a further field, always public.
      vars.each_key do |field|
        next if Wsjrdp::Credentials.name?(field) && kind.field?(field)

        code = kind.further_name_problem(field)
        next unless code

        yield "vars.#{Wsjrdp::Credentials.shown_name(field)}", FURTHER_NAME_MESSAGES.fetch(code)
      end

      Version.new(position: position, values: vars, name: (name == "") ? nil : name, **instants)
    end

    # One account of an override. Its versions are ordered by created_at
    # (BY_CREATED_AT, when every version states it) or by the list (BY_LIST).
    # A refused account still answers for the account, but none of its
    # versions is usable: a broken override must neither be used without
    # the part that was wrong nor fall back to the database.
    class Account
      attr_reader :kind, :account_key, :versions, :order

      def initialize(kind:, account_key:, versions:, order: BY_LIST, refused: false)
        @kind = kind
        @account_key = account_key
        @versions = versions.dup.freeze
        @order = order
        @refused = refused
        freeze
      end

      def refused? = @refused

      # The same account under the key it was asked for (a variable names
      # every key that maps to its account part).
      def for_key(key)
        return self if key == account_key

        self.class.new(kind: kind, account_key: key, versions: versions, order: order, refused: refused?)
      end

      def kind_name = kind.name

      # Newest first; versions of the same created_at keep the list's order.
      def ordered_versions
        return versions if order == BY_LIST

        versions.each_with_index.sort_by { |version, index| [-version.created_at.to_r, index] }.map(&:first)
      end

      def examine(at:, stage:)
        ordered_versions.map { |version| examine_version(version, at, stage) }
      end

      def answer(at:, stage:, source:)
        Lookup::Answer.of(source: source, stage: stage, examinations: examine(at: at, stage: stage))
      end

      def inspect = "#<#{self.class.name} #{kind_name}/#{account_key} versions=#{versions.size}#{" refused" if refused?}>"
      alias_method :to_s, :inspect

      private

      def examine_version(version, at, stage)
        cast = kind.cast(version.given_values, stage: stage)
        credential = (cast.valid? && !refused?) ? credential_of(version, cast, stage) : nil
        Examination.new(version: version, state: state_of(version, cast, at), credential: credential,
          errors: cast.errors, warnings: cast.warnings)
      end

      def state_of(version, cast, at)
        if refused? then REFUSED
        elsif !cast.valid? then KIND_MISMATCH
        elsif version.expires_at && version.expires_at <= at then EXPIRED
        elsif version.valid_from && version.valid_from > at then NOT_YET_VALID
        else
          ACTIVE
        end
      end

      def credential_of(version, cast, stage)
        Credential.new(kind: kind, account_key: account_key, stage: stage, values: cast.values, key_fingerprint: nil,
          version_name: version.name)
      end
    end

    # A source of Wsjrdp::Credentials::Lookup. The including class has
    # #accounts ({[kind, account key] => Account}), #stage and #source_name.
    module Source
      # nil when this source does not name the account.
      def answer(kind, account_key, at: Time.now.utc)
        account(kind, account_key)&.answer(at: at, stage: stage, source: source_name)
      end

      def account(kind, account_key) = accounts[[kind.to_s, Wsjrdp::Credentials.account_key_of(account_key.to_s)]]

      def account_names = accounts.keys

      # "kind/account key" of each account, as messages show them.
      def shown_account_names = account_names.map { |pair| pair.join("/") }
    end
  end
end
