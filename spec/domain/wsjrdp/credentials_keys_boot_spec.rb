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

    it "refuses the committed key under RAILS_ENV=production, even when RAILS_STAGE says test" do
      config.credential_keys = Settings.credentials.keys_default
      allow(Rails.env).to receive(:production?).and_return(true)
      allow(described_class).to receive(:stage).and_return("test")

      expect { described_class.current }
        .to raise_error(Wsjrdp::Credentials::ConfigurationError, /the committed, public key of test/)
    end

    it "takes the variable when it is set, and its label" do
      config.credential_keys = "test:#{secret}"
      config.credential_label = " laptop-a "

      keys = described_class.current
      expect(keys.keys.map(&:fingerprint)).to eq([described_class.fingerprint_of(secret)])
      expect(keys.label).to eq("laptop-a")
    end

    it "starts production with invalid bytes in a variable tagged US-ASCII, ignoring that entry" do
      allow(Rails.env).to receive(:production?).and_return(true)
      allow(described_class).to receive(:stage).and_return("production")
      config.credential_keys = "production:#{secret},production:#{"c" * 63}\xFF".force_encoding(Encoding::US_ASCII)

      keys = described_class.current
      expect(keys.keys.map(&:fingerprint)).to eq([described_class.fingerprint_of(secret)])
      expect(keys.problems).to eq(["entry 2: not valid text"])
    end

    it "is read once per process, until reset!" do
      config.credential_keys = "test:#{secret}"
      first = described_class.current
      config.credential_keys = "test:#{"e" * 64}"

      expect(described_class.current).to equal(first)
      described_class.reset!
      expect(described_class.current).not_to equal(first)
    end
  end

  # The initializer itself: credentials_overrides_spec.rb.
  describe "the boot wiring" do
    it "reads the keys' text from behind the initializer's lambda" do
      config.credential_keys = -> { "test:#{secret}" }

      expect(described_class.current.keys.map(&:fingerprint)).to eq([described_class.fingerprint_of(secret)])
    end

    it "has read the keys at boot, before any example ran" do
      expect(CredentialsKeysBootSpec::KEYS_AT_BOOT).to be_a(described_class)
      expect(CredentialsKeysBootSpec::KEYS_AT_BOOT.stage).to eq("test")
    end
  end
end
