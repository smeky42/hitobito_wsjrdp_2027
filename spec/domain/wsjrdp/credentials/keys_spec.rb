# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Standalone, without Rails (see standalone.rb).
require_relative "standalone"

# HITOBITO_CREDENTIAL_KEYS: "<stage>:<64 hex>" entries, the first of this
# stage active, all of this stage accepted, each known by its fingerprint.
# Production always starts; any other stage refuses a bad entry and a
# production one. The secrets below are made up.
describe Wsjrdp::Credentials::Keys do
  let(:secret_a) { "a" * 64 }
  let(:secret_b) { "b" * 64 }
  let(:secret_c) { "c" * 64 }
  let(:test_secret) { CredentialsSpec.test_settings_secrets.first }

  def keys(raw, stage:, **options) = described_class.new(raw, stage: stage, **options)

  def fingerprint(secret) = Base64.strict_encode64(OpenSSL::Digest::SHA256.digest(secret))

  describe "accepted and active keys" do
    it "takes the first entry of the stage as active and all of it as accepted" do
      keys = keys("development:#{secret_a}, development:#{secret_b}", stage: "development")

      expect(keys.active.fingerprint).to eq(fingerprint(secret_a))
      expect(keys.keys.map(&:stage)).to eq(%w[development development])
      expect(keys.accepted?(fingerprint(secret_b))).to be(true)
      expect(keys.accepted?(fingerprint(secret_c))).to be(false)
      expect(keys.find_by_fingerprint(fingerprint(secret_b))).to equal(keys.keys.last)
    end

    it "makes the fingerprint the Base64 of the SHA-256 of the secret as written, lower-cased" do
      upper = "A1" * 32
      key = keys("development:#{upper}", stage: "development").active

      expect(key.fingerprint).to eq(fingerprint(upper.downcase))
      expect(key.fingerprint.length).to eq(44)
      expect(described_class.fingerprint_of(upper)).to eq(fingerprint(upper.downcase))
    end

    it "uses the 32 bytes of the hex secret as they are" do
      key = keys("development:#{"0f" * 32}", stage: "development").active

      expect(key.bytes).to eq("\x0f".b * 32)
      expect(key.bytes.bytesize).to eq(described_class::KEY_BYTES)
    end

    it "ignores entries of another non-production stage with a warning" do
      keys = keys("test:#{secret_a},development:#{secret_b}", stage: "development")

      expect(keys.keys.map(&:fingerprint)).to eq([fingerprint(secret_b)])
      expect(keys.warnings.join).to include("entry 1", "stage test")
    end

    it "takes a list of entries as well as a text" do
      keys = keys(["development:#{secret_a}", " development:#{secret_b} "], stage: "development")

      expect(keys.keys.map(&:fingerprint)).to eq([fingerprint(secret_a), fingerprint(secret_b)])
    end

    it "names the source in its messages" do
      keys = keys(nil, stage: "development", source: "config/wsjrdp_credentials.local.yml keys")

      expect(keys.summary).to start_with("config/wsjrdp_credentials.local.yml keys:")
    end
  end

  describe "without any key" do
    it "is valid, has no active key and refuses to seal" do
      keys = keys(nil, stage: "development")

      expect(keys).to be_empty
      expect(keys.active).to be_nil
      expect(keys.summary).to include("no key for stage development")
      expect { keys.active! }.to raise_error(Wsjrdp::Credentials::NoKeyError, /no key for stage development/)
    end

    it "logs one warning and nothing else" do
      output = StringIO.new
      keys("", stage: "production").log_summary(Logger.new(output))

      expect(output.string.lines.size).to eq(1)
      expect(output.string).to include("WARN", "no key for stage production")
    end
  end

  describe "the label" do
    it "is stripped" do
      expect(keys(nil, stage: "development", label: "  laptop-a \n").label).to eq("laptop-a")
    end

    it "is nil when empty" do
      expect(keys(nil, stage: "development", label: " ").label).to be_nil
      expect(keys(nil, stage: "development").label).to be_nil
    end

    it "is named in the summary" do
      keys = keys("development:#{secret_a}", stage: "development", label: "laptop-a")
      expect(keys.summary).to end_with("label laptop-a")
    end
  end

  describe "outside production" do
    it "refuses to start with a production secret" do
      expect { keys("production:#{secret_a}", stage: "development") }
        .to raise_error(described_class::ConfigurationError, /production secret/)
    end

    it "refuses a production secret in a staging stage as well" do
      expect { keys("staging:#{secret_a},production:#{secret_b}", stage: "staging") }
        .to raise_error(described_class::ConfigurationError, /entry 2/)
    end

    it "refuses malformed entries" do
      ["Development:#{secret_a}", "development-x:#{secret_a}", "development:#{"a" * 63}",
        "development:#{"a" * 65}", "development:#{"a" * 128}", "development:#{"g" * 64}",
        "development", ":#{secret_a}"].each do |raw|
        expect { keys(raw, stage: "development") }.to raise_error(described_class::ConfigurationError), raw
      end
    end

    it "refuses a secret given twice, in any case and in any stage" do
      expect { keys("development:#{secret_a},development:#{secret_a.upcase}", stage: "development") }
        .to raise_error(described_class::ConfigurationError, /given again/)
      expect { keys("test:#{secret_a},development:#{secret_a}", stage: "development") }
        .to raise_error(described_class::ConfigurationError, /given again/)
    end

    it "never puts a secret into its messages" do
      expect { keys("development:#{secret_a},development:#{secret_a},production:#{secret_b}", stage: "development") }
        .to raise_error(described_class::ConfigurationError) { |error|
          expect(error.message).not_to include(secret_a)
          expect(error.message).not_to include(secret_b)
        }
    end
  end

  describe "a value that is not valid text" do
    let(:invalid) { (+"\xff").force_encoding("UTF-8") }

    it "is a problem of its entry, which production logs and ignores" do
      keys = keys("production:#{secret_a},production:#{invalid}#{secret_b}", stage: "production")

      expect(keys.keys.map(&:fingerprint)).to eq([fingerprint(secret_a)])
      expect(keys.problems).to eq(["entry 2: not valid text"])
    end

    it "is a problem in a list of entries as well" do
      keys = keys(["production:#{secret_a}", "#{invalid}production:#{secret_b}"], stage: "production")
      expect(keys.problems).to eq(["entry 2: not valid text"])
    end

    it "stops any other stage, showing nothing of it" do
      expect { keys("development:#{secret_a}#{invalid}", stage: "development") }
        .to raise_error(described_class::ConfigurationError, /entry 1: not valid text/) { |error|
          expect(error.message).not_to include(secret_a)
        }
    end

    it "is a problem in the label, which production logs and ignores" do
      keys = keys("production:#{secret_a}", stage: "production", label: "laptop#{invalid}")

      expect(keys.label).to be_nil
      expect(keys.problems).to eq(["the label (#{described_class::LABEL_ENV_NAME}) is not valid text"])
      expect { keys(nil, stage: "development", label: invalid) }.to raise_error(described_class::ConfigurationError)
    end
  end

  describe "a label tagged US-ASCII, as ENV is under a C or POSIX locale" do
    it "is read as UTF-8 and kept" do
      label = (+"l\xc3\xa4ptop").force_encoding("US-ASCII")
      keys = keys(nil, stage: "development", label: label)

      expect(keys.label).to eq("läptop")
      expect(keys.label.encoding).to eq(Encoding::UTF_8)
      expect(keys.problems).to eq([])
    end
  end

  describe "a secret typed into the stage" do
    it "is never shown: a long stage is \"another stage\"" do
      keys = keys("#{secret_a}:#{secret_b}", stage: "production")
      output = StringIO.new
      keys.log_summary(Logger.new(output))

      expect(keys.warnings).to eq(["entry 1 belongs to another stage, this is production"])
      expect(output.string).not_to include(secret_a)
    end

    it "is not shown when it is the instance's own stage either" do
      keys = keys(nil, stage: secret_a)
      expect([keys.summary, keys.inspect, keys.to_json].join).not_to include(secret_a)
      expect { keys("x:y", stage: secret_a) }
        .to raise_error(described_class::ConfigurationError) { |error| expect(error.message).not_to include(secret_a) }
    end

    it "is shown when it is short" do
      expect(keys("staging:#{secret_a}", stage: "production").warnings.join).to include("stage staging")
    end

    it "is shown up to 32 characters, and from 33 on is \"another stage\"" do
      expect(keys("#{"s" * 32}:#{secret_a}", stage: "production").warnings)
        .to eq(["entry 1 belongs to stage #{"s" * 32}, this is production"])
      expect(keys("#{"s" * 33}:#{secret_a}", stage: "production").warnings)
        .to eq(["entry 1 belongs to another stage, this is production"])
    end

    it "keeps 32 for the instance's own stage, even where a name may have 48" do
      expect(keys(nil, stage: "s" * 32).summary).to include("stage #{"s" * 32};")
      expect(keys(nil, stage: "s" * 33).summary).to include("stage (not a stage);")
    end
  end

  describe "in production" do
    it "starts despite bad entries, ignoring them" do
      keys = keys("production:#{secret_a},development:#{secret_b},broken,production:#{secret_a}", stage: "production")

      expect(keys.keys.map(&:fingerprint)).to eq([fingerprint(secret_a)])
      expect(keys.problems.join).to include("entry 3", "entry 4", "given again")
      expect(keys.warnings.join).to include("stage development")
    end

    it "logs problems as errors and warnings as warnings, by entry number" do
      output = StringIO.new
      keys("production:#{secret_a},broken,staging:#{secret_b}", stage: "production").log_summary(Logger.new(output))

      expect(output.string).to match(/ERROR.*entry 2/)
      expect(output.string).to match(/WARN.*entry 3/)
      expect(output.string).to match(/INFO.*active #{Regexp.escape(fingerprint(secret_a))}/)
    end
  end

  describe "the committed, public keys" do
    let(:golden_secret) { CredentialsSpec::GOLDEN_VECTOR_KEY }
    let(:public_secrets) { [test_secret, golden_secret] }

    it "are named by PUBLIC_FINGERPRINTS, exactly: the key of test.yml and of the golden-vector spec" do
      expect(CredentialsSpec.test_settings_secrets.size).to eq(1)
      expect(public_secrets).to all(match(/\A\h{64}\z/))
      expect(described_class::PUBLIC_FINGERPRINTS)
        .to match_array(public_secrets.map { |secret| described_class.fingerprint_of(secret) })
    end

    it "are logged and ignored in production, the other entries still counting" do
      keys = keys("production:#{test_secret},production:#{secret_b},production:#{golden_secret.upcase}",
        stage: "production")

      expect(keys.keys.map(&:fingerprint)).to eq([fingerprint(secret_b)])
      expect(keys.problems).to eq(["entry 1: the committed, public key of test",
        "entry 3: the committed, public key of test"])
    end

    it "stop development and any other stage from starting" do
      %w[development staging].each do |stage|
        public_secrets.each do |secret|
          expect { keys("#{stage}:#{secret}", stage: stage) }
            .to raise_error(described_class::ConfigurationError, /entry 1: the committed, public key of test/)
        end
      end
    end

    it "are accepted in the stage test" do
      keys = keys("test:#{test_secret},test:#{golden_secret}", stage: "test")
      expect(keys.keys.map(&:fingerprint)).to eq(public_secrets.map { |secret| fingerprint(secret) })
    end

    it "never show in a message or the log" do
      output = StringIO.new
      keys = keys("production:#{test_secret},production:#{golden_secret}", stage: "production")
      keys.log_summary(Logger.new(output))
      expect { keys("staging:#{test_secret}", stage: "staging") }.to raise_error(described_class::ConfigurationError) { |error|
        expect(error.message).not_to include(test_secret)
      }

      shown = [output.string, keys.problems, keys.summary, keys.inspect].join
      public_secrets.each { |secret| expect(shown.downcase).not_to include(secret) }
    end
  end

  describe "what it shows" do
    let(:shown_keys) do
      keys("production:#{secret_a},development:#{secret_c},broken", stage: "production", label: "box")
    end

    it "shows fingerprints, never secrets, wherever it is printed or logged" do
      keys = shown_keys
      output = StringIO.new
      keys.log_summary(Logger.new(output))
      shown = [keys.inspect, keys.to_s, keys.to_json, keys.as_json.to_s, keys.pretty_inspect,
        keys.active.inspect, keys.active.to_s, keys.active.to_json, keys.active.pretty_inspect,
        ActiveSupport::JSON.encode(keys), ActiveSupport::JSON.encode(keys.active), JSON.generate([keys.active]),
        keys.summary, keys.problems, keys.warnings, output.string].join

      expect(shown).to include(fingerprint(secret_a))
      [secret_a, secret_c, [secret_a].pack("H*")].each { |secret| expect(shown).not_to include(secret) }
    end

    it "refuses Marshal and YAML" do
      [shown_keys, shown_keys.active].each do |object|
        expect { Marshal.dump(object) }.to raise_error(TypeError)
        expect { YAML.dump(object) }.to raise_error(TypeError)
      end
    end
  end
end
