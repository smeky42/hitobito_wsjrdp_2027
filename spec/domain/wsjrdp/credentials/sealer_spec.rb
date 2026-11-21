# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Standalone, without Rails (see standalone.rb).
require_relative "standalone"

# Sealing and opening the fields of one account. The keys are made up.
describe Wsjrdp::Credentials::Sealer do
  let(:keys) { Wsjrdp::Credentials::Keys.new("test:#{"1" * 64},test:#{"2" * 64}", stage: "test") }
  let(:key) { keys.keys.first }
  let(:other_key) { keys.keys.last }
  let(:account) { {stage: "test", kind: "mail_account", account_key: "finanzen"} }
  let(:fields) do
    {"smtp_host" => "mail.example.org", "smtp_port" => 587, "smtp_password" => "made-up secret",
     "tls" => true, "imap_host" => nil}
  end

  def seal(fields = self.fields, key: self.key, **purpose) = described_class.seal(fields, key: key, **account, **purpose)

  def unseal(text, key: self.key, **purpose) = described_class.unseal(text, key: key, **account, **purpose)

  it "names its scheme" do
    expect(described_class::SCHEME).to eq("rails-me-v1")
  end

  it "builds the purpose credential/<stage>/<kind>/<account_key>" do
    expect(described_class.purpose(**account)).to eq("credential/test/mail_account/finanzen")
  end

  describe "a sealed text" do
    it "opens to the fields with the same key and purpose" do
      expect(unseal(seal)).to eq(fields)
    end

    it "differs every time" do
      expect(seal).not_to eq(seal)
    end

    it "holds no field in plain text" do
      text = seal
      expect(text).not_to include("made-up secret")
      expect(text).not_to include("mail.example.org")
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

    it "is nil for another stage, kind or account" do
      expect(unseal(text, stage: "development")).to be_nil
      expect(unseal(text, kind: "api_key")).to be_nil
      expect(unseal(text, account_key: "default")).to be_nil
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

    describe "a text sealed by other code, opening to what seal would refuse" do
      def foreign(content)
        encryptor = ActiveSupport::MessageEncryptor.new(key.bytes, cipher: "aes-256-gcm", serializer: JSON)
        encryptor.encrypt_and_sign(content, purpose: described_class.purpose(**account))
      end

      {
        "a nested hash" => {"a" => {"b" => "c"}},
        "an array value" => {"a" => ["b"]},
        "a float value" => {"a" => 1.5},
        "a json_class field" => {"json_class" => "Object", "a" => "b"},
        "an array" => [["a", "b"]],
        "a string" => "a text",
        "a number" => 5,
        "nil" => nil
      }.each do |what, content|
        it "is nil for #{what}" do
          expect(unseal(foreign(content))).to be_nil
        end
      end

      it "opens when it is of the shape seal takes" do
        expect(unseal(foreign(fields))).to eq(fields)
      end
    end

    it "is nil for a sealed value that is not a hash" do
      encryptor = ActiveSupport::MessageEncryptor.new(key.bytes, cipher: "aes-256-gcm", serializer: JSON)
      text = encryptor.encrypt_and_sign("a text", purpose: described_class.purpose(**account))

      expect(unseal(text)).to be_nil
    end
  end

  describe "refusals" do
    it "refuses purpose parts outside the grammar, when sealing and when opening" do
      [{stage: "Test"}, {stage: "te/st"}, {stage: ""}, {stage: nil}, {kind: "mail/account"},
        {kind: "Mail_account"}, {kind: "mail__account"}, {kind: "_mail"}, {kind: :mail_account},
        {account_key: "finanzen/x"}, {account_key: "fin-anzen"}, {account_key: "1finanzen"}].each do |part|
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

    it "refuses fields that are not a plain flat hash of string names and JSON scalars" do
      [nil, "text", [["a", "b"]], {a: "b"}, Class.new(Hash).new.merge!("a" => "b"), {"a" => 1.5}, {"a" => ["b"]}, {"a" => {"b" => 1}},
        {"a" => :b}, {"a" => (+"\xff").force_encoding("UTF-8")}].each do |bad|
        expect { seal(bad) }.to raise_error(described_class::Refused), bad.inspect
      end
    end

    it "says that a plain Hash is wanted when given a Hash subclass" do
      expect { seal(Class.new(Hash).new.merge!("a" => "b")) }
        .to raise_error(described_class::Refused, "the fields are not a plain Hash")
    end

    it "never names a value or the key in a refusal" do
      expect { seal({"smtp_password" => 1.5}) }.to raise_error(described_class::Refused) { |error|
        expect(error.message).to include("smtp_password")
        expect(error.message).not_to include("1.5")
      }
    end

    it "names a field only when it is a valid name" do
      ["a" * 64, "made-up secret"].each do |name|
        expect { seal({name => 1.5}) }.to raise_error(described_class::Refused) { |error|
          expect(error.message).not_to include(name)
          expect(error.message).to include("(not a name)")
        }
      end
    end

    describe "the field name json_class" do
      it "is refused: JSON.load would take its value for a class to build" do
        expect(described_class::JSON_CREATE_ID).to eq(JSON.create_id)
        expect { seal(fields.merge("json_class" => "String")) }
          .to raise_error(described_class::Refused, /json_class: the name is reserved/)
      end

      it "would, with a value such as String, make a text that no longer opens" do
        encryptor = ActiveSupport::MessageEncryptor.new(key.bytes, cipher: "aes-256-gcm", serializer: JSON)
        text = encryptor.encrypt_and_sign({"json_class" => "String", "a" => "b"},
          purpose: described_class.purpose(**account))

        expect(unseal(text)).to be_nil
      end
    end
  end
end
