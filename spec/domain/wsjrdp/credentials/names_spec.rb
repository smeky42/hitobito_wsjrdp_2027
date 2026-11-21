# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Standalone, without Rails (see standalone.rb).
require_relative "standalone"

# The one rule for a kind, an account key and a field name (the grammar, at
# most 48 characters), and what a message may repeat of a name or a stage.
# The secret below is made up.
describe Wsjrdp::Credentials do
  let(:hex_secret) { "a1" * 32 }

  describe ".name?" do
    it "accepts a name of the grammar of up to 48 characters" do
      expect(described_class::NAME_LENGTH).to eq(48)
      expect(described_class.name?("a" * 48)).to be(true)
      expect(described_class.name?("mail_account")).to be(true)
    end

    it "refuses 49 characters, a name outside the grammar and what is no text" do
      ["a" * 49, "Mail", "a__b", "1a", "", nil, :mail, (+"\xff").force_encoding("UTF-8")].each do |value|
        expect(described_class.name?(value)).to be(false), value.inspect
      end
    end

    it "refuses a 64-hex secret, which matches the grammar but not the length" do
      expect(hex_secret).to match(described_class::NAME_FORMAT)
      expect(described_class.name?(hex_secret)).to be(false)
    end
  end

  describe ".shown_name" do
    it "repeats a valid name of up to 48 characters" do
      expect(described_class.shown_name("a" * 48)).to eq("a" * 48)
      expect(described_class.shown_name(:smtp_host)).to eq("smtp_host")
    end

    it "shows 49 characters, a 64-hex secret or no name as the placeholder" do
      ["a" * 49, hex_secret, "made-up secret", 5].each do |value|
        expect(described_class.shown_name(value)).to eq("(not a name)"), value.inspect
      end
    end
  end

  describe ".shown_stage" do
    it "repeats a stage of up to 32 characters" do
      expect(described_class::SHOWN_STAGE_LENGTH).to eq(32)
      expect(described_class.shown_stage("a" * 32)).to eq("a" * 32)
    end

    it "shows 33 characters, a 64-hex secret or no stage as the placeholder" do
      ["a" * 33, hex_secret, "Staging", nil].each do |value|
        expect(described_class.shown_stage(value)).to eq("(not a stage)"), value.inspect
      end
    end
  end

  describe "the places that check a name" do
    let(:kind) { Wsjrdp::Credentials::Kinds.load.fetch("mail_account") }
    let(:key) { Wsjrdp::Credentials::Keys.new("test:#{"1" * 64}", stage: "test").active }

    def credential(account_key)
      Wsjrdp::Credentials::Credential.new(kind: kind, account_key: account_key, stage: "test", values: {},
        key_fingerprint: key.fingerprint)
    end

    it "takes an account key of 48 characters, and refuses one of 49" do
      expect(Wsjrdp::Credentials::Sealer.purpose(stage: "test", kind: "a" * 48, account_key: "b" * 48))
        .to eq("credential/test/#{"a" * 48}/#{"b" * 48}")
      expect(credential("b" * 48).account_key).to eq("b" * 48)

      expect { Wsjrdp::Credentials::Sealer.purpose(stage: "test", kind: "a" * 49, account_key: "b") }
        .to raise_error(Wsjrdp::Credentials::Sealer::Refused, /at most 48 characters/)
      expect { Wsjrdp::Credentials::Sealer.purpose(stage: "test", kind: "a", account_key: "b" * 49) }
        .to raise_error(Wsjrdp::Credentials::Sealer::Refused, /at most 48 characters/)
      expect { credential("b" * 49) }.to raise_error(ArgumentError, /at most 48 characters/)
    end

    it "never repeats a 64-hex secret given as a name" do
      result = kind.cast({hex_secret => "x"}, stage: "test")
      expect([result.errors.first.field, result.errors.first.code]).to eq(["(not a name)", :unknown])
      expect([result.inspect, result.to_json].join).not_to include(hex_secret)
      expect { credential(hex_secret) }.to raise_error(ArgumentError) { |error| expect(error.message).not_to include(hex_secret) }
      expect { Wsjrdp::Credentials::Kinds.load.fetch(hex_secret) }
        .to raise_error(Wsjrdp::Credentials::Kinds::UnknownKind) { |error| expect(error.message).not_to include(hex_secret) }
      expect { Wsjrdp::Credentials::Sealer.seal({hex_secret => 1.5}, key: key, stage: "test", kind: "k", account_key: "a") }
        .to raise_error(Wsjrdp::Credentials::Sealer::Refused) { |error| expect(error.message).not_to include(hex_secret) }
    end
  end
end
