# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "base64"
require "openssl"

module Wsjrdp::Credentials
  # The keys the credentials of this instance are sealed with
  # (doc/wsjrdp/credentials.md).
  #
  # HITOBITO_CREDENTIAL_KEYS holds a comma-separated list of
  # "<stage>:<secret>" entries, the stage of a-z and 0-9, the secret exactly
  # 32 random bytes as 64 hex digits (`openssl rand -hex 32`):
  #
  #   production:<64 hex>,production:<64 hex>
  #
  # The 32 bytes are the AES-256 key as they are; nothing is derived from
  # them. A key is known by its fingerprint, the Base64 of the SHA-256 of the
  # secret as written (lower-cased), as Wsjrdp2027::ServiceTokenHmacKeys
  # makes it:
  #
  #   printf %s "$SECRET" | openssl dgst -sha256 -binary | base64
  #
  # - The first entry of this instance's stage is active: new texts are
  #   sealed with it.
  # - Every entry of this instance's stage is accepted: a text sealed with
  #   any of them can be opened.
  # - An entry of another stage is ignored with a warning.
  # - A problem -- a malformed entry, a secret given twice, a production entry
  #   outside production, a committed, public key outside the stage test --
  #   stops every stage but production, which logs it, ignores the entry and
  #   starts.
  #
  # Without any key the instance is valid: it has no active key, the log
  # says so once, and sealing raises Wsjrdp::Credentials::NoKeyError.
  #
  # No stage has a committed key except the Rails environment test, which
  # falls back to credentials.keys_default in the wagon's
  # config/settings/test.yml. That key and the golden-vector spec's key
  # are made up and public; PUBLIC_FINGERPRINTS names them, and every stage
  # but test refuses them -- without reading any file, so a missing file
  # cannot let one through.
  #
  # HITOBITO_CREDENTIAL_LABEL is an optional name for this instance's key
  # ("laptop-a"), offered as #label.
  #
  # Both variables are read at boot (the wagon's initializer puts them into
  # Rails.configuration.x) and checked once in after_initialize. The plain
  # constructor needs no Rails; .current is the instance of this process.
  class Keys
    include Undumpable

    ENV_NAME = "HITOBITO_CREDENTIAL_KEYS"
    LABEL_ENV_NAME = "HITOBITO_CREDENTIAL_LABEL"
    SECRET_FORMAT = /\A\h{64}\z/
    KEY_BYTES = 32
    TEST_STAGE = "test"
    # The fingerprints (.fingerprint_of) of the committed, public keys, which
    # only the stage test accepts: credentials.keys_default of
    # config/settings/test.yml, and the key the golden-vector spec opens its
    # texts with (CredentialsSpec::GOLDEN_VECTOR_KEY in
    # spec/domain/wsjrdp/credentials/standalone.rb). A spec keeps this list
    # in step with both. Fingerprints only: no key is in this class.
    PUBLIC_FINGERPRINTS = %w[
      AKt7BWJVkTjRt3MtyPRq1iDTrtotEWPzLyzKe/hhUCU=
      fRnOxoNDHYDjwYM7pxMiLc+0Sn6d3WgRsT3MsRry6X4=
    ].freeze

    class ConfigurationError < Error; end

    # One key: its stage, its fingerprint and its bytes. Never shows the
    # bytes; #bytes is for Wsjrdp::Credentials::Sealer only.
    class Key
      include Undumpable

      attr_reader :stage, :fingerprint

      def initialize(stage, secret_hex)
        @stage = stage
        @fingerprint = Keys.fingerprint_of(secret_hex)
        @bytes = [secret_hex].pack("H*").freeze
        freeze
      end

      # The AES-256 key. For the sealer only.
      attr_reader :bytes

      def inspect = "#<#{self.class.name} #{shown_stage} #{fingerprint}>"
      alias_method :to_s, :inspect

      def as_json(*) = {"stage" => shown_stage, "fingerprint" => fingerprint}

      private

      def shown_stage = Wsjrdp::Credentials.shown_stage(stage)
    end

    class << self
      # The keys of this process, read once.
      def current
        @current ||= new(raw_value, stage: stage, label: Rails.configuration.x.credential_label)
          .tap { |keys| keys.log_summary(Rails.logger) }
      end

      def reset! = @current = nil

      # The one definition of the stage in the wagon.
      def stage = Wsjrdp2027::ServiceTokenHmacKeys.stage

      # The variable; in the Rails environment test without it the committed
      # value; else nil.
      def raw_value
        value = Rails.configuration.x.credential_keys
        return value if value.present?

        Rails.env.test? ? Settings.credentials&.keys_default.presence : nil
      end

      # Base64 of the SHA-256 of the secret as written, lower-cased.
      def fingerprint_of(secret_hex)
        Base64.strict_encode64(OpenSSL::Digest::SHA256.digest(secret_hex.to_s.strip.downcase))
      end
    end

    attr_reader :stage, :keys, :label, :problems, :warnings, :source

    # raw: the text of the variable, or a list of entries (as a file's list
    # of keys will give them). source names where it came from in the
    # messages.
    def initialize(raw, stage:, label: nil, source: ENV_NAME)
      @stage = stage
      @source = source
      @keys = []
      @problems = []
      @warnings = []
      @label = normalize_label(label)
      parse(raw)
      raise ConfigurationError, problem_message if problems.any? && !production?

      @keys.freeze
      @problems.freeze
      @warnings.freeze
    end

    def production? = stage == PRODUCTION

    def empty? = keys.empty?

    # The key new texts are sealed with; nil if there is none.
    def active = keys.first

    # The active key, or Wsjrdp::Credentials::NoKeyError.
    def active!
      active || raise(NoKeyError, "#{source}: no key for stage #{shown_stage}; credentials cannot be sealed here")
    end

    # The accepted key with that fingerprint; nil if there is none.
    def find_by_fingerprint(fingerprint) = keys.find { |key| key.fingerprint == fingerprint }

    def accepted?(fingerprint) = !find_by_fingerprint(fingerprint).nil?

    def summary
      if keys.empty?
        "#{source}: no key for stage #{shown_stage}; credentials cannot be sealed or opened here"
      else
        text = "#{source}: stage #{shown_stage}, active #{active.fingerprint}, accepted #{keys.map(&:fingerprint).join(", ")}"
        label ? "#{text}, label #{label}" : text
      end
    end

    # Fingerprints only: the secrets never reach a log, an error page or a
    # console.
    def inspect = "#<#{self.class.name} stage=#{shown_stage} keys=#{keys.map(&:fingerprint).join(",")}>"
    alias_method :to_s, :inspect

    def as_json(*) = {"stage" => shown_stage, "keys" => keys.map(&:fingerprint), "label" => label}

    def log_summary(logger)
      problems.each { |problem| logger.error("#{source}: #{problem} -- ignored") }
      warnings.each { |warning| logger.warn("#{source}: #{warning} -- ignored") }
      keys.empty? ? logger.warn(summary) : logger.info(summary)
      self
    end

    private

    # The stage of this instance as a message may show it.
    def shown_stage = Wsjrdp::Credentials.shown_stage(stage)

    # The label stripped, or nil. Read as bytes re-tagged as UTF-8, as the
    # entries are: under a C or POSIX locale Ruby tags ENV values US-ASCII,
    # and a correct UTF-8 label would look invalid.
    def normalize_label(label)
      return nil if label.nil?

      text = label.to_s.b.force_encoding(Encoding::UTF_8)
      unless text.valid_encoding?
        problems << "the label (#{LABEL_ENV_NAME}) is not valid text"
        return nil
      end
      text = text.strip
      text.empty? ? nil : text
    end

    # The entries in order, each a String, or nil where an entry is not valid
    # text. Split as bytes: String#split and #strip raise on invalid UTF-8.
    def entries(raw)
      list = raw.is_a?(Array) ? raw.map { |entry| entry.to_s.b } : raw.to_s.b.split(",")
      list.map(&:strip).reject(&:empty?).map do |entry|
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
      shown = Wsjrdp::Credentials.shown_stage(entry_stage, placeholder: nil)
      "entry #{index + 1} belongs to #{shown ? "stage #{shown}" : "another stage"}, this is #{shown_stage}"
    end

    def entry_problem(entry_stage, secret, index, seen_secrets)
      name = "entry #{index + 1}"
      if !Wsjrdp::Credentials.stage?(entry_stage)
        "#{name}: the stage is not of a-z and 0-9"
      elsif !SECRET_FORMAT.match?(secret)
        "#{name}: the secret is not exactly 64 hex characters"
      elsif seen_secrets.include?(secret)
        "#{name}: a secret given again"
      elsif !production? && entry_stage == PRODUCTION
        "#{name}: a production secret outside production (stage #{shown_stage})"
      elsif stage != TEST_STAGE && PUBLIC_FINGERPRINTS.include?(Keys.fingerprint_of(secret))
        "#{name}: the committed, public key of test"
      end
    end

    def problem_message
      "#{source} (stage #{shown_stage}): #{problems.join("; ")}"
    end
  end
end
