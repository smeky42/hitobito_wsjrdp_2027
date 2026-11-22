# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Standalone, without Rails (see standalone.rb).
require_relative "standalone"
require "tmpdir"

# The kind registry, config/wsjrdp_credential_kinds.yml, and how strictly it
# is read.
describe Wsjrdp::Credentials::Kinds do
  let(:registry_error) { described_class::RegistryError }

  def registry(kinds) = described_class.new({"kinds" => kinds}, source: "kinds_test")

  def self.kind_with(field) = {"k" => {"fields" => {"f" => field}}}

  describe "the committed file" do
    let(:kinds) { described_class.load }

    it "loads with its five kinds" do
      expect(kinds.names).to eq(%w[mail_account moss_api api_key basic_auth keycloak_admin])
    end

    it "gives the Keycloak admin login as the scripts use it" do
      keycloak = kinds.fetch(:keycloak_admin)

      expect(keycloak.field_names).to eq(%w[server_url realm server_realm client_id client_secret admin_username
        admin_password use_service_account])
      expect(keycloak.secret_field_names).to eq(%w[client_secret admin_password])
      expect(keycloak.fields.to_h { |field| [field.name, field.default] }.compact)
        .to eq("server_url" => "https://login.worldscoutjamboree.de", "server_realm" => "master",
          "client_id" => "admin-cli", "use_service_account" => false)
      expect(keycloak.field("use_service_account").type).to eq("boolean")
      expect(keycloak.fields.select(&:required?).map(&:name)).to eq(%w[server_url realm])
      expect(keycloak.title_field).to eq("admin_username")
    end

    it "gives the fields of a kind in order, secret and public" do
      mail = kinds.fetch(:mail_account)

      expect(mail.field_names).to eq(%w[mail_from smtp_host smtp_port smtp_security smtp_username smtp_password
        imap_host imap_port imap_username imap_password sent_folder])
      expect(mail.secret_field_names).to eq(%w[smtp_password imap_password])
      expect(mail.public_field_names).not_to include("smtp_password", "imap_password")
      expect(mail.title_field).to eq("mail_from")
      expect(mail.remind_days_before).to eq([])
    end

    it "gives the types, flags, defaults and values" do
      moss = kinds.fetch("moss_api")

      expect(moss.remind_days_before).to eq([30, 14, 3])
      expect(moss.field(:base_url)).to have_attributes(type: "url", required?: true, secret?: false,
        default: "https://public-api.getmoss.com")
      expect(moss.field("client_secret")).to have_attributes(type: "string", required?: true, secret?: true)
      expect(moss.field("scope")).to have_attributes(type: "enum", values: %w[read write], default: "read")
      expect(kinds.fetch("mail_account").field("smtp_port").default).to eq(587)
    end

    it "names an unknown kind, only when it is a valid name" do
      expect { kinds.fetch("generic") }.to raise_error(described_class::UnknownKind, /generic/)
      expect { kinds.fetch("a" * 64) }.to raise_error(described_class::UnknownKind) { |error|
        expect(error.message).not_to include("a" * 64)
      }
      expect(kinds["generic"]).to be_nil
    end

    it "is read once by .current" do
      described_class.reset!
      expect(described_class.current).to equal(described_class.current)
      expect(described_class.current.names).to include("moss_api")
    ensure
      described_class.reset!
    end
  end

  describe "a broken file" do
    around { |example| Dir.mktmpdir { |dir| @dir = dir and example.run } }

    def file(text)
      File.join(@dir, "kinds.yml").tap { |path| File.write(path, text) }
    end

    it "is refused when it is no YAML" do
      expect { described_class.load(file("kinds: [")) }.to raise_error(registry_error, /cannot be read/)
    end

    it "is refused when it holds a date or an alias" do
      expect { described_class.load(file("kinds:\n  k:\n    fields:\n      f: {type: string, default: 2026-01-01}\n")) }
        .to raise_error(registry_error, /cannot be read/)
      expect { described_class.load(file("a: &a {type: string}\nkinds:\n  k:\n    fields:\n      f: *a\n")) }
        .to raise_error(registry_error, /cannot be read/)
    end

    it "is refused when it is missing" do
      expect { described_class.load(File.join(@dir, "none.yml")) }.to raise_error(registry_error, /cannot be read/)
    end

    it "names the file in the error" do
      expect { described_class.load(file("kinds: {}\n")) }.to raise_error(registry_error, /kinds\.yml: kinds: is empty/)
    end
  end

  describe "strictness" do
    {
      "an unknown top-level key" => [{"kinds" => {"k" => {"fields" => {"f" => {"type" => "string"}}}}, "slots" => {}},
        /\(top level\): unknown key "slots"/],
      "no kinds" => [{}, /kinds: is not a mapping/],
      "a top level that is no mapping" => [["kinds"], /\(top level\): is not a mapping/]
    }.each do |what, (data, message)|
      it "refuses #{what}" do
        expect { described_class.new(data) }.to raise_error(registry_error, message)
      end
    end

    {
      "an unknown key of a kind" => [{"k" => {"fields" => {"f" => {"type" => "string"}}, "test" => "x"}},
        /kinds\.k: unknown key "test"/],
      "an unknown key of a field" => [kind_with("type" => "string", "max_length" => 3),
        /kinds\.k\.fields\.f: unknown key "max_length"/],
      "a kind name outside the grammar" => [{"Mail" => {"fields" => {"f" => {"type" => "string"}}}},
        /kinds\.Mail: the name is not lower-case snake/],
      "a kind name with a double underscore" => [{"mail__account" => {"fields" => {"f" => {"type" => "string"}}}},
        /kinds\.mail__account: the name/],
      "a kind name of 49 characters" => [{"a" * 49 => {"fields" => {"f" => {"type" => "string"}}}},
        /kinds\.a{49}: the name is longer than 48 characters/],
      "a field name of 49 characters" => [{"k" => {"fields" => {"a" * 49 => {"type" => "string"}}}},
        /kinds\.k\.fields\.a{49}: the name is longer than 48 characters/],
      "a long field name outside the grammar" => [{"k" => {"fields" => {"A" * 49 => {"type" => "string"}}}},
        /fields\.A{49}: the name is not lower-case snake/],
      "a field name outside the grammar" => [{"k" => {"fields" => {"smtp-host" => {"type" => "string"}}}},
        /kinds\.k\.fields\.smtp-host: the name is not lower-case snake/],
      "a kind without fields" => [{"k" => {}}, /kinds\.k\.fields: is missing/],
      "a kind with empty fields" => [{"k" => {"fields" => {}}}, /kinds\.k\.fields: is empty/],
      "a field that is no mapping" => [kind_with("string"), /kinds\.k\.fields\.f: is not a mapping/],
      "an unknown type" => [kind_with("type" => "password"), /kinds\.k\.fields\.f\.type: is not one of/],
      "a missing type" => [kind_with("required" => true), /kinds\.k\.fields\.f\.type: is not one of/],
      "a required flag that is no boolean" => [kind_with("type" => "string", "required" => "yes"),
        /fields\.f\.required: is not true or false/],
      "a secret flag that is no boolean" => [kind_with("type" => "string", "secret" => 1),
        /fields\.f\.secret: is not true or false/],
      "an enum without values" => [kind_with("type" => "enum"), /fields\.f\.values: is not a list of texts/],
      "an enum with empty values" => [kind_with("type" => "enum", "values" => []), /fields\.f\.values: is not a list/],
      "an enum with a value twice" => [kind_with("type" => "enum", "values" => %w[a a]), /names a value twice/],
      "an enum with a default outside its values" => [kind_with("type" => "enum", "values" => %w[a b], "default" => "c"),
        /fields\.f\.default: is no value of the field \(not_in_values\)/],
      "values on a field that is no enum" => [kind_with("type" => "string", "values" => %w[a]),
        /fields\.f\.values: only an enum has values/],
      "a default that is no value of its type" => [kind_with("type" => "integer", "default" => "many"),
        /fields\.f\.default: is no value of the field \(not_an_integer\)/],
      "a url default that is no url" => [kind_with("type" => "url", "default" => "ftp://example.org"),
        /fields\.f\.default: .*not_a_url/],
      "a default on a secret field" => [kind_with("type" => "string", "secret" => true, "default" => "made-up"),
        /fields\.f\.default: a secret field has no default/],
      "a title_field that is no field" => [{"k" => {"title_field" => "g", "fields" => {"f" => {"type" => "string"}}}},
        /kinds\.k\.title_field: is not a field of the kind/],
      "a title_field that is secret" => [{"k" => {"title_field" => "f", "fields" => {"f" => {"type" => "string",
                                                                                             "secret" => true}}}}, /kinds\.k\.title_field: is a secret field/],
      "a remind_days_before that is no list" => [{"k" => {"remind_days_before" => 30, "fields" => {"f" => {"type" => "string"}}}},
        /kinds\.k\.remind_days_before: is not a list of positive integers/],
      "a remind_days_before with zero" => [{"k" => {"remind_days_before" => [30, 0], "fields" => {"f" => {"type" => "string"}}}},
        /remind_days_before: is not a list of positive integers/],
      "a remind_days_before with a text" => [{"k" => {"remind_days_before" => ["30"], "fields" => {"f" => {"type" => "string"}}}},
        /remind_days_before: is not a list of positive integers/]
    }.each do |what, (kinds, message)|
      it "refuses #{what}" do
        expect { registry(kinds) }.to raise_error(registry_error, message)
      end
    end

    it "reserves name, created_at, valid_from and expires_at" do
      expect(described_class::RESERVED_FIELD_NAMES).to eq(%w[name created_at valid_from expires_at])
    end

    {
      "outside the grammar" => ["Smtp-Host", "the name is not lower-case snake"],
      "longer than 48 characters" => ["a" * 49, "the name is longer than 48 characters"],
      "reserved" => ["name", "the name is reserved"]
    }.each do |what, (name, message)|
      it "refuses a field name #{what} in a kind with a title_field, naming the place" do
        kinds = {"k" => {"title_field" => "f", "fields" => {name => {"type" => "string"}, "f" => {"type" => "string"}}}}
        expect { registry(kinds) }
          .to raise_error(registry_error, /\Akinds_test: kinds\.k\.fields\.#{Regexp.escape(name)}: #{message}\z/)
      end
    end

    it "refuses a bad field name next to a title_field that names it, as a missing field" do
      kinds = {"k" => {"title_field" => "name", "fields" => {"name" => {"type" => "string"}, "f" => {"type" => "string"}}}}
      expect { registry(kinds) }.to raise_error(registry_error, /fields\.name: the name is reserved; kinds\.k\.title_field: is not a field/)
    end

    described_class::RESERVED_FIELD_NAMES.each do |name|
      it "refuses the reserved field name #{name}" do
        expect { registry({"k" => {"fields" => {name => {"type" => "string"}}}}) }
          .to raise_error(registry_error, /kinds\.k\.fields\.#{name}: the name is reserved/)
      end
    end

    it "accepts names of exactly 48 characters, which a message can show" do
      name = "a" * 48
      kinds = registry({name => {"fields" => {name => {"type" => "string"}}}})

      expect(kinds.fetch(name).field_names).to eq([name])
      expect(Wsjrdp::Credentials.shown_name(name)).to eq(name)
    end

    it "accepts every type and an empty remind_days_before" do
      kinds = registry({"k" => {"remind_days_before" => [], "fields" => Wsjrdp::Credentials::Field::TYPES.to_h do |type|
        [type, (type == "enum") ? {"type" => type, "values" => %w[a]} : {"type" => type}]
      end}})

      expect(kinds.fetch("k").fields.map(&:type)).to eq(Wsjrdp::Credentials::Field::TYPES)
    end

    it "names every error at once" do
      expect { registry({"k" => {"fields" => {"f" => {"type" => "x"}, "name" => {"type" => "string"}}}}) }
        .to raise_error(registry_error, /f\.type: .*; .*fields\.name: the name is reserved/)
    end
  end
end
