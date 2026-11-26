# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # The secrets a service token's token is hashed with (Wsjrdp2027::ServiceToken).
  #
  # HITOBITO_SERVICE_TOKEN_HMAC_KEYS holds a comma-separated list of
  # "<stage>:<secret>" entries, the stage of a-z and 0-9, the secret at least
  # 32 random bytes as hex (`openssl rand -hex 32`):
  #
  #   production:<64 hex>,production:<64 hex>
  #
  # A token hash is "hmac-sha256:<hex HMAC-SHA256 of the token>"; the API key
  # stores the stage and the fingerprint of the secret next to it. A
  # fingerprint is the Base64 of the SHA-256 of the secret, lower-cased (44
  # characters), so it can be checked in a shell:
  #
  #   printf %s "$SECRET" | tr 'A-F' 'a-f' | openssl dgst -sha256 -binary | base64
  #
  # It names the secret without giving it away: the secret is 32 random bytes,
  # and the fingerprint is a plain hash, not the HMAC the tokens are hashed
  # with.
  #
  # - The first entry of this instance's stage is active: new HMAC tokens use
  #   it.
  # - Every entry of this instance's stage is accepted: a token is looked up
  #   with each of them. A token of another stage, or of a secret taken out of
  #   the list, does not work here.
  # - Changing a secret: put the new entry first, make the old tokens anew
  #   ("Token neu erzeugen"), then take the old entry out.
  #
  # The stage is RAILS_STAGE (default "production") under
  # RAILS_ENV=production, else the Rails environment: "development", "test".
  # A RAILS_STAGE that is no stage (not of a-z and 0-9, or not valid text)
  # is logged as an error, and the stage is production. Both variables are
  # read at boot (the wagon's initializer puts them into
  # Rails.configuration.x).
  #
  # Production always starts: a missing variable leaves it without active key
  # (no HMAC token can be made, and only the unhashed and "sha256:" tokens
  # work), a bad entry -- an entry that is not valid text (invalid UTF-8)
  # among them -- is logged and ignored. Any other stage refuses to start on a
  # bad entry and on any "production" entry, so a production secret never
  # makes production tokens work outside production. Entries of a stage other
  # than this one and production are ignored with a warning, which names
  # their stage only up to 32 characters ("another stage" beyond): 64 hex
  # digits are a valid stage, and may be a secret typed into the wrong place.
  # No message repeats anything else of an entry.
  #
  # Without the variable, development and test fall back to the value in the
  # wagon's config/settings/<environment>.yml. Those values are committed and
  # public on purpose: they only mark development and test tokens, which work
  # nowhere else. Production refuses them, and so does every stage under
  # RAILS_ENV=production (RAILS_STAGE could say test).
  class ServiceTokenHmacKeys
    ENV_NAME = "HITOBITO_SERVICE_TOKEN_HMAC_KEYS"
    SCHEME = "hmac-sha256"
    PRODUCTION = "production"
    STAGE_FORMAT = /\A[a-z0-9]+\z/
    SECRET_FORMAT = /\A\h{64,}\z/
    FINGERPRINT_FORMAT = %r{\A[A-Za-z0-9+/]{43}=\z}
    # The longest stage of an entry a warning repeats. A longer one may be a
    # secret typed into the stage slot, so the warning says "another stage".
    SHOWN_STAGE_LENGTH = 32
    # The stages that fall back to a committed value in the wagon settings.
    PUBLIC_SETTINGS = %w[development test].freeze
    # The fingerprints (.fingerprint_of, of the lower-cased secret) of the
    # committed, public secrets of config/settings/development.yml and
    # test.yml. A spec keeps the list in step with both files.
    PUBLIC_FINGERPRINTS = %w[
      WN0sZJHVfCpg0yZC9eIPJDdSQrFrZId6W6GAzVtvkv8=
      93OaGuwMCcHbuIzts/FkPea33GyLHbwlSwqY9NPUPsg=
    ].freeze

    class ConfigurationError < StandardError; end

    # One secret: its stage, its fingerprint and its bytes. Never shows the
    # secret.
    class Key
      attr_reader :stage, :fingerprint

      def initialize(stage, secret_hex)
        @stage = stage
        @fingerprint = ServiceTokenHmacKeys.fingerprint_of(secret_hex)
        @secret = [secret_hex].pack("H*")
      end

      # The token hash the token column stores for plain_token.
      def digest(plain_token)
        "#{SCHEME}:#{OpenSSL::HMAC.hexdigest("SHA256", @secret, plain_token.to_s)}"
      end

      def inspect = "#<#{self.class.name} #{stage} #{fingerprint}>"
      alias_method :to_s, :inspect
    end

    class << self
      # The keys of this process, read once.
      def current
        @current ||= begin
          raw = Rails.configuration.x.service_token_hmac_keys
          raw = raw.call if raw.respond_to?(:call) # the initializer's lambda; a spec may set a plain value
          Rails.logger.error("RAILS_STAGE: not a stage of a-z and 0-9; the stage is #{PRODUCTION}") if stage_invalid?
          new(given?(raw) ? raw : default_value, stage: stage, rails_production: Rails.env.production?)
            .tap(&:log_summary)
        end
      end

      def reset! = @current = nil

      def stage
        return Rails.env.to_s unless Rails.env.production?

        stage_variable || PRODUCTION
      end

      # Base64 of the SHA-256 of the text given; callers lower-case it.
      def fingerprint_of(secret_hex) = Base64.strict_encode64(OpenSSL::Digest::SHA256.digest(secret_hex.to_s))

      # The committed value of development and test; nil in any other stage.
      def default_value
        return nil unless PUBLIC_SETTINGS.include?(stage)

        Settings.service_tokens&.hmac_keys_default.presence
      end

      private

      # Whether a variable is set, decided on its bytes: blank? would raise on
      # invalid UTF-8, and production must start.
      def given?(value) = !value.nil? && !value.to_s.b.strip.empty?

      # RAILS_STAGE stripped when it is a stage; nil when it is not set or no
      # stage.
      def stage_variable
        raw = Rails.configuration.x.rails_stage
        return nil unless given?(raw)

        text = raw.to_s.b.strip.force_encoding(Encoding::UTF_8)
        (text.valid_encoding? && STAGE_FORMAT.match?(text)) ? text : nil
      end

      def stage_invalid? = Rails.env.production? && given?(Rails.configuration.x.rails_stage) && stage_variable.nil?
    end

    attr_reader :stage, :keys, :problems, :warnings

    # rails_production: whether this is RAILS_ENV=production, handed in so
    # that a spec can set it.
    def initialize(raw, stage:, rails_production: false)
      @stage = stage
      @refuse_public = production? || rails_production
      @keys = []
      @problems = []
      @warnings = []
      parse(raw.to_s)
      raise ConfigurationError, problem_message if problems.any? && !production?
    end

    def production? = stage == PRODUCTION

    # The key new HMAC tokens are made with; nil if there is none.
    def active = keys.first

    # The accepted key with that fingerprint; nil if there is none.
    def find_by_fingerprint(fingerprint) = keys.find { |key| key.fingerprint == fingerprint }

    def accepted?(fingerprint) = find_by_fingerprint(fingerprint).present?

    # The token hashes under which a token with plain_token may be stored.
    def digests(plain_token) = keys.map { |key| key.digest(plain_token) }

    def summary
      if keys.empty?
        "#{ENV_NAME}: no key for stage #{stage}; HMAC service tokens cannot be made"
      else
        "#{ENV_NAME}: stage #{stage}, active key fingerprint #{active.fingerprint}, accepted key fingerprints #{keys.map(&:fingerprint).join(", ")}"
      end
    end

    # Fingerprints only: the secrets never reach a log, an error page or a
    # console.
    def inspect = "#<#{self.class.name} stage=#{stage} keys=#{keys.map(&:fingerprint).join(",")}>"
    alias_method :to_s, :inspect

    def log_summary(logger = Rails.logger)
      problems.each { |problem| logger.error("#{ENV_NAME}: #{problem} -- ignored") }
      warnings.each { |warning| logger.warn("#{ENV_NAME}: #{warning} -- ignored") }
      keys.empty? ? logger.warn(summary) : logger.info(summary)
      self
    end

    private

    # The entries in order, each a String, or nil where an entry is not valid
    # text. Split as bytes: String#split and #strip raise on invalid UTF-8.
    # Re-tagged as UTF-8, so that a correct value Ruby tagged US-ASCII (as
    # under a C or POSIX locale) is read as it is.
    def entries(raw)
      raw.b.split(",").map(&:strip).reject(&:empty?).map do |entry|
        text = entry.force_encoding(Encoding::UTF_8)
        text.valid_encoding? ? text : nil
      end
    end

    def parse(raw)
      seen_secrets = []
      entries(raw).each_with_index do |entry, index|
        next problems << "entry #{index + 1}: not valid text" if entry.nil?

        entry_stage, secret = entry.split(":", 2)
        entry_stage = entry_stage.to_s.strip
        secret = secret.to_s.strip.downcase
        problem = entry_problem(entry_stage, secret, index, seen_secrets)
        next problems << problem if problem

        seen_secrets << secret
        next warnings << other_stage_warning(entry_stage, index) unless entry_stage == stage

        keys << Key.new(entry_stage, secret)
      end
    end

    # Names the entry's stage only when it is short: 64 hex digits are a
    # valid stage, and may be a secret typed into the wrong place.
    def other_stage_warning(entry_stage, index)
      shown = (entry_stage.length <= SHOWN_STAGE_LENGTH) ? "stage #{entry_stage}" : "another stage"
      "entry #{index + 1} belongs to #{shown}, this is #{stage}"
    end

    def entry_problem(entry_stage, secret, index, seen_secrets)
      name = "entry #{index + 1}"
      if !STAGE_FORMAT.match?(entry_stage)
        "#{name}: the stage is not of a-z and 0-9"
      elsif !SECRET_FORMAT.match?(secret)
        "#{name}: the secret is not at least 64 hex characters"
      elsif seen_secrets.include?(secret)
        "#{name}: a secret given again"
      elsif !production? && entry_stage == PRODUCTION
        "#{name}: a production secret outside production (stage #{stage})"
      elsif @refuse_public && PUBLIC_FINGERPRINTS.include?(ServiceTokenHmacKeys.fingerprint_of(secret))
        "#{name}: the committed, public secret of development or test"
      end
    end

    def problem_message
      "#{ENV_NAME} (stage #{stage}): #{problems.join("; ")}"
    end
  end
end
