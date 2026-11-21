# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Standalone, without Rails (see standalone.rb).
require_relative "standalone"
require "yaml"

# The value object a consumer gets: public fields with [], secret ones with
# #secret, and no trace of any value in any printed form. The values are made
# up.
describe Wsjrdp::Credentials::Credential do
  let(:kind) { Wsjrdp::Credentials::Kinds.load.fetch("mail_account") }
  let(:fingerprint) { Wsjrdp::Credentials::Keys.fingerprint_of("1" * 64) }
  let(:values) do
    {"mail_from" => "finanzen@example.org", "smtp_host" => "mail.example.org", "smtp_port" => 587,
     "smtp_password" => "made-up-password"}
  end
  let(:credential) do
    described_class.new(kind: kind, account_key: "finanzen", stage: "test", values: values, key_fingerprint: fingerprint)
  end

  describe "reading" do
    it "gives a public field with []" do
      expect(credential[:smtp_host]).to eq("mail.example.org")
      expect(credential["smtp_port"]).to eq(587)
    end

    it "gives nil for a field of the kind that is not set" do
      expect(credential[:sent_folder]).to be_nil
      expect(credential.secret(:imap_password)).to be_nil
    end

    it "refuses a secret field with [] and points to #secret" do
      expect { credential[:smtp_password] }
        .to raise_error(described_class::WrongAccess, /secret field; read it with #secret\(:smtp_password\)/)
    end

    it "gives a secret field with #secret" do
      expect(credential.secret(:smtp_password)).to eq("made-up-password")
      expect(credential.secret("smtp_password")).to eq("made-up-password")
    end

    it "refuses a public field with #secret" do
      expect { credential.secret(:smtp_host) }.to raise_error(described_class::WrongAccess, /\[:smtp_host\]/)
    end

    it "refuses an unknown field either way" do
      expect { credential[:api_key] }.to raise_error(described_class::UnknownField, /mail_account has no field api_key/)
      expect { credential.secret(:api_key) }.to raise_error(described_class::UnknownField)
    end

    it "gives its kind, account key, stage, field names and key fingerprint" do
      expect(credential).to have_attributes(kind: kind, kind_name: "mail_account", account_key: "finanzen",
        stage: "test", key_fingerprint: fingerprint, field_names: %w[mail_from smtp_host smtp_port smtp_password])
    end

    it "is frozen, its values too" do
      expect(credential).to be_frozen
      expect(credential[:smtp_host]).to be_frozen
      expect(credential.secret(:smtp_password)).to be_frozen
    end
  end

  describe "building" do
    def build(**options)
      described_class.new(kind: kind, account_key: "finanzen", stage: "test", values: values,
        key_fingerprint: fingerprint, **options)
    end

    it "refuses a value of a field the kind does not have, naming the field only" do
      expect { build(values: values.merge("api_key" => "made-up")) }
        .to raise_error(ArgumentError, /no field api_key/) { |error| expect(error.message).not_to include("made-up") }
    end

    it "does not repeat a field name that may be a value in the wrong place" do
      expect { build(values: values.merge("made-up-password" => "x")) }
        .to raise_error(ArgumentError) { |error| expect(error.message).not_to include("made-up-password") }
    end

    it "refuses an account key or a stage outside the grammar" do
      expect { build(account_key: "Finanzen") }.to raise_error(ArgumentError)
      expect { build(stage: "te/st") }.to raise_error(ArgumentError)
    end

    it "takes symbol names" do
      expect(build(values: {smtp_host: "mail.example.org"})[:smtp_host]).to eq("mail.example.org")
    end
  end

  describe "what it shows" do
    let(:secret_values) { %w[made-up-password finanzen@example.org mail.example.org 587] }

    def expect_no_value(text)
      secret_values.each { |value| expect(text).not_to include(value) }
    end

    it "shows names and the key's fingerprint in inspect and to_s" do
      expect(credential.inspect).to eq("#<Wsjrdp::Credentials::Credential mail_account/finanzen stage=test " \
        "fields=mail_from,smtp_host,smtp_port,smtp_password key=#{fingerprint}>")
      expect(credential.to_s).to eq(credential.inspect)
      expect("#{credential}").to eq(credential.inspect) # rubocop:disable Style/RedundantInterpolation
    end

    it "shows no value in pp, as_json, to_json or a JSON of a structure holding it" do
      shown = [credential.pretty_inspect, PP.pp({c: credential}, +""), credential.as_json.to_s, credential.to_json,
        ActiveSupport::JSON.encode(credential), ActiveSupport::JSON.encode([credential]), {c: credential}.to_json,
        JSON.generate({"c" => credential}), [credential].inspect, format("%p %s", credential, credential)]

      shown.each { |text| expect_no_value(text) }
      expect(credential.as_json).to eq("kind" => "mail_account", "account_key" => "finanzen", "stage" => "test",
        "fields" => %w[mail_from smtp_host smtp_port smtp_password], "key_fingerprint" => fingerprint)
    end

    it "refuses YAML" do
      expect { credential.to_yaml }.to raise_error(TypeError)
      expect { YAML.dump({"c" => credential}) }.to raise_error(TypeError)
    end

    it "refuses Marshal" do
      expect { Marshal.dump(credential) }.to raise_error(TypeError)
      expect { Marshal.dump([credential]) }.to raise_error(TypeError)
    end

    it "shows no value in an error message" do
      [-> { credential[:smtp_password] }, -> { credential.secret(:smtp_host) }, -> { credential[:nope] }].each do |call|
        expect(&call).to raise_error(Wsjrdp::Credentials::Error) { |error| expect_no_value(error.message) }
      end
    end

    it "names an unknown field only when it is a valid name" do
      ["made-up-password", "a" * 64, (+"\xff").force_encoding("UTF-8")].each do |name|
        expect { credential[name] }.to raise_error(described_class::UnknownField) { |error|
          expect(error.message).to end_with("has no field (not a name)")
        }
      end
    end
  end
end
