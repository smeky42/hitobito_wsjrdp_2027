# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# HITOBITO_SERVICE_TOKEN_HMAC_KEYS: "<stage>:<hex secret>" entries, the first
# of this stage active, all of this stage accepted, each known by its
# fingerprint. Production always starts; any other stage refuses a bad entry
# and a production one.
describe Wsjrdp2027::ServiceTokenHmacKeys do
  let(:secret_a) { "a" * 64 }
  let(:secret_b) { "b" * 64 }
  let(:secret_c) { "c" * 64 }

  def keys(raw, stage:, public_secrets: [])
    described_class.new(raw, stage: stage, public_secrets: public_secrets)
  end

  def fingerprint(secret) = Base64.strict_encode64(Digest::SHA256.digest(secret))

  describe "accepted and active keys" do
    it "takes the first entry of the stage as active and all of it as accepted" do
      keys = keys("development:#{secret_a}, development:#{secret_b}", stage: "development")

      expect(keys.active.fingerprint).to eq(fingerprint(secret_a))
      expect(keys.keys.map(&:stage)).to eq(%w[development development])
      expect(keys.accepted?(fingerprint(secret_b))).to be(true)
      expect(keys.find_by_fingerprint(fingerprint(secret_b)).fingerprint).to eq(fingerprint(secret_b))
    end

    it "makes the fingerprint the Base64 of the SHA-256 of the secret as written, 44 characters" do
      key = keys("development:#{secret_a}", stage: "development").active
      expect(key.fingerprint).to eq(fingerprint(secret_a))
      expect(key.fingerprint.length).to eq(44)
    end

    it "ignores entries of another non-production stage with a warning" do
      keys = keys("test:#{secret_a},development:#{secret_b}", stage: "development")

      expect(keys.keys.map(&:fingerprint)).to eq([fingerprint(secret_b)])
      expect(keys.warnings.join).to include("stage test")
    end

    it "hashes a token as hmac-sha256:<hex>, one value per accepted key" do
      keys = keys("development:#{secret_a},development:#{secret_b}", stage: "development")
      digests = keys.digests("token")

      expect(digests.first).to eq("hmac-sha256:#{OpenSSL::HMAC.hexdigest("SHA256", [secret_a].pack("H*"), "token")}")
      expect(digests.size).to eq(2)
      expect(digests.uniq.size).to eq(2)
    end
  end

  describe "outside production" do
    it "refuses to start with a production secret" do
      expect { keys("production:#{secret_a}", stage: "development") }
        .to raise_error(described_class::ConfigurationError, /production secret/)
    end

    it "refuses a production secret in an integration stage as well" do
      expect { keys("integration:#{secret_a},production:#{secret_b}", stage: "integration") }
        .to raise_error(described_class::ConfigurationError)
    end

    it "refuses malformed entries" do
      ["Development:#{secret_a}", "development-x:#{secret_a}", "development:#{"a" * 63}",
        "development:#{"g" * 64}", "development"].each do |raw|
        expect { keys(raw, stage: "development") }.to raise_error(described_class::ConfigurationError), raw
      end
    end

    it "refuses a secret given twice" do
      expect { keys("development:#{secret_a},development:#{secret_a}", stage: "development") }
        .to raise_error(described_class::ConfigurationError, /given again/)
    end

    it "never puts a secret into its messages" do
      keys("development:#{secret_a},development:#{secret_a}", stage: "development")
    rescue described_class::ConfigurationError => e
      expect(e.message).not_to include(secret_a)
    end
  end

  it "shows fingerprints, never secrets, when inspected or logged" do
    keys = keys("production:#{secret_a},development:#{secret_c},broken", stage: "production", public_secrets: [secret_b])
    logger = instance_double(Logger, error: nil, warn: nil, info: nil)
    keys.log_summary(logger)

    shown = [keys.inspect, keys.to_s, keys.keys.first.inspect, keys.summary, keys.problems, keys.warnings].join
    expect(shown).to include(fingerprint(secret_a))
    expect(shown).not_to include(secret_a)
    expect(shown).not_to include(secret_b)
    expect(shown).not_to include(secret_c)
  end

  describe "in production" do
    it "starts without the variable, with no active key" do
      keys = keys(nil, stage: "production")

      expect(keys.active).to be_nil
      expect(keys.digests("token")).to eq([])
      expect(keys.summary).to include("no key")
    end

    it "starts despite bad entries, ignoring them" do
      keys = keys("production:#{secret_a},development:#{secret_b},broken,production:#{secret_a}", stage: "production")

      expect(keys.keys.map(&:fingerprint)).to eq([fingerprint(secret_a)])
      expect(keys.problems.join).to include("entry 3", "given again")
      expect(keys.warnings.join).to include("stage development")
    end

    it "refuses the committed, public secrets" do
      keys = keys("production:#{secret_a},production:#{secret_b}", stage: "production", public_secrets: [secret_a])

      expect(keys.keys.map(&:fingerprint)).to eq([fingerprint(secret_b)])
      expect(keys.problems.join).to include("public")
    end

    it "reads the committed secrets of development and test" do
      expect(described_class.public_secrets.size).to eq(2)
      expect(described_class.public_secrets).to all(match(/\A\h{64}\z/))
    end
  end

  describe ".stage" do
    it "is the Rails environment outside RAILS_ENV=production" do
      expect(described_class.stage).to eq("test")
    end

    it "is RAILS_STAGE under RAILS_ENV=production, production without it" do
      allow(Rails.env).to receive(:production?).and_return(true)
      allow(Rails.configuration.x).to receive(:rails_stage).and_return(nil)
      expect(described_class.stage).to eq("production")

      allow(Rails.configuration.x).to receive(:rails_stage).and_return("integration")
      expect(described_class.stage).to eq("integration")
    end
  end

  it "uses the committed test value in the test environment" do
    expect(described_class.current.active.stage).to eq("test")
  end
end
