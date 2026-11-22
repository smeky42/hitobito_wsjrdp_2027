# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Standalone, without Rails (see standalone.rb).
require_relative "standalone"

# The rule for a kind and a field name (the grammar, at most 48
# characters), the wider one for an account key (at most 64 characters,
# folded to lower case and NFC), and what a message may repeat of a name or
# a stage.
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

  describe "an account key" do
    it "takes lower-case letters of any script and 0-9, joined by single _ @ , . + -, up to 64 characters" do
      expect(described_class::ACCOUNT_KEY_LENGTH).to eq(64)
      ["foo@worldscoutjamboree.de", "finanzen", "1kasse", "x+y,z.w-v_u", "müller", "straße", "東京", "a" * 64,
        "a1_b2"].each do |value|
        expect(described_class.account_key?(value)).to be(true), value.inspect
      end
    end

    it "refuses upper case, other characters, marks, invisible letters, special characters in a row or at an end" do
      ["Foo", "a/b", "a b", "a\tb", "a:b", "a#b", "a€b", "-a", "_a", ".a", "a.", "a__b", "a.-b", "foo@@x", "a\u0301", "\u3164a", "a\u200Bb",
        "\u02B0a", "a١", "a" * 65, "", nil, :foo, "\uF900"].each do |value|
        expect(described_class.account_key?(value)).to be(false), value.inspect
      end
    end

    it "folds to lower case and NFC, whatever is given; no text stays as it is" do
      expect(described_class.account_key_of("Foo@WorldScoutJamboree.DE")).to eq("foo@worldscoutjamboree.de")
      expect(described_class.account_key_of("Mu\u0308ller")).to eq("müller")
      expect(described_class.account_key_of("STRASSE")).to eq("strasse")
      expect(described_class.account_key_of("\uF900")).to eq("\u8C48")
      expect(described_class.account_key_of(:Kasse)).to eq("kasse")
      expect(described_class.account_key_of("FINANZEN".b)).to eq("finanzen")
      expect(described_class.account_key_of(5)).to eq(5)
      invalid = (+"\xff").force_encoding("UTF-8")
      expect(described_class.account_key_of(invalid)).to equal(invalid)
      expect(described_class.account_key?(described_class.account_key_of("İ"))).to be(false)
    end

    it "is repeated in a message only when it is one" do
      expect(described_class.shown_account_key("foo@worldscoutjamboree.de")).to eq("foo@worldscoutjamboree.de")
      ["Foo", "made-up secret", "a" * 65].each do |value|
        expect(described_class.shown_account_key(value)).to eq("(not a name)"), value.inspect
      end
    end
  end

  describe ".text?" do
    it "answers false, never raises, for a String of an ASCII-incompatible encoding" do
      utf16 = "mail_account".encode("UTF-16LE")

      expect(described_class.text?(utf16)).to be(false)
      expect(described_class.name?(utf16)).to be(false)
      expect(described_class.stage?("test".encode("UTF-16BE"))).to be(false)
      expect(described_class.shown_name(utf16)).to eq("(not a name)")
      expect(described_class.text?("made-up text")).to be(true)
    end

    it "takes another encoding only for plain ASCII" do
      expect(described_class.text?("made-up \xE4".b)).to be(false)
      expect(described_class.text?("made-up ä".encode("ISO-8859-1"))).to be(false)
      expect(described_class.text?("made-up".b)).to be(true)
      expect(described_class.text?("made-up ä")).to be(true)
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

    it "takes a kind and a field of 48 characters and an account key of 64, and refuses one more" do
      expect(Wsjrdp::Credentials::Sealer.purpose(stage: "test", kind: "a" * 48, account_key: "b" * 64, field: "c" * 48))
        .to eq("credential/test/#{"a" * 48}/#{"b" * 64}/#{"c" * 48}")
      expect(credential("b" * 64).account_key).to eq("b" * 64)

      expect { Wsjrdp::Credentials::Sealer.purpose(stage: "test", kind: "a" * 49, account_key: "b", field: "c") }
        .to raise_error(Wsjrdp::Credentials::Sealer::Refused, /at most 48 characters/)
      expect { Wsjrdp::Credentials::Sealer.purpose(stage: "test", kind: "a", account_key: "b" * 65, field: "c") }
        .to raise_error(Wsjrdp::Credentials::Sealer::Refused, /at most 64 characters/)
      expect { Wsjrdp::Credentials::Sealer.purpose(stage: "test", kind: "a", account_key: "b", field: "c" * 49) }
        .to raise_error(Wsjrdp::Credentials::Sealer::Refused, /at most 48 characters/)
      expect { credential("b" * 65) }.to raise_error(ArgumentError, /at most 64 characters/)
    end

    it "never repeats a 64-hex secret given as a name" do
      result = kind.cast({hex_secret => "x"}, stage: "test")
      expect([result.errors.first.field, result.errors.first.code]).to eq(["(not a name)", :not_a_name])
      expect([result.inspect, result.to_json].join).not_to include(hex_secret)
      # A 64-hex secret is a valid account key; one with a character a key
      # does not take is refused without being repeated.
      expect { credential("#{hex_secret}/") }.to raise_error(ArgumentError) { |error| expect(error.message).not_to include(hex_secret) }
      expect { Wsjrdp::Credentials::Kinds.load.fetch(hex_secret) }
        .to raise_error(Wsjrdp::Credentials::Kinds::UnknownKind) { |error| expect(error.message).not_to include(hex_secret) }
      expect { Wsjrdp::Credentials::Sealer.seal("x", key: key, stage: "test", kind: "k", account_key: "a", field: hex_secret) }
        .to raise_error(Wsjrdp::Credentials::Sealer::Refused) { |error| expect(error.message).not_to include(hex_secret) }
      expect { Wsjrdp::Credentials::Sealer.seal(hex_secret.to_sym, key: key, stage: "test", kind: "k", account_key: "a", field: "f") }
        .to raise_error(Wsjrdp::Credentials::Sealer::Refused) { |error| expect(error.message).not_to include(hex_secret) }
    end
  end
end
