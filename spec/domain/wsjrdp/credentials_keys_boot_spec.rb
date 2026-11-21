# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# What the standalone specs of spec/domain/wsjrdp/credentials/ cannot cover:
# Wsjrdp::Credentials::Keys.current in the Rails environment test, its
# fallback to the committed test key, and the boot wiring of
# lib/hitobito_wsjrdp_2027/wagon.rb. The secrets are made up.
module CredentialsKeysBootSpec
  # Taken when rspec loads this file, after the app booted and before any
  # example (one of which resets the memo) ran: the keys the boot read
  # (config.after_initialize in wagon.rb), or nil if the boot did not.
  KEYS_AT_BOOT = Wsjrdp::Credentials::Keys.instance_variable_get(:@current)
end

describe Wsjrdp::Credentials::Keys do
  let(:secret) { "d" * 64 }
  let(:config) { Rails.configuration.x }

  around do |example|
    saved = [config.credential_keys, config.credential_label]
    described_class.reset!
    example.run
  ensure
    config.credential_keys, config.credential_label = saved
    described_class.reset!
  end

  describe ".current" do
    it "falls back to credentials.keys_default of the test settings when the variable is not set" do
      config.credential_keys = nil
      test_secret = Settings.credentials.keys_default.split(":", 2).last

      keys = described_class.current
      expect(keys.stage).to eq("test")
      expect(keys.active.fingerprint).to eq(described_class.fingerprint_of(test_secret))
      expect(described_class::PUBLIC_FINGERPRINTS).to include(keys.active.fingerprint)
    end

    it "takes the variable when it is set, and its label" do
      config.credential_keys = "test:#{secret}"
      config.credential_label = " laptop-a "

      keys = described_class.current
      expect(keys.keys.map(&:fingerprint)).to eq([described_class.fingerprint_of(secret)])
      expect(keys.label).to eq("laptop-a")
    end

    it "starts production with invalid bytes in the variable, ignoring that entry" do
      allow(Rails.env).to receive(:production?).and_return(true)
      allow(described_class).to receive(:stage).and_return("production")
      bad = "production:#{secret},production:#{"c" * 63}\xFF"
      [bad, bad.dup.force_encoding(Encoding::US_ASCII)].each do |raw|
        config.credential_keys = raw
        described_class.reset!

        keys = described_class.current
        expect(keys.keys.map(&:fingerprint)).to eq([described_class.fingerprint_of(secret)])
        expect(keys.problems).to eq(["entry 2: not valid text"])
      end
    end

    it "is read once per process, until reset!" do
      config.credential_keys = "test:#{secret}"
      first = described_class.current
      config.credential_keys = "test:#{"e" * 64}"

      expect(described_class.current).to equal(first)
      described_class.reset!
      expect(described_class.current).not_to equal(first)
    end

    it "has the stage of the service tokens" do
      expect(described_class.stage).to eq(Wsjrdp2027::ServiceTokenHmacKeys.stage)
    end

    it "logs fingerprints, never a secret" do
      config.credential_keys = "test:#{secret}"
      lines = []
      allow(Rails.logger).to receive(:info) { |line| lines << line }

      described_class.current
      expect(lines.join).to include(described_class.fingerprint_of(secret))
      expect(lines.join).not_to include(secret)
    end
  end

  describe "the boot wiring" do
    def initializer
      HitobitoWsjrdp2027::Wagon.initializers.find { |init| init.name == "wsjrdp_2027.credential_keys" }
    end

    it "takes both variables into the configuration" do
      app = Struct.new(:config).new(ActiveSupport::OrderedOptions.new.tap { |c| c.x = ActiveSupport::OrderedOptions.new })
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("HITOBITO_CREDENTIAL_KEYS").and_return("test:#{secret}")
      allow(ENV).to receive(:[]).with("HITOBITO_CREDENTIAL_LABEL").and_return("laptop-a")

      initializer.run(app)
      expect(app.config.x.credential_keys).to eq("test:#{secret}")
      expect(app.config.x.credential_label).to eq("laptop-a")
    end

    it "has read the keys at boot, before any example ran" do
      expect(CredentialsKeysBootSpec::KEYS_AT_BOOT).to be_a(described_class)
      expect(CredentialsKeysBootSpec::KEYS_AT_BOOT.stage).to eq("test")
    end
  end
end
