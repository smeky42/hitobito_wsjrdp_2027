# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "openssl"

module Wsjrdp::Credentials
  # The keys this instance seals its credentials with
  # (doc/wsjrdp/credentials.md, "Keys"). HITOBITO_CREDENTIAL_KEYS holds
  # "<stage>:<64 hex>" entries, comma-separated; the bytes are the AES-256
  # key as they are. The first entry of the instance's stage is active, all
  # of its stage are accepted; a valid entry of another stage is kept by
  # fingerprint only, for the pages. A key is known by its fingerprint: the
  # SHA-256 of the secret, lower-cased, as 64 lower-case hex digits
  # (`printf %s "$SECRET" | tr 'A-F' 'a-f' | sha256sum`).
  #
  # Where the variable is not set, the local file's keys and label are the
  # instance's; the sources are never merged (.from_sources). A problem
  # stops every stage but production, which logs it and ignores the entry.
  # Without any key the instance is valid; sealing raises NoKeyError.
  class Keys
    include Undumpable

    ENV_NAME = "HITOBITO_CREDENTIAL_KEYS"
    LABEL_ENV_NAME = "HITOBITO_CREDENTIAL_LABEL"
    SECRET_FORMAT = /\A\h{64}\z/
    KEY_BYTES = 32
    TEST_STAGE = "test"
    TEST_SETTINGS_SOURCE = "config/settings/test.yml credentials.keys_default"
    # The committed, public keys (credentials.keys_default of
    # config/settings/test.yml and the golden-vector spec's key), which only
    # the stage test accepts, and never under RAILS_ENV=production (RAILS_STAGE
    # could say test). Known by fingerprint, so that no file is needed to
    # refuse them; a spec keeps the list in step.
    PUBLIC_FINGERPRINTS = %w[
      00ab7b0562559138d1b7732dc8f46ad620d3aeda2d1163f32f2cca7bf8615025
      7d19cec683431d80e3c1833ba713222dcfb44a7e9ddd6811b13dccb11af2e97e
    ].freeze

    # One key. Never shows its bytes; #bytes is for the Sealer only.
    class Key
      include Undumpable

      attr_reader :stage, :fingerprint

      def initialize(stage, secret_hex)
        @stage = stage
        @fingerprint = Keys.fingerprint_of(secret_hex)
        @bytes = [secret_hex].pack("H*").freeze
        freeze
      end

      attr_reader :bytes

      def inspect = "#<#{self.class.name} #{shown_stage} #{fingerprint}>"
      alias_method :to_s, :inspect

      def as_json(*) = {"stage" => shown_stage, "fingerprint" => fingerprint}

      private

      def shown_stage = Wsjrdp::Credentials.shown_stage(stage)
    end

    # A valid entry of another stage, listed on the pages only: its
    # fingerprint and its stage (nil where the stage may not be shown).
    # It seals and opens nothing.
    class OtherStageKey
      include Undumpable

      attr_reader :stage, :fingerprint

      def initialize(stage, secret_hex)
        @stage = Wsjrdp::Credentials.shown_stage(stage, placeholder: nil)
        @fingerprint = Keys.fingerprint_of(secret_hex)
        freeze
      end

      def inspect = "#<#{self.class.name} #{Wsjrdp::Credentials.shown_stage(stage)} #{fingerprint}>"
      alias_method :to_s, :inspect

      def as_json(*) = {"stage" => stage, "fingerprint" => fingerprint}
    end

    class << self
      def current
        @current ||= from_sources.tap { |keys| keys.log_summary(Rails.logger) }
      end

      def reset! = @current = nil

      # The one definition of the stage in the wagon.
      def stage = Wsjrdp2027::ServiceTokenHmacKeys.stage

      # The keys of the first source that gives them: the variable, else
      # the local file (with the file's label), else in the Rails
      # environment test the committed test key. The log says when a source
      # behind is left unused.
      def from_sources(variable: captured_keys,
        label: Rails.configuration.x.credential_label, file: Overrides.current.file,
        test_value: Rails.env.test? ? Settings.credentials&.keys_default.presence : nil, logger: Rails.logger,
        rails_production: Rails.env.production?)
        defaults = {stage: stage, label: label, rails_production: rails_production}
        build = ->(raw, **options) { new(raw, **defaults, **options) }
        if given?(variable)
          if file.keys?
            logger.warn("#{file.source}: its keys#{" and label" if file.label} are not used, #{ENV_NAME} is set")
          end
          return build.call(variable)
        end

        if file.keys?
          logger.warn("#{LABEL_ENV_NAME}: not used, the keys come from #{file.source}") if given?(label)
          return build.call(file.key_entries, label: file.label, source: file.keys_source,
            label_source: file.label_source)
        end
        return build.call(test_value, source: TEST_SETTINGS_SOURCE) if test_value

        build.call(nil)
      end

      # The SHA-256 of the secret, lower-cased, in 64 lower-case hex digits.
      def fingerprint_of(secret_hex)
        OpenSSL::Digest::SHA256.hexdigest(secret_hex.to_s.strip.downcase)
      end

      def captured_keys = Wsjrdp::Credentials.captured(Rails.configuration.x.credential_keys)

      private

      # As bytes: a value of invalid encoding counts as set (and is refused).
      def given?(value) = !value.nil? && !value.to_s.b.strip.empty?
    end

    attr_reader :stage, :keys, :other_stage_keys, :label, :problems, :warnings, :source, :label_source

    # raw: the variable's text, or the local file's list of entries.
    # rails_production: whether this is RAILS_ENV=production, handed in so
    # that the constructor needs no Rails.
    def initialize(raw, stage:, label: nil, source: ENV_NAME, label_source: LABEL_ENV_NAME, rails_production: false)
      @stage = stage
      @rails_production = rails_production
      @source = source
      @label_source = label_source
      @keys = []
      @other_stage_keys = []
      @problems = []
      @warnings = []
      @label = normalize_label(label)
      parse(raw)
      raise ConfigurationError, problem_message if problems.any? && !production?

      @keys.freeze
      @other_stage_keys.freeze
      @problems.freeze
      @warnings.freeze
    end

    def production? = stage == PRODUCTION

    def active = keys.first

    def active!
      active || raise(NoKeyError, "#{source}: no key for stage #{shown_stage}; credentials cannot be sealed here")
    end

    def find_by_fingerprint(fingerprint) = keys.find { |key| key.fingerprint == fingerprint }

    def accepted?(fingerprint) = !find_by_fingerprint(fingerprint).nil?

    def summary
      if keys.empty?
        "#{source}: no key for stage #{shown_stage}; credentials cannot be sealed or opened here"
      else
        text = "#{source}: stage #{shown_stage}, active key fingerprint #{active.fingerprint}, accepted key fingerprints #{keys.map(&:fingerprint).join(", ")}"
        label ? "#{text}, label #{label}" : text
      end
    end

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

    def shown_stage = Wsjrdp::Credentials.shown_stage(stage)

    # Read as bytes: under a C or POSIX locale Ruby tags ENV values
    # US-ASCII, and a correct UTF-8 label would look invalid.
    def normalize_label(label)
      return nil if label.nil?

      text = label.to_s.b.force_encoding(Encoding::UTF_8)
      unless Wsjrdp::Credentials.text?(text)
        problems << "the label (#{label_source}) is not valid text"
        return nil
      end
      text = text.strip
      text.empty? ? nil : text
    end

    # nil where an entry is not valid text. Split as bytes: String#split
    # and #strip raise on invalid UTF-8.
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
        unless entry_stage == stage
          warnings << other_stage_warning(entry_stage, index)
          next other_stage_keys << OtherStageKey.new(entry_stage, secret)
        end

        keys << Key.new(entry_stage, secret)
      end
    end

    # 64 hex digits are a valid stage, and may be a secret in the wrong
    # place: shown_stage repeats only a short one.
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
      elsif (stage != TEST_STAGE || @rails_production) && PUBLIC_FINGERPRINTS.include?(Keys.fingerprint_of(secret))
        "#{name}: the committed, public key of test"
      end
    end

    def problem_message
      "#{source} (stage #{shown_stage}): #{problems.join("; ")}"
    end
  end
end
