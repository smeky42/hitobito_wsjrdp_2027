# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Standalone, without Rails (see standalone.rb).
require_relative "standalone"

# Casting and checking a set of values for a kind. The values are made up.
describe Wsjrdp::Credentials::Kind do
  let(:kinds) { Wsjrdp::Credentials::Kinds.load }
  let(:mail) { kinds.fetch("mail_account") }
  let(:moss) { kinds.fetch("moss_api") }
  let(:mail_values) { {"mail_from" => "finanzen@example.org", "smtp_host" => "mail.example.org"} }

  def problems(list) = list.map { |problem| [problem.field, problem.code] }

  # A kind with one field of type, optional and without a default.
  def one(type, **options)
    field = Wsjrdp::Credentials::Field.new(name: "f", type: type, **options)
    described_class.new(name: "k", fields: [field])
  end

  def cast_one(type, value, stage: "test", **options) = one(type, **options).cast({"f" => value}, stage: stage)

  describe "a set of values" do
    it "casts, fills defaults and keeps the kind's order" do
      result = mail.cast({"smtp_host" => "mail.example.org", "smtp_port" => "25", "mail_from" => "finanzen@example.org",
                          "smtp_password" => "made-up"}, stage: "test")

      expect(result).to be_valid
      expect(result.values).to eq("mail_from" => "finanzen@example.org", "smtp_host" => "mail.example.org",
        "smtp_port" => 25, "smtp_security" => "starttls", "smtp_password" => "made-up", "imap_port" => 993)
      expect(result.values.keys).to eq(%w[mail_from smtp_host smtp_port smtp_security smtp_password imap_port])
      expect(result.warnings).to eq([])
    end

    it "takes symbol names as well" do
      expect(mail.cast({mail_from: "finanzen@example.org", smtp_host: "mail.example.org"}, stage: "test")).to be_valid
    end

    it "counts nil and an empty string as not set" do
      result = mail.cast(mail_values.merge("smtp_port" => "", "smtp_username" => nil, "smtp_password" => ""),
        stage: "test")

      expect(result).to be_valid
      expect(result.values["smtp_port"]).to eq(587)
      expect(result.values).not_to have_key("smtp_username")
      expect(result.values).not_to have_key("smtp_password")
    end

    it "refuses a required field that is not set" do
      result = mail.cast({"smtp_host" => "", "smtp_password" => "made-up"}, stage: "test")

      expect(result).not_to be_valid
      expect(problems(result.errors)).to eq([["mail_from", :required], ["smtp_host", :required]])
    end

    it "takes nil as no values at all" do
      expect(problems(moss.cast(nil, stage: "test").errors)).to eq([["client_id", :required], ["client_secret", :required]])
    end

    it "takes a field the kind does not have as a further field, a text, after the kind's fields by name" do
      result = mail.cast(mail_values.merge("zone" => "eu", "smtp_tls" => "1", "note" => ""), stage: "test")

      expect(result).to be_valid
      expect(result.values.keys).to eq(%w[mail_from smtp_host smtp_port smtp_security imap_port smtp_tls zone])
      expect(result.values["smtp_tls"]).to eq("1")
    end

    it "refuses a further field whose value is no valid text" do
      result = mail.cast(mail_values.merge("count" => 5, "bad" => "a\u0000b"), stage: "test")
      expect(problems(result.errors)).to eq([["count", :not_a_string], ["bad", :not_valid_text]])
    end

    it "refuses a further field under a reserved name" do
      expect(problems(mail.cast(mail_values.merge("expires_at" => "x"), stage: "test").errors))
        .to eq([["expires_at", :reserved]])
    end

    it "says why a name cannot be a further field" do
      expect(%w[note smtp_host name Note].map { |name| mail.further_name_problem(name) })
        .to eq([nil, :field_of_the_kind, :reserved, :not_a_name])
    end

    it "does not fill in the default of a field whose value is wrong" do
      result = mail.cast(mail_values.merge("smtp_port" => "many"), stage: "test")

      expect(problems(result.errors)).to eq([["smtp_port", :not_an_integer]])
      expect(result.values).not_to have_key("smtp_port")
    end

    describe "the result" do
      let(:result) do
        moss.cast({"client_id" => 4711, "client_secret" => "made-up-secret",
                   "base_url" => "http://made-up.example.org", "scope" => "made-up-scope"}, stage: "production")
      end
      let(:made_up) { %w[made-up-secret made-up.example.org made-up-scope] }

      it "never names a value in any printed form" do
        shown = [result.inspect, result.to_s, result.pretty_inspect, PP.pp({r: result}, +""), result.as_json.to_s,
          result.to_json, ActiveSupport::JSON.encode(result), ActiveSupport::JSON.encode([result]), {r: result}.to_json,
          JSON.generate({"r" => result}), format("%p %s", result, result), result.errors.map(&:to_s),
          result.errors.inspect, result.errors.to_json, result.warnings.map(&:to_s), result.warnings.inspect,
          result.warnings.to_json].join

        expect(problems(result.errors)).to eq([["client_id", :not_a_string]])
        expect(problems(result.warnings)).to eq([["base_url", :not_https]])
        made_up.each { |value| expect(shown).not_to include(value) }
      end

      it "gives field names and codes in as_json" do
        expect(result.as_json).to eq("fields" => %w[base_url client_secret scope],
          "errors" => [{"field" => "client_id", "code" => "not_a_string"}],
          "warnings" => [{"field" => "base_url", "code" => "not_https"}])
      end

      it "hands its values out through #values only" do
        expect(result.values["client_secret"]).to eq("made-up-secret")
        %i[to_h to_hash deconstruct_keys deconstruct].each { |name| expect(result).not_to respond_to(name) }
      end

      it "refuses Marshal and YAML" do
        expect { Marshal.dump(result) }.to raise_error(TypeError)
        expect { YAML.dump(result) }.to raise_error(TypeError)
      end

      it "is frozen, its parts too" do
        expect([result, result.values, result.errors, result.warnings]).to all(be_frozen)
      end
    end

    it "refuses values that are not a hash" do
      ["a=b", [["mail_from", "x"]], 5].each do |values|
        expect { mail.cast(values, stage: "test") }.to raise_error(ArgumentError, "the values are not a hash")
      end
    end

    it "names a further field only when it is a valid name" do
      result = mail.cast(mail_values.merge("made-up-password" => "1", "a" * 64 => "1", 5 => "1",
        (+"\xff").force_encoding("UTF-8") => "1", "smtp_tls" => 2), stage: "test")

      expect(problems(result.errors)).to eq([["(not a name)", :not_a_name]] * 4 + [["smtp_tls", :not_a_string]])
    end
  end

  describe "the types" do
    it "string: a String as given, nothing else" do
      expect(cast_one("string", " a b ").values).to eq("f" => " a b ")
      [587, true, 1.5, :a, ["a"]].each do |value|
        expect(problems(cast_one("string", value).errors)).to eq([["f", :not_a_string]]), value.inspect
      end
    end

    it "integer: an Integer, from an Integer or decimal digits" do
      {"587" => 587, "-3" => -3, "+4" => 4, "0123" => 123, 993 => 993}.each do |value, cast|
        expect(cast_one("integer", value).values).to eq({"f" => cast}), value.inspect
      end
      [" 587", "587 ", "5.0", "0x10", "1e3", "abc", 5.0, true, "5\n"].each do |value|
        expect(problems(cast_one("integer", value).errors)).to eq([["f", :not_an_integer]]), value.inspect
      end
    end

    it "integer: only what a bigint holds" do
      [2**63 - 1, -(2**63), "9223372036854775807", "-9223372036854775808"].each do |value|
        expect(cast_one("integer", value).errors).to eq([]), value.inspect
      end
      [2**63, "9223372036854775808", "1" * 140_000, -(2**63) - 1].each do |value|
        expect(problems(cast_one("integer", value).errors)).to eq([["f", :not_an_integer]]), value.to_s[0, 30]
      end
    end

    it "boolean: true or false" do
      {true => true, false => false, "true" => true, "false" => false, "1" => true, "0" => false}.each do |value, cast|
        expect(cast_one("boolean", value).values).to eq({"f" => cast}), value.inspect
      end
      ["yes", "TRUE", 1, 0, "on"].each do |value|
        expect(problems(cast_one("boolean", value).errors)).to eq([["f", :not_a_boolean]]), value.inspect
      end
    end

    it "boolean: a false default is filled in" do
      expect(one("boolean", default: false).cast({}, stage: "test").values).to eq("f" => false)
    end

    it "enum: any text, its values being suggestions" do
      expect(cast_one("enum", "tls", values: %w[starttls tls]).values).to eq("f" => "tls")
      expect(cast_one("enum", "ssl", values: %w[starttls tls]).values).to eq("f" => "ssl")
      [:tls, 1].each do |value|
        expect(problems(cast_one("enum", value, values: %w[starttls tls]).errors))
          .to eq([["f", :not_a_string]]), value.inspect
      end
    end

    it "email: the form of an address" do
      expect(cast_one("email", "finanzen@example.org").values).to eq("f" => "finanzen@example.org")
      ["finanzen", "finanzen@", "@example.org", "fin anzen@example.org", " finanzen@example.org"].each do |value|
        expect(problems(cast_one("email", value).errors)).to eq([["f", :not_an_email]]), value.inspect
      end
      expect(problems(cast_one("email", 5).errors)).to eq([["f", :not_a_string]])
    end

    it "url: an absolute http or https URL with a host and without user info" do
      %w[https://public-api.getmoss.com http://localhost:3000/api HTTPS://example.org/x?y=1].each do |value|
        expect(cast_one("url", value).values).to eq({"f" => value}), value
      end
      ["ftp://example.org", "example.org", "/api", "https://", "https:example.org", "https://user:pw@example.org",
        "https://user@example.org", "https://exa mple.org", "mailto:a@example.org"].each do |value|
        expect(problems(cast_one("url", value).errors)).to eq([["f", :not_a_url]]), value
      end
    end
  end

  it "answers not_valid_text for a string of invalid encoding, for every type" do
    invalid = (+"\xff587").force_encoding("UTF-8")
    Wsjrdp::Credentials::Field::TYPES.each do |type|
      options = (type == "enum") ? {values: %w[a]} : {}
      expect(problems(cast_one(type, invalid, **options).errors)).to eq([["f", :not_valid_text]]), type
    end
  end

  it "answers not_valid_text for a string with a NUL character, for every type, secret or not" do
    ["made-up\u0000secret", "\u0000", "https://example.org/\u0000", "587\u0000"].each do |with_nul|
      Wsjrdp::Credentials::Field::TYPES.each do |type|
        options = (type == "enum") ? {values: [with_nul]} : {}
        expect(problems(cast_one(type, with_nul, **options).errors)).to eq([["f", :not_valid_text]]), type
      end
    end
    field = Wsjrdp::Credentials::Field.new(name: "f", type: "string", secret: true)
    expect(field.cast("made-up\u0000secret")).to eq([nil, :not_valid_text])
  end

  describe "a url that is not https" do
    it "is a warning in production, and saved all the same" do
      result = cast_one("url", "http://example.org", stage: "production")

      expect(result).to be_valid
      expect(result.values).to eq("f" => "http://example.org")
      expect(problems(result.warnings)).to eq([["f", :not_https]])
    end

    it "says nothing in any other stage" do
      %w[staging development test].each do |stage|
        expect(cast_one("url", "http://example.org", stage: stage).warnings).to eq([]), stage
      end
    end

    it "is no warning when it is https" do
      expect(cast_one("url", "https://example.org", stage: "production").warnings).to eq([])
    end

    it "warns for a default as well" do
      kind = one("url", default: "http://example.org")
      expect(problems(kind.cast({}, stage: "production").warnings)).to eq([["f", :not_https]])
    end
  end
end
