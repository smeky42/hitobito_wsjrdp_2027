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
  # fingerprint is the Base64 of the SHA-256 of the secret as written (44
  # characters), so it can be checked in a shell:
  #
  #   printf %s "$SECRET" | openssl dgst -sha256 -binary | base64
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
  # Both variables are read at boot (the wagon's initializer puts them into
  # Rails.configuration.x).
  #
  # Production always starts: a missing variable leaves it without active key
  # (no HMAC token can be made, and only the unhashed and "sha256:" tokens
  # work), a bad entry is logged and ignored. Any other stage refuses to start
  # on a bad entry and on any "production" entry, so a production secret never
  # makes production tokens work outside production. Entries of a stage other
  # than this one and production are ignored with a warning.
  #
  # Without the variable, development and test fall back to the value in the
  # wagon's config/settings/<environment>.yml. Those values are committed and
  # public on purpose: they only mark development and test tokens, which work
  # nowhere else. Production refuses them.
  class ServiceTokenHmacKeys
    ENV_NAME = "HITOBITO_SERVICE_TOKEN_HMAC_KEYS"
    SCHEME = "hmac-sha256"
    PRODUCTION = "production"
    STAGE_FORMAT = /\A[a-z0-9]+\z/
    SECRET_FORMAT = /\A\h{64,}\z/
    FINGERPRINT_FORMAT = %r{\A[A-Za-z0-9+/]{43}=\z}
    # The wagon settings that hold the committed, public secrets.
    PUBLIC_SETTINGS = %w[development test].freeze

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
        @current ||= new(Rails.configuration.x.service_token_hmac_keys.presence || default_value, stage: stage)
          .tap(&:log_summary)
      end

      def reset! = @current = nil

      def stage
        if Rails.env.production?
          Rails.configuration.x.rails_stage.presence || PRODUCTION
        else
          Rails.env.to_s
        end
      end

      # Base64 of the SHA-256 of the secret as written.
      def fingerprint_of(secret_hex) = Base64.strict_encode64(OpenSSL::Digest::SHA256.digest(secret_hex.to_s))

      # The committed value of development and test; nil in any other stage.
      def default_value
        return nil unless PUBLIC_SETTINGS.include?(stage)

        Settings.service_tokens&.hmac_keys_default.presence
      end

      # The committed secrets, which production refuses.
      def public_secrets
        PUBLIC_SETTINGS.flat_map do |name|
          path = HitobitoWsjrdp2027::Wagon.root.join("config", "settings", "#{name}.yml")
          next [] unless path.exist?

          value = YAML.safe_load_file(path).to_h.dig("service_tokens", "hmac_keys_default")
          value.to_s.split(",").map { |entry| entry.split(":", 2).last.to_s.strip.downcase }
        end
      end
    end

    attr_reader :stage, :keys, :problems, :warnings

    def initialize(raw, stage:, public_secrets: nil)
      @stage = stage
      @public_secrets = public_secrets || (production? ? self.class.public_secrets : [])
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
        "#{ENV_NAME}: stage #{stage}, active #{active.fingerprint}, accepted #{keys.map(&:fingerprint).join(", ")}"
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

    def parse(raw)
      seen_secrets = []
      raw.split(",").map(&:strip).reject(&:empty?).each_with_index do |entry, index|
        entry_stage, secret = entry.split(":", 2)
        entry_stage = entry_stage.to_s.strip
        secret = secret.to_s.strip.downcase
        problem = entry_problem(entry_stage, secret, index, seen_secrets)
        next problems << problem if problem

        seen_secrets << secret
        next warnings << "entry #{index + 1} belongs to stage #{entry_stage}, this is #{stage}" unless entry_stage == stage

        keys << Key.new(entry_stage, secret)
      end
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
      elsif production? && @public_secrets.include?(secret)
        "#{name}: the committed, public secret of development or test"
      end
    end

    def problem_message
      "#{ENV_NAME} (stage #{stage}): #{problems.join("; ")}"
    end
  end
end
