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

  def keys(raw, stage:, **options) = described_class.new(raw, stage: stage, **options)

  # The committed secrets of the two settings files, read by the spec only.
  def committed_secrets
    %w[development test].flat_map do |name|
      path = HitobitoWsjrdp2027::Wagon.root.join("config", "settings", "#{name}.yml")
      YAML.safe_load_file(path).dig("service_tokens", "hmac_keys_default").to_s.split(",")
        .map { |entry| entry.split(":", 2).last.strip }
    end
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

    it "makes the fingerprint the Base64 of the SHA-256 of the lower-cased secret, 44 characters" do
      key = keys("development:#{secret_a}", stage: "development").active
      expect(key.fingerprint).to eq(fingerprint(secret_a))
      expect(key.fingerprint.length).to eq(44)
      expect(keys("development:#{secret_a.upcase}", stage: "development").active.fingerprint).to eq(fingerprint(secret_a))
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
    keys = keys("production:#{secret_a},development:#{secret_c},broken", stage: "production")
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

    it "refuses the committed, public secrets, however they are written" do
      committed = committed_secrets.first
      keys = keys("production:#{committed},production:#{secret_b},production:#{committed_secrets.last.upcase}",
        stage: "production")

      expect(keys.keys.map(&:fingerprint)).to eq([fingerprint(secret_b)])
      expect(keys.problems).to eq(["entry 1: the committed, public secret of development or test",
        "entry 3: the committed, public secret of development or test"])
    end

    it "knows the committed secrets of development and test by PUBLIC_FINGERPRINTS, exactly" do
      expect(committed_secrets.size).to eq(2)
      expect(described_class::PUBLIC_FINGERPRINTS)
        .to match_array(committed_secrets.map { |secret| described_class.fingerprint_of(secret.downcase) })
    end

    it "reads no file for the check" do
      raw = "staging:#{committed_secrets.first}"
      expect(YAML).not_to receive(:safe_load_file)
      expect(File).not_to receive(:read)
      expect { keys(raw, stage: "staging", rails_production: true) }
        .to raise_error(described_class::ConfigurationError, /public secret/)
    end
  end

  describe "under RAILS_ENV=production" do
    let(:public_secret) { committed_secrets.first }

    it "refuses the committed secrets in any stage, which then does not start" do
      %w[staging test].each do |stage|
        expect { described_class.new("#{stage}:#{public_secret}", stage: stage, rails_production: true) }
          .to raise_error(described_class::ConfigurationError, /committed, public secret/) { |error|
            expect(error.message).not_to include(public_secret)
          }
      end
    end

    it "accepts the committed secrets in the stage test when not under RAILS_ENV=production" do
      expect(described_class.new("test:#{public_secret}", stage: "test").keys.size).to eq(1)
    end

    it "is what .current hands in" do
      described_class.reset!
      allow(Rails.env).to receive(:production?).and_return(true)
      allow(Rails.configuration.x).to receive(:rails_stage).and_return("staging")
      allow(Rails.configuration.x).to receive(:service_token_hmac_keys).and_return("staging:#{public_secret}")

      expect { described_class.current }.to raise_error(described_class::ConfigurationError, /public secret/)
    ensure
      described_class.reset!
    end
  end

  describe ".current under RAILS_ENV=production with invalid bytes" do
    let(:output) { StringIO.new }

    # .current with these variables, the log in output.
    def current_with(stage:, keys:)
      described_class.reset!
      allow(Rails.env).to receive(:production?).and_return(true)
      allow(Rails.configuration.x).to receive(:rails_stage).and_return(stage)
      allow(Rails.configuration.x).to receive(:service_token_hmac_keys).and_return(keys)
      allow(Rails).to receive(:logger).and_return(Logger.new(output))
      described_class.current
    end

    after { described_class.reset! }

    it "starts with invalid bytes in the variable, in UTF-8 and in US-ASCII, ignoring that entry" do
      ["production:#{secret_a},production:#{"c" * 63}\xFF",
        "production:#{secret_a},production:#{"c" * 63}\xFF".force_encoding(Encoding::US_ASCII)].each do |raw|
        keys = current_with(stage: nil, keys: raw)

        expect(keys.stage).to eq("production")
        expect(keys.keys.map(&:fingerprint)).to eq([fingerprint(secret_a)])
        expect(keys.problems).to eq(["entry 2: not valid text"])
      end
      expect(output.string).not_to include("c" * 16)
    end

    it "counts a variable that is blank as bytes as not set" do
      expect(current_with(stage: nil, keys: " \t").keys).to eq([])
    end

    it "is production, with an error, for a RAILS_STAGE of invalid bytes or that is no stage" do
      ["stag\xFFing", (+"stag\xFFing").force_encoding(Encoding::US_ASCII), "Staging", "stag ing"].each do |stage|
        keys = current_with(stage: stage, keys: "production:#{secret_a}")

        expect(keys.stage).to eq("production"), stage.inspect
        expect(keys.active.fingerprint).to eq(fingerprint(secret_a))
        expect(Wsjrdp::Credentials::Keys.stage).to eq("production")
      end
      expect(output.string).to include("RAILS_STAGE: not a stage of a-z and 0-9; the stage is production")
      expect(output.string).not_to include("Staging", "stag ing")
    end

    it "takes a valid RAILS_STAGE, stripped, without an error" do
      keys = current_with(stage: " staging ", keys: "staging:#{secret_a}")

      expect(keys.stage).to eq("staging")
      expect(output.string).not_to include("RAILS_STAGE")
    end
  end

  describe "an entry that is not valid text" do
    # Invalid UTF-8; the literal is a String of invalid encoding.
    let(:bad_stage) { "produc\xFFtion:#{secret_c}" }
    let(:bad_secret) { "production:#{"c" * 63}\xFF" }

    it "is recorded and ignored in production, the good entries still active" do
      keys = keys("production:#{secret_a},#{bad_stage},#{bad_secret},production:#{secret_b}", stage: "production")

      expect(keys.keys.map(&:fingerprint)).to eq([fingerprint(secret_a), fingerprint(secret_b)])
      expect(keys.active.fingerprint).to eq(fingerprint(secret_a))
      expect(keys.problems).to eq(["entry 2: not valid text", "entry 3: not valid text"])
    end

    it "is logged without anything of the entry in production" do
      output = StringIO.new
      keys("production:#{secret_a},#{bad_secret}", stage: "production").log_summary(Logger.new(output))

      expect(output.string).to include("entry 2: not valid text")
      expect(output.string).not_to include("c" * 16)
    end

    it "refuses to start outside production, the message without the entry" do
      ["develop\xFFment:#{secret_c}", "development:#{"c" * 63}\xFF"].each do |entry|
        expect { keys("development:#{secret_a},#{entry}", stage: "development") }
          .to raise_error(described_class::ConfigurationError) { |error|
            expect(error.message).to include("entry 2: not valid text")
            expect(error.message).not_to include("c" * 16)
            expect(error.message).to be_valid_encoding
          }
      end
    end
  end

  describe "the warning on an entry of another stage" do
    # 64 hex digits are a valid stage: a secret typed into the stage slot.
    let(:typed_secret) { "0123456789abcdef" * 4 }

    def log_of(keys)
      output = StringIO.new
      keys.log_summary(Logger.new(output))
      output.string
    end

    # No run of 8 characters of the typed secret appears in text.
    def expect_none_of_typed_secret(text)
      typed_secret.chars.each_cons(8).map(&:join).each do |window|
        expect(text).not_to include(window)
      end
    end

    it "says another stage for a 64-hex stage in production, the log holding none of it" do
      keys = keys("production:#{secret_a},#{typed_secret}:#{secret_b}", stage: "production")

      expect(keys.keys.map(&:fingerprint)).to eq([fingerprint(secret_a)])
      expect(keys.warnings).to eq(["entry 2 belongs to another stage, this is production"])
      expect_none_of_typed_secret(log_of(keys))
    end

    it "says another stage for a 64-hex stage outside production, the log holding none of it" do
      keys = keys("development:#{secret_a},#{typed_secret}:#{secret_b}", stage: "development")

      expect(keys.warnings).to eq(["entry 2 belongs to another stage, this is development"])
      expect_none_of_typed_secret(log_of(keys))
    end

    it "still names an ordinary stage" do
      keys = keys("production:#{secret_a},staging:#{secret_b}", stage: "production")

      expect(keys.warnings).to eq(["entry 2 belongs to stage staging, this is production"])
    end

    it "names a stage of 32 characters, not one of 33" do
      keys = keys("production:#{secret_a},#{"s" * 32}:#{secret_b},#{"t" * 33}:#{secret_c}", stage: "production")

      expect(keys.warnings).to eq([
        "entry 2 belongs to stage #{"s" * 32}, this is production",
        "entry 3 belongs to another stage, this is production"
      ])
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
