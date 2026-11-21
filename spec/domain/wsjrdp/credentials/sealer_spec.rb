# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Standalone, without Rails (see standalone.rb).
require_relative "standalone"

# Sealing and opening the value of one secret field. The keys and values
# are made up.
describe Wsjrdp::Credentials::Sealer do
  let(:keys) { Wsjrdp::Credentials::Keys.new("test:#{"1" * 64},test:#{"2" * 64}", stage: "test") }
  let(:key) { keys.keys.first }
  let(:other_key) { keys.keys.last }
  let(:account) { {stage: "test", kind: "mail_account", account_key: "finanzen", field: "smtp_password"} }
  let(:secret) { "made-up secret" }

  def seal(value = secret, key: self.key, **purpose) = described_class.seal(value, key: key, **account, **purpose)

  def unseal(text, key: self.key, **purpose) = described_class.unseal(text, key: key, **account, **purpose)

  def encryptor = ActiveSupport::MessageEncryptor.new(key.bytes, cipher: "aes-256-gcm", serializer: JSON)

  # A text sealed with the right key and purpose by other code.
  def foreign(content) = encryptor.encrypt_and_sign(content, purpose: described_class.purpose(**account))

  it "names its scheme" do
    expect(described_class::SCHEME).to eq("rails-me-v1")
  end

  it "builds the purpose credential/<stage>/<kind>/<account_key>/<field>" do
    expect(described_class.purpose(**account)).to eq("credential/test/mail_account/finanzen/smtp_password")
  end

  it "seals and opens for an account key that is no name, which is part of the purpose" do
    key_name = "foo@worldscoutjamboree.de"
    text = seal(account_key: key_name)

    expect(described_class.purpose(**account, account_key: key_name))
      .to eq("credential/test/mail_account/foo@worldscoutjamboree.de/smtp_password")
    expect(unseal(text, account_key: key_name)).to eq(secret)
    expect(unseal(text, account_key: "foo@worldscoutjamboree.org")).to be_nil
  end

  describe "a sealed text" do
    it "opens to the value with the same key and purpose: a string, an integer, true or false" do
      ["made-up secret", "", "ünïcode", 587, -1, 2**70, true, false].each do |value|
        expect(unseal(seal(value))).to eq(value), value.inspect
      end
    end

    it "opens to false as false, never as nil" do
      expect(unseal(seal(false))).to be(false)
    end

    it "holds exactly {\"value\" => value}" do
      expect(encryptor.decrypt_and_verify(seal, purpose: described_class.purpose(**account))).to eq("value" => secret)
    end

    it "differs every time" do
      expect(seal).not_to eq(seal)
    end

    it "holds no value in plain text" do
      expect(seal).not_to include(secret)
    end

    it "is Rails' outer form, ciphertext--nonce--tag in Base64" do
      parts = seal.split("--")

      expect(parts.size).to eq(3)
      expect(parts.map { |part| Base64.strict_decode64(part).bytesize }.drop(1)).to eq([12, 16])
    end
  end

  describe "what cannot be opened here" do
    let(:text) { seal }

    it "is nil for another key" do
      expect(unseal(text, key: other_key)).to be_nil
    end

    it "is nil for another stage, kind, account or field" do
      expect(unseal(text, stage: "development")).to be_nil
      expect(unseal(text, kind: "api_key")).to be_nil
      expect(unseal(text, account_key: "default")).to be_nil
      expect(unseal(text, field: "imap_password")).to be_nil
    end

    it "is nil for a changed character anywhere" do
      [0, text.index("--") - 1, text.index("--") + 2, text.length - 3].each do |index|
        changed = text.dup
        changed[index] = (changed[index] == "A") ? "B" : "A"
        expect(unseal(changed)).to be_nil, "position #{index}"
      end
    end

    it "is nil for a shortened or longer text" do
      expect(unseal(text[0..-2])).to be_nil
      expect(unseal("#{text}=")).to be_nil
      expect(unseal("A#{text}")).to be_nil
    end

    it "is nil for anything that is no sealed text" do
      ["", "x", "--", "----", "#{"A" * 4}--#{"A" * 16}--#{"A" * 22}==", "é" * 40, "\xff".b * 40,
        nil, 42, :symbol, ["a"], {"a" => 1}].each do |input|
        expect(unseal(input)).to be_nil, input.inspect
      end
    end

    it "is nil without a key" do
      expect(unseal(text, key: nil)).to be_nil
    end

    describe "a text sealed with the right key and purpose, but holding anything else" do
      {
        "a bare string" => "a text",
        "a bare number" => 5,
        "bare true" => true,
        "nil" => nil,
        "an array" => ["a"],
        "an empty hash" => {},
        "another name" => {"val" => "a"},
        "a second name" => {"value" => "a", "other" => "b"},
        "a nil value" => {"value" => nil},
        "a float value" => {"value" => 1.5},
        "an array value" => {"value" => ["a"]},
        "a hash value" => {"value" => {"a" => "b"}},
        "a json_class" => {"json_class" => "Object", "value" => "a"}
      }.each do |what, content|
        it "is nil for #{what}" do
          expect(unseal(foreign(content))).to be_nil
        end
      end

      it "opens when it is exactly the shape seal writes" do
        expect(unseal(foreign({"value" => secret}))).to eq(secret)
      end
    end
  end

  describe "refusals" do
    it "refuses purpose parts outside the grammar, when sealing and when opening" do
      [{stage: "Test"}, {stage: "te/st"}, {stage: ""}, {stage: nil}, {kind: "mail/account"},
        {kind: "Mail_account"}, {kind: "mail__account"}, {kind: "_mail"}, {kind: :mail_account},
        {account_key: "finanzen/x"}, {account_key: "Finanzen"}, {account_key: "-finanzen"},
        {account_key: "fin anzen"}, {account_key: "a" * 65}, {account_key: "a\u0301"},
        {field: "smtp/password"}, {field: "Smtp"}, {field: ""}, {field: nil}, {field: "a" * 49}].each do |part|
        expect { seal(**part) }.to raise_error(described_class::Refused), part.inspect
        expect { unseal("x", **part) }.to raise_error(described_class::Refused), part.inspect
      end
    end

    it "refuses to seal without a key" do
      expect { seal(key: nil) }.to raise_error(Wsjrdp::Credentials::NoKeyError)
    end

    it "refuses a key that is not a Keys::Key" do
      expect { seal(key: "1" * 32) }.to raise_error(described_class::Refused)
      expect { unseal("x", key: "1" * 32) }.to raise_error(described_class::Refused)
    end

    it "refuses a value that is not a string, an integer, true or false" do
      [nil, 1.5, :symbol, ["a"], {"value" => "a"}, Object.new, (+"\xff").force_encoding("UTF-8"),
        "made-up\u0000secret"].each do |bad|
        expect { seal(bad) }.to raise_error(described_class::Refused), bad.class.name
      end
    end

    it "never names a value or the key in a refusal" do
      expect { seal(1.5) }.to raise_error(described_class::Refused) { |error|
        expect(error.message).to include("smtp_password")
        expect(error.message).not_to include("1.5")
      }
    end
  end
end
