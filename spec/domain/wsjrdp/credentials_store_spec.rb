# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The write paths (Wsjrdp::Credentials::Deposit, Change, Rekey) and the
# lookup (Wsjrdp::Credentials.fetch and .candidates) end to end, over the
# table and the test key of this process (Keys.current) or keys made up
# here. The values are made up.
describe "Wsjrdp::Credentials: the write paths and the lookup" do
  let(:keys) { Wsjrdp::Credentials::Keys.current }
  let(:kinds) { Wsjrdp::Credentials::Kinds.current }
  let(:moss_secret) { "made-up-client-secret-0815" }
  let(:moss_values) { {"client_id" => "made-up-client", "client_secret" => moss_secret} }
  let(:key_a) { "a" * 64 }
  let(:key_b) { "b" * 64 }

  # Every example: no override, whatever the process was started with.
  before { use_overrides }

  def keys_of(*secrets) = Wsjrdp::Credentials::Keys.new(secrets.map { |secret| "test:#{secret}" }.join(","),
    stage: "test", label: "label-#{secrets.first&.first}")

  def deposit(kind: "moss_api", account_key: "default", values: moss_values, **options)
    Wsjrdp::Credentials::Deposit.call(kind: kind, account_key: account_key, values: values, **options)
  end

  def deposit!(**options) = deposit(**options).tap { |result| expect(result).to be_saved }.record

  def change_version(row, **options) = Wsjrdp::Credentials::Change.call(record: row, **options)

  def rekey(row, **options) = Wsjrdp::Credentials::Rekey.call(record: row, **options)

  def codes(problems) = problems.map(&:to_s)

  def opened(row, field, keys: self.keys)
    key = keys.find_by_fingerprint(row.encryption_key_fingerprint)
    Wsjrdp::Credentials::Sealer.unseal(row.secret_data[field], key: key, stage: row.stage, kind: row.kind,
      account_key: row.account_key, field: field)
  end

  describe Wsjrdp::Credentials::Deposit do
    it "seals each secret field by itself with the active key, the others plain, and fills the row" do
      person = people(:admin)
      result = deposit(name: "key of May", valid_from: Time.utc(2027, 5, 1), expires_at: Time.utc(2027, 11, 1),
        author: person, comment: "Lebt 180 Tage")
      row = result.record.reload

      expect(result).to be_saved
      expect(result.field_errors + result.errors + result.warnings).to be_empty
      expect(row).to have_attributes(kind: "moss_api", account_key: "default", stage: "test", name: "key of May",
        scheme: "rails-me-v1", encryption_key_fingerprint: keys.active.fingerprint,
        encryption_key_label: keys.label, author: person, comment: "Lebt 180 Tage",
        valid_from: Time.utc(2027, 5, 1), expires_at: Time.utc(2027, 11, 1))
      expect(row.public_data).to eq("base_url" => "https://public-api.getmoss.com", "client_id" => "made-up-client",
        "scope" => "read")
      expect(row.secret_data.keys).to eq(["client_secret"])
      expect(row.secret_data.to_s).not_to include(moss_secret)
      expect(opened(row, "client_secret")).to eq(moss_secret)
    end

    it "takes a value of an enum field beyond its suggestions, and the version stays usable" do
      row = deposit!(values: moss_values.merge("scope" => "admin"))

      expect(row.reload.public_data["scope"]).to eq("admin")
      expect(row.state(keys: keys, kinds: kinds)).to eq(:active)
      expect(Wsjrdp::Credentials.fetch(:moss_api, "default")[:scope]).to eq("admin")
      expect(change_version(row, values: {"scope" => "owner"})).to be_saved
      expect(row.reload.public_data["scope"]).to eq("owner")
    end

    it "stores the account key folded, and the lookup finds it however it is written" do
      row = deposit!(account_key: "Foo@WorldScoutJamboree.DE")

      expect(row.reload.account_key).to eq("foo@worldscoutjamboree.de")
      expect(Wsjrdp::Credentials.fetch(:moss_api, "FOO@worldscoutjamboree.de").version_id).to eq(row.id)
      expect(Wsjrdp::Credentials.fetch(:moss_api, "foo@worldscoutjamboree.de").secret(:client_secret)).to eq(moss_secret)
      expect(codes(deposit(account_key: "foo bar@example.org").errors)).to eq(["account_key: not_a_name"])
    end

    it "names the active key also when no field is secret" do
      data = YAML.safe_load_file(Wsjrdp::Credentials::Kinds::PATH)
      data["kinds"]["made_up_plain"] = {"fields" => {"host" => {"type" => "string"}}}
      row = deposit!(kind: "made_up_plain", values: {"host" => "a.example.org"},
        kinds: Wsjrdp::Credentials::Kinds.new(data))

      expect(row).to have_attributes(secret_data: {}, encryption_key_fingerprint: keys.active.fingerprint)
      expect { deposit(keys: Wsjrdp::Credentials::Keys.new(nil, stage: "test")) }
        .to raise_error(Wsjrdp::Credentials::NoKeyError)
    end

    it "hands back the errors per field and per attribute, as codes, and writes nothing" do
      result = nil
      expect {
        result = deposit(values: {"client_id" => "made-up-client", "client_secret" => "", "scope" => 4711},
          valid_from: Time.utc(2027, 5, 2), expires_at: Time.utc(2027, 5, 1), account_key: "De fault")
      }.not_to change(WsjrdpCredential, :count)

      expect(result).not_to be_saved
      expect(result.record).to be_nil
      expect(codes(result.field_errors)).to contain_exactly("client_secret: required", "scope: not_a_string")
      expect(codes(result.errors)).to contain_exactly("account_key: not_a_name", "expires_at: not_after_valid_from")
      [result.inspect, result.to_json].each { |text| expect(text).not_to include(moss_secret) }
    end

    it "gives an unknown kind as an error" do
      expect(codes(deposit(kind: "nope").errors)).to eq(["kind: unknown_kind"])
    end

    it "hands back the warnings and saves all the same" do
      production = Wsjrdp::Credentials::Keys.new("production:#{"c" * 64}", stage: "production")
      result = Wsjrdp::Credentials::Deposit.call(kind: "api_key", account_key: "mailcow", keys: production,
        values: {"base_url" => "http://mail.example.org", "api_key" => "made-up"})

      expect(result).to be_saved
      expect(codes(result.warnings)).to eq(["base_url: not_https"])
    end

    {
      "invalid UTF-8" => (+"made-up\xff").force_encoding("UTF-8"),
      "binary with high bytes" => (+"made-up-\xE4\xFF").b,
      "Latin-1 with high bytes" => "made-up-\u00e4".encode("ISO-8859-1"),
      "a NUL character" => "made-up\u0000value"
    }.each do |what, bad|
      it "hands back codes for #{what} in the kind, the key, any field, the name and the comment, without raising" do
        [[{kind: bad}, :errors, "kind: unknown_kind"], [{account_key: bad}, :errors, "account_key: not_a_name"],
          [{values: moss_values.merge("client_id" => bad)}, :field_errors, "client_id: not_valid_text"],
          [{values: moss_values.merge("client_secret" => bad)}, :field_errors, "client_secret: not_valid_text"],
          [{values: moss_values.merge("base_url" => "https://example.org/#{bad.b}".b)}, :field_errors,
            "base_url: not_valid_text"],
          [{name: bad}, :errors, "name: not_valid_text"], [{comment: bad}, :errors, "comment: not_valid_text"]]
          .each do |options, list, code|
          result = nil
          expect { result = deposit(**options) }.not_to raise_error
          expect(codes(result.public_send(list))).to eq([code]), options.keys.inspect
          expect([result.inspect, result.to_json].join).not_to include("made-up")
        end
        expect(WsjrdpCredential.count).to eq(0)
      end
    end

    it "takes plain ASCII in any encoding as text" do
      expect(deposit(name: "made-up".b)).to be_saved
    end

    it "hands back not_an_integer for a number a bigint does not hold, without raising" do
      values = {"mail_from" => "finanzen@example.org", "smtp_host" => "mail.example.org", "smtp_port" => "9" * 140_000,
                "smtp_password" => "made-up"}
      result = nil
      expect { result = deposit(kind: "mail_account", account_key: "finanzen", values: values) }.not_to raise_error
      expect(codes(result.field_errors)).to eq(["smtp_port: not_an_integer"])
    end

    it "raises for values that are not a Hash, and for a window that is not a Time or nil" do
      expect { deposit(values: [["client_id", "x"]]) }.to raise_error(ArgumentError)
      ["2027-05-01", Date.new(2027, 5, 1)].each do |bad|
        expect { deposit(valid_from: bad) }.to raise_error(ArgumentError)
        expect { deposit(expires_at: bad) }.to raise_error(ArgumentError)
      end
    end

    it "checks the kind against the registry it was given" do
      data = YAML.safe_load_file(Wsjrdp::Credentials::Kinds::PATH)
      data["kinds"]["made_up_kind"] = {"fields" => {"token" => {"type" => "string", "secret" => true}}}
      made_up = Wsjrdp::Credentials::Kinds.new(data)

      result = deposit(kind: "made_up_kind", values: {"token" => "made-up"}, kinds: made_up)
      expect(result).to be_saved
      expect(result.record.examine(kinds: made_up).credential.secret(:token)).to eq("made-up")
      expect(codes(deposit(kind: "made_up_kind", values: {"token" => "made-up"}).errors)).to eq(["kind: unknown_kind"])
    end
  end

  describe Wsjrdp::Credentials::Change do
    it "changes only the fields given, keeps the others, and leaves the record handed in as it is" do
      row = deposit!
      sealed = row.secret_data["client_secret"]
      result = change_version(row, values: {"client_id" => "made-up-other", "scope" => "write"})

      expect(result).to be_saved
      expect(result.record.reload.public_data).to eq("base_url" => "https://public-api.getmoss.com",
        "client_id" => "made-up-other", "scope" => "write")
      expect(result.record.secret_data["client_secret"]).to eq(sealed)
      expect(row.public_data["client_id"]).to eq("made-up-client")
    end

    it "changes the name, the comment and the window, and leaves out what is not given" do
      row = deposit!(name: "key of May", comment: "alt", expires_at: Time.utc(2027, 11, 1))
      result = change_version(row, comment: "neu", valid_from: Time.utc(2027, 5, 1))

      expect(result.record.reload).to have_attributes(name: "key of May", comment: "neu",
        valid_from: Time.utc(2027, 5, 1), expires_at: Time.utc(2027, 11, 1))
      expect(change_version(row, name: "", expires_at: nil).record.reload).to have_attributes(name: nil, expires_at: nil)
    end

    it "revokes and takes a revocation back, with the rules of the other instants, whatever the key" do
      row = deposit!(keys: keys_of(key_a))
      at = Time.utc(2027, 5, 1, 12)

      expect(change_version(row, revoked_at: at, keys: keys_of(key_b))).to be_saved
      expect(row.reload.revoked_at).to eq(at)
      expect(row.state(at: at, keys: keys_of(key_a), kinds: kinds)).to eq(:revoked)
      expect(change_version(row, revoked_at: nil, keys: Wsjrdp::Credentials::Keys.new(nil, stage: "test"))).to be_saved
      expect(row.reload.revoked_at).to be_nil
      expect(change_version(row, name: "renamed").record.reload.revoked_at).to be_nil # not given: kept
      ["2027-05-01", Date.new(2027, 5, 1)].each do |bad|
        expect { change_version(row, revoked_at: bad) }.to raise_error(ArgumentError)
      end
    end

    it "hands back not_valid_text for a NUL character, writing nothing and raising nothing" do
      row = deposit!
      nul = "made-up\u0000value"
      [[{values: {"client_id" => nul}}, :field_errors, "client_id: not_valid_text"],
        [{values: {"client_secret" => nul}}, :field_errors, "client_secret: not_valid_text"],
        [{name: nul}, :errors, "name: not_valid_text"], [{comment: nul}, :errors, "comment: not_valid_text"]]
        .each do |options, list, code|
        result = nil
        expect { result = change_version(row, **options) }.not_to raise_error
        expect(codes(result.public_send(list))).to eq([code])
      end
      expect(row.reload).to have_attributes(name: nil, comment: "")
      expect(row.public_data["client_id"]).to eq("made-up-client")
    end

    it "refuses as stale a row changed after the expected updated_at, writing nothing" do
      row = deposit!
      drawn = row.updated_at
      change_version(WsjrdpCredential.find(row.id), comment: "by someone else")

      result = change_version(row, comment: "mine", expected_updated_at: drawn)

      expect(codes(result.errors)).to eq(["base: stale"])
      expect(row.reload.comment).to eq("by someone else")
    end

    it "changes a row whose updated_at is the expected one" do
      row = deposit!

      expect(change_version(row, comment: "mine", expected_updated_at: row.updated_at)).to be_saved
      expect(row.reload.comment).to eq("mine")
    end

    describe "after the registry made the version no longer fit" do
      let(:stricter) do
        changed_kinds("moss_api") do |fields|
          fields["helo_name"] = {"type" => "string", "required" => true}
          fields["client_id"]["type"] = "email" # the stored "made-up-client" no longer fits
        end
      end

      it "still revokes, renames and re-windows it, whatever the key, checking no field" do
        row = deposit!(keys: keys_of(key_a))
        expect(row.state(keys: keys_of(key_a), kinds: stricter)).to eq(:kind_mismatch)
        [keys_of(key_a), keys_of(key_b, key_a), keys_of(key_b)].each do |keys_then|
          result = change_version(row, revoked_at: Time.current, name: "old", comment: "c", valid_from: nil,
            expires_at: Time.utc(2030, 1, 1), keys: keys_then, kinds: stricter)
          expect(result).to be_saved
          expect(result.field_errors + result.errors).to be_empty
        end
      end

      it "checks only the fields given: another field missing or stale does not stop a change" do
        row = deposit!
        result = change_version(row, values: {"scope" => "write"}, kinds: stricter)
        expect(result).to be_saved
        expect(codes(change_version(row, values: {"scope" => 7}, kinds: stricter).field_errors))
          .to eq(["scope: not_a_string"])
      end

      it "mends the version when the missing field is given" do
        row = deposit!
        result = change_version(row, values: {"helo_name" => "hitobito", "client_id" => "api@example.org"},
          kinds: stricter)
        expect(result).to be_saved
        expect(result.record.reload.state(kinds: stricter)).to eq(:active)
      end
    end

    it "refuses fields of a row whose column of values is not a hash, but changes the rest" do
      row = deposit!
      row.update_column(:public_data, "made-up text")

      result = change_version(row, values: {"client_id" => "made-up-new"})
      expect(codes(result.errors)).to eq(["public_data: not_field_values"])
      expect(result).not_to be_saved
      expect(row.reload.public_data).to eq("made-up text")
      expect(change_version(row, name: "renamed", revoked_at: Time.current)).to be_saved
    end

    it "refuses a secret field of a row whose scheme is unknown, as Rekey does, but changes the rest" do
      row = deposit!
      row.update_column(:scheme, "rails-me-v2")
      sealed = row.secret_data["client_secret"]

      expect(codes(change_version(row, values: {"client_secret" => "made-up-new"}).field_errors))
        .to eq(["client_secret: unknown_scheme"])
      expect(row.reload.secret_data["client_secret"]).to eq(sealed)
      expect(change_version(row, values: {"client_id" => "made-up-new"}, revoked_at: Time.current)).to be_saved
    end

    it "removes a field given as empty; the kind's rules hold for the result" do
      row = deposit!
      expect(change_version(row, values: {"scope" => ""}).record.reload.public_data).not_to have_key("scope")
      expect(Wsjrdp::Credentials.fetch(:moss_api, "default")[:scope]).to eq("read") # its default

      result = change_version(row, values: {"client_id" => nil})
      expect(codes(result.field_errors)).to eq(["client_id: required"])
      expect(result).not_to be_saved
      expect(row.reload.public_data["client_id"]).to eq("made-up-client")
    end

    it "casts the given values with the kind and names a further field that is no name, writing nothing on an error" do
      row = deposit!
      result = change_version(row, values: {"scope" => 7, "a" * 64 => "x", "client_id" => "made-up-new"})

      expect(codes(result.field_errors)).to contain_exactly("scope: not_a_string", "(not a name): not_a_name")
      expect(row.reload.public_data["client_id"]).to eq("made-up-client")
    end

    it "hands back the model's errors and the warnings" do
      row = deposit!(valid_from: Time.utc(2027, 5, 1))
      expect(codes(change_version(row, expires_at: Time.utc(2027, 5, 1)).errors)).to eq(["expires_at: not_after_valid_from"])
      expect { change_version(row, expires_at: "2027-05-02") }.to raise_error(ArgumentError)

      production = Wsjrdp::Credentials::Keys.new("production:#{"c" * 64}", stage: "production")
      prod_row = Wsjrdp::Credentials::Deposit.call(kind: "api_key", account_key: "mailcow", keys: production,
        values: {"base_url" => "https://mail.example.org", "api_key" => "made-up"}).record
      result = change_version(prod_row, values: {"base_url" => "http://mail.example.org"}, keys: production)
      expect(result).to be_saved
      expect(codes(result.warnings)).to eq(["base_url: not_https"])
    end

    it "refuses a row of another stage, and a row that is gone" do
      row = deposit!
      row.update_column(:stage, "staging")
      expect(codes(change_version(row, name: "x").errors)).to eq(["stage: other_stage"])

      gone = deposit!
      WsjrdpCredential.where(id: gone.id).delete_all
      expect(codes(change_version(gone, name: "x").errors)).to eq(["base: not_found"])
    end

    it "raises for a record that is not saved and for values that are not a Hash" do
      expect { change_version(WsjrdpCredential.new) }.to raise_error(ArgumentError)
      expect { change_version(deposit!, values: [%w[a b]]) }.to raise_error(ArgumentError)
    end

    describe "a secret field" do
      it "is changed while the version's key is the active one, sealed with it" do
        row = deposit!(keys: keys_of(key_a))
        result = change_version(row, values: {"client_secret" => "made-up-new"}, keys: keys_of(key_a, key_b))

        expect(result).to be_saved
        expect(opened(result.record.reload, "client_secret", keys: keys_of(key_a))).to eq("made-up-new")
        expect(result.record.encryption_key_fingerprint).to eq(keys_of(key_a).active.fingerprint)
      end

      it "is not sealed again when its value stays the same" do
        row = deposit!
        sealed = row.secret_data["client_secret"]
        expect(change_version(row, values: {"client_secret" => moss_secret}).record.reload.secret_data["client_secret"])
          .to eq(sealed)
      end

      it "is refused with key_not_active when the version's key is accepted but not active, and nothing is written" do
        row = deposit!(keys: keys_of(key_a))
        result = change_version(row, values: {"client_secret" => "made-up-new", "client_id" => "made-up-new"},
          keys: keys_of(key_b, key_a))

        expect(codes(result.field_errors)).to eq(["client_secret: key_not_active"])
        expect(row.reload.public_data["client_id"]).to eq("made-up-client")
        expect(codes(change_version(row, values: {"client_secret" => ""}, keys: keys_of(key_b, key_a)).field_errors))
          .to eq(["client_secret: key_not_active"])
      end

      it "is refused with key_missing when the version's key is not here" do
        row = deposit!(keys: keys_of(key_a))
        result = change_version(row, values: {"client_secret" => "made-up-new"}, keys: keys_of(key_b))

        expect(codes(result.field_errors)).to eq(["client_secret: key_missing"])
        expect(codes(change_version(row, values: {"client_secret" => "x"}, keys: Wsjrdp::Credentials::Keys.new(nil,
          stage: "test")).field_errors)).to eq(["client_secret: key_missing"])
      end
    end

    describe "a field that is not secret" do
      [["the active key", -> { keys_of(key_a) }], ["an accepted, not active key", -> { keys_of(key_b, key_a) }],
        ["a missing key", -> { keys_of(key_b) }]].each do |what, keys_then|
        it "is changed with #{what}, the secret fields kept (a sealed one counting as set)" do
          row = deposit!(keys: keys_of(key_a))
          sealed = row.secret_data["client_secret"]
          result = change_version(row, values: {"client_id" => "made-up-new"}, keys: instance_exec(&keys_then))

          expect(result).to be_saved
          expect(result.record.reload).to have_attributes(secret_data: {"client_secret" => sealed},
            encryption_key_fingerprint: keys_of(key_a).active.fingerprint)
          expect(result.record.public_data["client_id"]).to eq("made-up-new")
        end
      end
    end

    describe "after the kind changed" do
      it "seals a field that turned secret when it is written, and removes it from public_data" do
        row = deposit!(values: moss_values.merge("scope" => "write"))
        # A secret field has no default (the registry is committed).
        changed = changed_kinds("moss_api") do |fields|
          fields["scope"] = {"type" => "enum", "values" => %w[read write], "secret" => true}
        end
        result = change_version(row, values: {"scope" => "read"}, kinds: changed)

        expect(result).to be_saved
        expect(result.record.reload.public_data).not_to have_key("scope")
        expect(opened(result.record, "scope")).to eq("read")
      end

      it "writes a field that stopped being secret plain, and removes its sealed text" do
        row = deposit!
        changed = changed_kinds("moss_api") { |fields| fields["client_secret"].delete("secret") }
        result = change_version(row, values: {"client_secret" => "made-up-plain-now"}, kinds: changed)

        expect(result.record.reload.secret_data).to eq({})
        expect(result.record.public_data["client_secret"]).to eq("made-up-plain-now")
      end

      it "moves a field of the wrong column also when its value stays the same" do
        row = deposit!
        changed = changed_kinds("moss_api") { |fields| fields["client_secret"].delete("secret") }
        result = change_version(row, values: {"client_secret" => moss_secret}, kinds: changed)

        expect(result.record.reload).to have_attributes(secret_data: {})
        expect(result.record.public_data["client_secret"]).to eq(moss_secret)
      end

      it "refuses a field change when the kind is unknown, but lets the name change" do
        row = deposit!
        data = YAML.safe_load_file(Wsjrdp::Credentials::Kinds::PATH)
        data["kinds"].delete("moss_api")
        unknown = Wsjrdp::Credentials::Kinds.new(data)

        expect(codes(change_version(row, values: {"client_id" => "x"}, kinds: unknown).errors)).to eq(["kind: unknown_kind"])
        expect(change_version(row, name: "still named", kinds: unknown)).to be_saved
        expect(change_version(row, revoked_at: Time.current, kinds: unknown)).to be_saved
      end
    end
  end

  describe "further fields" do
    let(:pin) { "made-up-further-pin-1357" }

    def further!(**options)
      deposit!(values: moss_values.merge("tenant" => "made-up-tenant", "pin" => pin), secret_further_fields: [:pin],
        **options)
    end

    it "deposits a public one plain and a secret one sealed by itself, read like the kind's fields" do
      row = further!

      expect(row.public_data["tenant"]).to eq("made-up-tenant")
      expect(row.secret_data.keys).to contain_exactly("client_secret", "pin")
      expect(opened(row, "pin")).to eq(pin)
      credential = Wsjrdp::Credentials.fetch(:moss_api, "default")
      expect([credential[:tenant], credential.secret(:pin)]).to eq(["made-up-tenant", pin])
    end

    it "lets the kind decide for a field of the kind, whatever secret_further_fields says" do
      row = deposit!(secret_further_fields: ["client_id"])
      expect(row.plain?("client_id")).to be true
    end

    it "refuses one under a reserved name or with a value that is no text, writing nothing" do
      result = deposit(values: moss_values.merge("name" => "x", "count" => 3))
      expect(codes(result.field_errors)).to contain_exactly("name: reserved", "count: not_a_string")
      expect(WsjrdpCredential.count).to eq(0)
    end

    it "changes one, seals a public one on request, and keeps a sealed one sealed" do
      row = further!
      expect(change_version(row, values: {"tenant" => "made-up-next", "pin" => "made-up-new-pin"})).to be_saved
      expect(row.reload.public_data["tenant"]).to eq("made-up-next")
      expect(opened(row, "pin")).to eq("made-up-new-pin")

      expect(change_version(row, values: {"tenant" => "made-up-next"}, secret_further_fields: ["tenant"])).to be_saved
      expect(row.reload.sealed?("tenant")).to be true
      expect(row.plain?("tenant")).to be false
    end

    it "changes or removes a sealed one only under the active key, a public one whatever the key" do
      row = further!(keys: keys_of(key_a))
      newer = keys_of(key_b, key_a)

      expect(codes(change_version(row, values: {"pin" => nil}, keys: newer).field_errors)).to eq(["pin: key_not_active"])
      expect(codes(change_version(row, values: {"rate" => "x"}, secret_further_fields: ["rate"], keys: newer)
        .field_errors)).to eq(["rate: key_not_active"])
      expect(change_version(row, values: {"tenant" => nil}, keys: newer)).to be_saved
      expect(row.reload.plain?("tenant")).to be false
      expect(opened(row, "pin", keys: newer)).to eq(pin)
    end

    it "keeps each in its column through a re-key" do
      row = further!(keys: keys_of(key_a))
      newer = keys_of(key_b, key_a)
      expect(rekey(row, keys: newer)).to be_saved

      expect(row.reload.plain?("tenant")).to be true
      expect(opened(row, "pin", keys: newer)).to eq(pin)
    end

    it "never shows a sealed value in inspect, as_json, the credential or the trail" do
      row = nil
      with_versioning { row = further! }
      credential = Wsjrdp::Credentials.fetch(:moss_api, "default")
      texts = [row.inspect, row.to_json, credential.inspect, credential.to_json,
        PaperTrail::Version.where(item: row).map { |version| version.attributes.to_json }.join]

      texts.each { |text| expect(text).not_to include(pin) }
      expect(PaperTrail::Version.where(item: row).last.wsjrdp_data).to eq("secret_fields_set" => %w[client_secret pin])
    end
  end

  describe Wsjrdp::Credentials::Rekey do
    it "changes nothing when a column of values is not a hash" do
      row = deposit!(keys: keys_of(key_a))
      row.update_column(:secret_data, ["made-up"])

      result = rekey(row, keys: keys_of(key_b, key_a))
      expect(codes(result.errors)).to eq(["secret_data: not_field_values"])
      expect(row.reload).to have_attributes(secret_data: ["made-up"],
        encryption_key_fingerprint: keys_of(key_a).active.fingerprint)
    end

    it "seals every value again with the active key and changes fingerprint, label and scheme" do
      row = deposit!(keys: keys_of(key_a))
      new_keys = keys_of(key_b, key_a)
      result = rekey(row, keys: new_keys)

      expect(result).to be_saved
      expect(result.warnings).to be_empty
      expect(result.record.reload).to have_attributes(encryption_key_fingerprint: new_keys.active.fingerprint,
        encryption_key_label: "label-b", scheme: "rails-me-v1")
      expect(result.record.secret_data["client_secret"]).not_to eq(row.secret_data["client_secret"])
      expect(opened(result.record, "client_secret", keys: keys_of(key_b))).to eq(moss_secret)
      expect(result.record.public_data).to eq(row.public_data)
      expect(result.record.state(keys: keys_of(key_b), kinds: kinds)).to eq(:active)
    end

    it "moves every field into the column the kind names now" do
      row = deposit!(keys: keys_of(key_a), values: moss_values.merge("scope" => "write"))
      changed = changed_kinds("moss_api") do |fields|
        fields["scope"] = {"type" => "enum", "values" => %w[read write], "secret" => true}
        fields["client_secret"].delete("secret")
      end
      record = rekey(row, keys: keys_of(key_b, key_a), kinds: changed).record.reload

      expect(record.secret_data.keys).to eq(["scope"])
      expect(record.public_data).to include("client_secret" => moss_secret)
      expect(record.public_data).not_to have_key("scope")
      expect(record.examine(keys: keys_of(key_b), kinds: changed).credential.secret(:scope)).to eq("write")
    end

    it "with the active key already, seals nothing again and only moves what lies in the wrong column" do
      row = deposit!(keys: keys_of(key_a), values: moss_values.merge("scope" => "write"))
      changed = changed_kinds("moss_api") do |fields, kind|
        fields["client_id"]["secret"] = true
        kind.delete("title_field") # a title field is never secret
      end
      result = rekey(row, keys: keys_of(key_a), kinds: changed)

      expect(codes(result.warnings)).to eq(["encryption_key_fingerprint: already_active"])
      record = result.record.reload
      expect(record.secret_data["client_secret"]).to eq(row.secret_data["client_secret"])
      expect(opened(record, "client_id", keys: keys_of(key_a))).to eq("made-up-client")
      expect(record.public_data).not_to have_key("client_id")
    end

    it "changes nothing when the version's key is not here" do
      row = deposit!(keys: keys_of(key_a))
      result = rekey(row, keys: keys_of(key_b))

      expect(codes(result.errors)).to eq(["encryption_key_fingerprint: key_missing"])
      expect(row.reload.encryption_key_fingerprint).to eq(keys_of(key_a).active.fingerprint)
    end

    it "changes nothing when one value does not open, and names it" do
      row = deposit!(keys: keys_of(key_a), kind: "mail_account", account_key: "finanzen",
        values: {"mail_from" => "finanzen@example.org", "smtp_host" => "mail.example.org",
                 "smtp_password" => "made-up-smtp", "imap_password" => "made-up-imap"})
      row.update_column(:secret_data, row.secret_data.merge("imap_password" => row.secret_data["smtp_password"]))
      before = row.reload.attributes
      result = rekey(row, keys: keys_of(key_b, key_a))

      expect(result).not_to be_saved
      expect(codes(result.field_errors)).to eq(["imap_password: not_opening"])
      expect(row.reload.attributes).to eq(before)
    end

    it "refuses a row of another stage and a row with an unknown scheme" do
      row = deposit!(keys: keys_of(key_a))
      row.update_column(:scheme, "rails-me-v2")
      expect(codes(rekey(row, keys: keys_of(key_b, key_a)).errors)).to eq(["scheme: unknown_scheme"])

      row.update_columns(scheme: "rails-me-v1", stage: "staging")
      expect(codes(rekey(row, keys: keys_of(key_b, key_a)).errors)).to eq(["stage: other_stage"])
      expect(row.reload.encryption_key_fingerprint).to eq(keys_of(key_a).active.fingerprint)
    end

    it "raises NoKeyError without any key" do
      row = deposit!
      expect { rekey(row, keys: Wsjrdp::Credentials::Keys.new(nil, stage: "test")) }
        .to raise_error(Wsjrdp::Credentials::NoKeyError)
    end

    it "lets secret fields be changed again afterwards" do
      row = deposit!(keys: keys_of(key_a))
      new_keys = keys_of(key_b, key_a)
      expect(codes(change_version(row, values: {"client_secret" => "x"}, keys: new_keys).field_errors))
        .to eq(["client_secret: key_not_active"])

      rekey(row, keys: new_keys)
      expect(change_version(row, values: {"client_secret" => "made-up-after"}, keys: new_keys)).to be_saved
    end
  end

  describe ".fetch and .candidates" do
    # The order of the sources is credentials_overrides_spec.rb's.
    it "gives back a version deposited here" do
      row = deposit!(name: "key of May")

      credential = Wsjrdp::Credentials.fetch(:moss_api, "default")
      expect(credential.secret(:client_secret)).to eq(moss_secret)
      expect(credential[:base_url]).to eq("https://public-api.getmoss.com")
      expect(credential).to have_attributes(version_id: row.id, version_name: "key of May")
    end

    it "lets the newest win, the id deciding between rows of the same instant" do
      first = travel_to(Time.zone.local(2026, 11, 1)) { deposit!(values: moss_values.merge("client_id" => "first")) }
      second = travel_to(Time.zone.local(2026, 11, 3)) { deposit!(values: moss_values.merge("client_id" => "second")) }
      third = travel_to(Time.zone.local(2026, 11, 2)) { deposit!(values: moss_values.merge("client_id" => "third")) }

      expect(Wsjrdp::Credentials.candidates(:moss_api, "default").map(&:version_id))
        .to eq([second.id, third.id, first.id])

      third.update_column(:created_at, second.created_at)
      expect(Wsjrdp::Credentials.candidates(:moss_api, "default").map(&:version_id))
        .to eq([third.id, second.id, first.id])
      expect(Wsjrdp::Credentials.fetch(:moss_api, "default")[:client_id]).to eq("third")
    end

    it "keeps the window to whether a version counts, never which one wins" do
      successor = travel_to(Time.zone.local(2026, 11, 1)) { deposit!(valid_from: Time.utc(2026, 12, 1)) }
      current = travel_to(Time.zone.local(2026, 11, 2)) { deposit! }

      travel_to(Time.zone.local(2026, 12, 2)) do
        expect(Wsjrdp::Credentials.candidates(:moss_api, "default").map(&:version_id))
          .to eq([current.id, successor.id])
      end
    end

    it "skips what is not usable here and goes on to the next one" do
      usable = travel_to(1.day.ago) { deposit! }
      deposit!.update!(revoked_at: Time.current)
      deposit!.update_column(:stage, "staging")
      deposit!.update_column(:encryption_key_fingerprint, Wsjrdp::Credentials::Keys.fingerprint_of("f" * 64))
      deposit!.tap { |row| row.update_column(:secret_data, {"client_secret" => "junk"}) }
      other_account = deposit!(account_key: "other")
      deposit!.update_column(:secret_data, other_account.secret_data)

      expect(Wsjrdp::Credentials.candidates(:moss_api, "default").map(&:version_id)).to eq([usable.id])
    end

    it "goes on to an older version when the newer one no longer fits the registry" do
      older = travel_to(1.day.ago) { deposit!(values: moss_values.merge("client_id" => "kasse@example.org")) }
      deposit!(values: moss_values.merge("client_id" => "made-up-client"))
      changed = changed_kinds("moss_api") { |fields| fields["client_id"]["type"] = "email" }
      allow(Wsjrdp::Credentials::Kinds).to receive(:current).and_return(changed)

      expect(Wsjrdp::Credentials.fetch(:moss_api, "default").version_id).to eq(older.id)
    end

    it "raises a named error that names the account and the states, never a value" do
      deposit!.update!(revoked_at: Time.current)
      deposit!(expires_at: Time.utc(2026, 1, 1)).tap { |row| row.update_column(:stage, "staging") }

      expect { Wsjrdp::Credentials.fetch(:moss_api, "default") }.to raise_error(Wsjrdp::Credentials::NoCredentialError,
        "moss_api/default: no usable version in stage test (database: 2 versions, none usable: other_stage 1, " \
        "revoked 1)") { |error| expect(error.message).not_to include(moss_secret) }
      expect { Wsjrdp::Credentials.fetch(:moss_api, "nobody") }
        .to raise_error(Wsjrdp::Credentials::NoCredentialError, /\(database: no version\)/)
    end

    it "reads the rows on each call, remembering nothing" do
      row = deposit!
      expect(Wsjrdp::Credentials.fetch(:moss_api, "default").version_id).to eq(row.id)

      row.update!(revoked_at: Time.current)
      expect(Wsjrdp::Credentials.candidates(:moss_api, "default")).to be_empty
    end
  end
end
