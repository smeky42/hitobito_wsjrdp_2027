# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# One version of one account in one stage: its checks, what is fixed once
# written, the comment, the instants, the two columns of fields, the states,
# the trail and the hygiene. Rows are made through the write path
# Wsjrdp::Credentials::Deposit. The keys and values are made up.
describe WsjrdpCredential do
  let(:keys) { Wsjrdp::Credentials::Keys.new("test:#{"a" * 64}", stage: "test", label: "spec-key") }
  let(:kinds) { Wsjrdp::Credentials::Kinds.current }
  let(:password) { "made-up-password-4711" }
  let(:mail_values) do
    {"mail_from" => "finanzen@example.org", "smtp_host" => "mail.example.org", "smtp_password" => password}
  end

  def deposit(kind: "mail_account", account_key: "finanzen", values: mail_values, keys: self.keys, **options)
    result = Wsjrdp::Credentials::Deposit.call(kind: kind, account_key: account_key, values: values, keys: keys,
      kinds: kinds, **options)
    expect(result).to be_saved
    result.record
  end

  def state(row, keys: self.keys, kinds: self.kinds, **context) = row.reload.state(keys: keys, kinds: kinds, **context)

  def purpose(field) = "credential/test/mail_account/finanzen/#{field}"

  def foreign_seal(content, field, key: keys.active)
    ActiveSupport::MessageEncryptor.new(key.bytes, cipher: "aes-256-gcm", serializer: JSON)
      .encrypt_and_sign(content, purpose: purpose(field))
  end

  describe "the table" do
    it "has the defaults of the design" do
      row = described_class.create!(kind: "mail_account", account_key: "finanzen", stage: "test",
        scheme: Wsjrdp::Credentials::Sealer::SCHEME, encryption_key_fingerprint: keys.active.fingerprint)
      expect(row.reload).to have_attributes(comment: "", public_data: {}, secret_data: {}, remind_days_before: [],
        remind_emails: [], reminded_at: [], additional_info: {}, author_type: "Person", revoked_at: nil)
    end
  end

  describe "checks" do
    let(:valid) do
      described_class.new(kind: "mail_account", account_key: "finanzen", stage: "test",
        scheme: Wsjrdp::Credentials::Sealer::SCHEME, encryption_key_fingerprint: keys.active.fingerprint)
    end

    it "accepts a row of the registry's kind, a valid account key and stage, and the sealer's scheme" do
      expect(valid).to be_valid
    end

    {kind: ["nope", :unknown_kind], account_key: ["fin/anzen", :not_a_name], stage: ["Test!", :not_a_stage],
     scheme: ["rails-me-v0", :unknown_scheme]}.each do |attribute, (value, code)|
      it "refuses a wrong #{attribute} with the code #{code} and a message without the value" do
        valid[attribute] = value
        expect(valid).not_to be_valid
        expect(valid.errors.details[attribute]).to eq([{error: code}])
        expect(valid.errors.full_messages.join).not_to include(value)
      end
    end

    it "refuses an account key longer than 64 characters" do
      valid.account_key = "a" * 65
      expect(valid).not_to be_valid
      expect(valid.errors.details[:account_key]).to eq([{error: :not_a_name}])
    end

    it "folds a new row's account key to lower case and NFC, and keeps it fixed after" do
      valid.account_key = "Mu\u0308ller@Example.ORG"
      valid.save!
      expect(valid.reload.account_key).to eq("müller@example.org")
      valid.account_key = "mueller@example.org"
      expect(valid).not_to be_valid
      expect(valid.errors.details[:account_key]).to eq([{error: :fixed}])
    end

    it "finds an account by its folded key and by a key stored past the checks as it is" do
      folded = deposit
      raw = deposit(account_key: "other").tap { |row| row.update_column(:account_key, "Finanzen") }
      expect(described_class.of_account(:mail_account, "FINANZEN")).to contain_exactly(folded)
      expect(described_class.of_account(:mail_account, "Finanzen")).to contain_exactly(folded, raw)
    end

    it "refuses columns of values that are not hashes of field names to values or sealed texts" do
      [{"a" * 64 => "x"}, {"smtp_host" => 1.5}, {"smtp_host" => {"a" => "b"}}, [1], "text"].each do |bad|
        valid.public_data = bad
        valid.secret_data = bad.is_a?(Hash) ? bad.transform_values { |value| [value] } : bad
        expect(valid).not_to be_valid
        expect(valid.errors.details.slice(:public_data, :secret_data).values.flatten.uniq)
          .to eq([{error: :not_field_values}])
        expect(valid.errors.full_messages.join).not_to include("a" * 64)
      end
    end

    it "has a polymorphic author" do
      person = people(:admin)
      valid.author = person
      valid.save!
      expect(valid.reload.author).to eq(person)
      expect(valid.author_type).to eq("Person")
    end
  end

  describe "what is fixed once written" do
    let(:row) { deposit }

    %w[kind account_key stage].each do |attribute|
      it "refuses a change of #{attribute}" do
        row[attribute] = (attribute == "kind") ? "api_key" : "changed"
        expect(row).not_to be_valid
        expect(row.errors.details[attribute.to_sym]).to eq([{error: :fixed}])
      end
    end

    it "refuses a change of the author" do
      row.author = people(:admin)
      expect(row).not_to be_valid
      expect(row.errors.details.keys).to include(:author_id)
    end

    it "lets the name, the comment, the window, revoked_at and the reminder columns change" do
      row.update!(name: "key of May", comment: "Lebt 180 Tage", valid_from: Time.utc(2027, 5, 1),
        expires_at: Time.utc(2027, 11, 1), remind_days_before: [14, 3], remind_emails: ["finanzen@example.org"],
        revoked_at: Time.current)
      expect(row.reload).to have_attributes(name: "key of May", comment: "Lebt 180 Tage", remind_days_before: [14, 3])
    end
  end

  describe "the comment" do
    it "belongs to the version: a plain column, saved with the row" do
      first = deposit(comment: "Lebt 180 Tage")
      second = deposit
      expect([first.reload.comment, second.reload.comment]).to eq(["Lebt 180 Tage", ""])

      second.update!(comment: "Nur hier")
      expect([first.reload.comment, second.reload.comment]).to eq(["Lebt 180 Tage", "Nur hier"])
    end

    it "is \"\" when nil, and refuses a text of invalid encoding" do
      row = deposit
      row.comment = nil
      expect(row).to be_valid
      expect(row.comment).to eq("")

      row.comment = (+"x\xff").force_encoding("UTF-8")
      expect(row).not_to be_valid
      expect(row.errors.details[:comment]).to eq([{error: :not_valid_text}])
    end
  end

  describe "the instants valid_from, expires_at and revoked_at" do
    it "take a Time or a TimeWithZone and are stored in UTC, to the microsecond" do
      row = deposit(valid_from: Time.zone.local(2027, 5, 1, 9, 30), expires_at: Time.utc(2027, 11, 1, 0, 0, 0.1234567r))
      stored = described_class.connection.select_rows(
        "SELECT valid_from::text, expires_at::text FROM wsjrdp_credentials WHERE id = #{row.id}"
      ).first

      expect(stored).to eq([Time.zone.local(2027, 5, 1, 9, 30).utc.strftime("%F %T"), "2027-11-01 00:00:00.123456"])
      expect(row.reload.expires_at).to eq(Time.utc(2027, 11, 1, 0, 0, 0.123456r))
    end

    %w[valid_from expires_at revoked_at].each do |attribute|
      it "refuses a text, a Date or a DateTime in #{attribute}, keeping the stored value, without repeating it" do
        row = deposit
        row.update!(attribute => Time.utc(2027, 1, 1))
        ["2027-05-01", "made-up-3", Date.new(2027, 5, 1), DateTime.new(2027, 5, 1), 1_800_000_000].each do |bad|
          row.public_send(:"#{attribute}=", bad)
          expect(row).not_to be_valid
          expect(row.errors.details[attribute.to_sym]).to eq([{error: :not_an_instant}])
          expect(row.errors.full_messages.join).not_to include("made-up-3")
          expect(row[attribute]).to eq(Time.utc(2027, 1, 1))
        end

        row.public_send(:"#{attribute}=", nil)
        expect(row).to be_valid
      end
    end

    it "forgets an instant that was none on reload" do
      row = deposit
      row.expires_at = "made-up"
      expect(row).not_to be_valid
      expect(row.reload).to be_valid
    end

    it "refuses an expiry that is not after the start" do
      row = deposit
      start = Time.utc(2027, 5, 1)
      [start, start - 1].each do |expiry|
        row.assign_attributes(valid_from: start, expires_at: expiry)
        expect(row).not_to be_valid
        expect(row.errors.details[:expires_at]).to eq([{error: :not_after_valid_from}])
      end

      row.expires_at = start + Rational(1, 1_000_000)
      expect(row).to be_valid
    end

    it "makes a version used from valid_from on, up to but not including expires_at" do
      start = Time.utc(2027, 5, 1)
      expiry = Time.utc(2027, 11, 1)
      row = deposit(valid_from: start, expires_at: expiry)

      expect(state(row, at: start - 0.000001)).to eq(:not_yet_valid)
      expect(state(row, at: start)).to eq(:active)
      expect(state(row, at: expiry - 0.000001)).to eq(:active)
      expect(state(row, at: expiry)).to eq(:expired)
    end

    it "makes a version revoked from revoked_at on, also when that lies ahead" do
      revoked = Time.utc(2027, 5, 1)
      row = deposit.tap { |r| r.update!(revoked_at: revoked) }

      expect(state(row, at: revoked - 0.000001)).to eq(:active)
      expect(state(row, at: revoked)).to eq(:revoked)
    end
  end

  describe "the two columns of fields" do
    it "holds the plain values in public_data and each secret field sealed by itself in secret_data" do
      row = deposit(values: mail_values.merge("imap_password" => "made-up-imap"))

      expect(row.public_data).to eq("mail_from" => "finanzen@example.org", "smtp_host" => "mail.example.org",
        "smtp_port" => 587, "smtp_security" => "starttls", "imap_port" => 993)
      expect(row.secret_data.keys).to contain_exactly("smtp_password", "imap_password")
      expect(Wsjrdp::Credentials::Sealer.unseal(row.secret_data["imap_password"], key: keys.active, stage: "test",
        kind: "mail_account", account_key: "finanzen", field: "imap_password")).to eq("made-up-imap")
    end

    it "reads a field from either column" do
      row = deposit
      sealed_host = Wsjrdp::Credentials::Sealer.seal("sealed.example.org", key: keys.active, stage: "test",
        kind: "mail_account", account_key: "finanzen", field: "smtp_host")
      row.update_columns(public_data: row.public_data.except("smtp_host").merge("smtp_password" => "plain-made-up"),
        secret_data: {"smtp_host" => sealed_host})

      expect(row.reload.field_values(keys: keys)).to include("smtp_host" => "sealed.example.org",
        "smtp_password" => "plain-made-up")
      credential = row.examine(keys: keys, kinds: kinds).credential
      expect(credential[:smtp_host]).to eq("sealed.example.org")
      expect(credential.secret(:smtp_password)).to eq("plain-made-up")
    end

    it "takes the sealed value when a name is in both columns" do
      row = deposit
      row.update_column(:public_data, row.public_data.merge("smtp_password" => "plain-made-up"))
      expect(row.reload.field_values(keys: keys)["smtp_password"]).to eq(password)
    end

    describe "#write_field" do
      it "puts a field into the column named and removes it from the other one" do
        row = deposit
        row.write_field("smtp_host", "other.example.org", secret: true, key: keys.active)
        expect(row.public_data).not_to have_key("smtp_host")
        expect(row.secret_data).to have_key("smtp_host")

        row.write_field("smtp_password", "now-plain", secret: false)
        expect(row.secret_data).not_to have_key("smtp_password")
        expect(row.public_data["smtp_password"]).to eq("now-plain")
        row.save!
        expect(row.reload.field_values(keys: keys)).to include("smtp_host" => "other.example.org",
          "smtp_password" => "now-plain")
      end

      it "removes a field from both columns for nil" do
        row = deposit
        row.update_column(:public_data, row.public_data.merge("smtp_password" => "plain-made-up"))
        row.reload.write_field("smtp_password", nil, secret: false)
        expect([row.public_data, row.secret_data].map(&:keys).flatten).not_to include("smtp_password")
      end

      it "seals with the version's own key only" do
        row = deposit
        other = Wsjrdp::Credentials::Keys.new("test:#{"b" * 64}", stage: "test").active
        expect { row.write_field("smtp_password", "x", secret: true, key: other) }.to raise_error(ArgumentError)
        expect { row.write_field("smtp_password", "x", secret: true) }.to raise_error(ArgumentError)
      end

      it "refuses to write when a column of values is not a hash" do
        row = deposit
        row.update_column(:secret_data, ["made-up"])
        expect { row.reload.write_field("smtp_host", "x", secret: false) }.to raise_error(ArgumentError, /not a hash/)
        expect(row.secret_data).to eq(["made-up"])
      end
    end

    describe "#field_report" do
      it "names the fields that are sealed, plain, in both columns, in the wrong column, further or not opening" do
        row = deposit(values: mail_values.merge("imap_password" => "made-up-imap"))
        row.update_columns(public_data: row.public_data.merge("smtp_password" => "x", "made_up_old" => "y"),
          secret_data: row.secret_data.merge("imap_password" => "junk", "smtp_host" => row.secret_data["smtp_password"]))
        report = row.reload.field_report(keys: keys, kinds: kinds)

        expect(report.sealed).to contain_exactly("smtp_password", "imap_password", "smtp_host")
        expect(report.plain).to include("smtp_host", "smtp_password", "made_up_old")
        expect(report.in_both).to contain_exactly("smtp_password", "smtp_host")
        expect(report.wrong_column).to contain_exactly("smtp_host", "smtp_password")
        expect(report.further).to eq(["made_up_old"])
        expect(report.not_opening).to contain_exactly("imap_password", "smtp_host")
        expect(report.to_h.to_s).not_to include(password)
        expect(report.to_h.to_s).not_to include("mail.example.org")
      end

      it "cannot tell what does not open in another stage, nor the column without the kind" do
        row = deposit.tap { |r| r.update_column(:stage, "staging") }
        report = row.reload.field_report(keys: keys, kinds: kinds)
        expect(report.not_opening).to be_nil
        expect(report.sealed).to eq(["smtp_password"])

        data = YAML.safe_load_file(Wsjrdp::Credentials::Kinds::PATH)
        data["kinds"].delete("mail_account")
        report = deposit.field_report(keys: keys, kinds: Wsjrdp::Credentials::Kinds.new(data))
        expect([report.wrong_column, report.further, report.not_opening]).to eq([nil, nil, []])
      end
    end
  end

  describe "#examine and #state" do
    it "is active for a fresh row, with a Credential of its fields" do
      row = deposit(name: "key of May")
      examination = row.examine(keys: keys, kinds: kinds)

      expect(examination.state).to eq(:active)
      expect(examination.credential.secret(:smtp_password)).to eq(password)
      expect(examination.credential[:smtp_host]).to eq("mail.example.org")
      expect(examination.credential).to have_attributes(version_id: row.id, version_name: "key of May",
        key_fingerprint: keys.active.fingerprint, stage: "test")
    end

    it "is other_stage for a row of another stage" do
      row = deposit.tap { |r| r.update_column(:stage, "staging") }
      expect(state(row)).to eq(:other_stage)
    end

    it "is key_missing for a row sealed with a key this instance does not have, with or without secret fields" do
      other = Wsjrdp::Credentials::Keys.new("test:#{"b" * 64}", stage: "test")
      row = deposit
      expect(row.state(keys: other, kinds: kinds)).to eq(:key_missing)
      expect(row.state(keys: Wsjrdp::Credentials::Keys.new(nil, stage: "test"), kinds: kinds)).to eq(:key_missing)

      plain = deposit(kind: "api_key", values: {"base_url" => "https://api.example.org", "api_key" => "x"})
      plain.update_columns(secret_data: {}, public_data: plain.public_data.merge("api_key" => "x"))
      expect(plain.reload.state(keys: other, kinds: kinds)).to eq(:key_missing)
    end

    it "is kind_unknown for a kind no longer in the registry" do
      row = deposit
      data = YAML.safe_load_file(Wsjrdp::Credentials::Kinds::PATH)
      data["kinds"].delete("mail_account")
      expect(row.state(keys: keys, kinds: Wsjrdp::Credentials::Kinds.new(data))).to eq(:kind_unknown)
    end

    it "is unreadable when one sealed value does not open, or the scheme is unknown" do
      row = deposit(values: mail_values.merge("imap_password" => "made-up-imap"))
      row.update_column(:secret_data, row.secret_data.merge("imap_password" => row.secret_data["imap_password"].reverse))
      expect(state(row)).to eq(:unreadable)

      fresh = deposit
      fresh.update_column(:scheme, "rails-me-v2")
      expect(state(fresh)).to eq(:unreadable)
    end

    it "is unreadable for a sealed value moved into another field or another account" do
      row = deposit(values: mail_values.merge("imap_password" => "made-up-imap"))
      moved = row.secret_data.merge("imap_password" => row.secret_data["smtp_password"])
      row.update_column(:secret_data, moved)
      expect(state(row)).to eq(:unreadable)

      original = deposit
      other = deposit(account_key: "other")
      other.update_column(:secret_data, original.secret_data)
      expect(state(other)).to eq(:unreadable)
    end

    it "is unreadable for a sealed text holding anything but {\"value\" => a value}" do
      row = deposit
      [{"smtp_password" => {"nested" => 1}}, ["smtp_password"], "text", {"value" => 1.5}, {"value" => nil},
        {"value" => "a", "x" => "b"}].each do |content|
        row.update_column(:secret_data, {"smtp_password" => foreign_seal(content, "smtp_password")})
        expect(state(row)).to eq(:unreadable), content.inspect
      end

      row.update_column(:secret_data, {"smtp_password" => foreign_seal({"value" => "made-up"}, "smtp_password")})
      expect(state(row)).to eq(:active)
    end

    it "is kind_mismatch for values of the wrong type, in either column" do
      row = deposit
      row.update_column(:public_data, row.public_data.merge("smtp_port" => "not-a-port"))
      expect(state(row)).to eq(:kind_mismatch)

      row.update_columns(public_data: row.public_data.merge("smtp_port" => 587),
        secret_data: {"smtp_password" => foreign_seal({"value" => 4711}, "smtp_password")})
      expect(state(row)).to eq(:kind_mismatch)
    end

    def expect_no_raise(row, column, values, kind, account_key)
      source = Wsjrdp::Credentials::DatabaseSource.new(keys: keys, kinds: kinds)
      values.each do |value|
        row.update_column(column, value)
        row.reload
        expect { row.state(keys: keys, kinds: kinds) }.not_to raise_error, value.inspect
        expect { row.field_report(keys: keys, kinds: kinds) }.not_to raise_error
        expect { Wsjrdp::Credentials::Lookup.new([source]).candidates(kind, account_key) }.not_to raise_error
      end
    end

    {
      stage: ["", "a" * 64, "Not A Stage"], kind: ["", "a" * 200, "x/y"], account_key: ["", "a" * 200, "x/y"],
      scheme: ["", "x" * 300], encryption_key_fingerprint: ["", "not hex", "a" * 500],
      secret_data: [[1, 2], "text", 42, {"smtp_password" => 1}, {"a" * 64 => "x"}, {"smtp_password" => "junk"},
        {"x/y" => "a--b--c"}],
      public_data: [[1, 2], "text", 42, {"a" => {"b" => 1}}, {"a" * 64 => "x"}, {"smtp_port" => [1]}],
      name: ["", "x" * 5000, "\u{1F600}"]
    }.each do |column, values|
      it "never raises for nonsense in #{column}, in examine, field_report and the lookup" do
        expect_no_raise(deposit, column, values, :mail_account, "finanzen")
      end
    end

    describe "a row without any secret field" do
      # The secret api_key lies plain (as after the kind changed), so that no
      # sealed value stands between the row's columns and the Credential.
      def plain_row
        row = deposit(kind: "api_key", account_key: "mailcow",
          values: {"base_url" => "https://api.example.org", "api_key" => "made-up-plain"})
        row.update_columns(public_data: row.public_data.merge("api_key" => "made-up-plain"), secret_data: {})
        row.reload
      end

      it "is active, the plain field handed out by the kind" do
        expect(plain_row.examine(keys: keys, kinds: kinds).credential.secret(:api_key)).to eq("made-up-plain")
      end

      {
        account_key: ["", "a" * 200, "x/y", "Not A Name", "a__b"], kind: ["", "a" * 200, "x/y"],
        stage: ["", "a" * 64, "Not A Stage"], scheme: ["", "x" * 300],
        encryption_key_fingerprint: ["", "a" * 500], public_data: [[1, 2], "text", 42, {"a" * 64 => "x"},
          {"base_url" => {"a" => 1}}, {"api_key" => 4711}], name: ["", "x" * 5000]
      }.each do |column, values|
        it "never raises for nonsense in #{column}, in examine, field_report and the lookup" do
          expect_no_raise(plain_row, column, values, :api_key, "mailcow")
        end
      end

      it "is unreadable for an account key that is no name" do
        row = plain_row
        row.update_column(:account_key, "Not A Name")
        expect(state(row)).to eq(:unreadable)
      end
    end

    it "checks the content before the lifecycle" do
      row = deposit.tap { |r| r.update!(revoked_at: Time.current) }
      row.update_column(:secret_data, {"smtp_password" => "junk"})
      expect(state(row)).to eq(:unreadable)
    end

    it "carries the kind's warnings of the values" do
      production = Wsjrdp::Credentials::Keys.new("production:#{"d" * 64}", stage: "production")
      row = deposit(kind: "api_key", account_key: "mailcow", keys: production,
        values: {"base_url" => "http://mailcow.example.org", "api_key" => "made-up-api-key"})

      expect(row.examine(keys: production, kinds: kinds).warnings.map(&:to_s)).to eq(["base_url: not_https"])
      expect(deposit.examine(keys: keys, kinds: kinds).warnings).to eq([])
    end

    it "says why its secret fields cannot be changed with the keys given" do
      row = deposit
      newer = Wsjrdp::Credentials::Keys.new("test:#{"c" * 64},test:#{"a" * 64}", stage: "test")

      expect(row.secret_key_problem(keys)).to be_nil
      expect(row.secret_key_problem(newer)).to eq(:key_not_active)
      expect(row.secret_key_problem(Wsjrdp::Credentials::Keys.new("test:#{"b" * 64}", stage: "test"))).to eq(:key_missing)
      row.scheme = "rails-me-v0"
      expect(row.secret_key_problem(keys)).to eq(:unknown_scheme)
    end
  end

  describe "a registry changed since the version was written" do
    it "keeps a field the kind no longer has as a further field, public or sealed as it lies" do
      row = deposit(values: mail_values.merge("sent_folder" => "Sent"))
      changed = changed_kinds("mail_account") do |fields|
        fields.delete("sent_folder")
        fields.delete("smtp_password")
      end

      examination = row.examine(keys: keys, kinds: changed)
      expect(examination.state).to eq(:active)
      expect(examination.credential.further_field_names).to eq(%w[sent_folder smtp_password])
      expect(examination.credential[:sent_folder]).to eq("Sent")
      expect(examination.credential.secret(:smtp_password)).to eq(password)
      expect { examination.credential[:smtp_password] }.to raise_error(Wsjrdp::Credentials::Credential::WrongAccess)
    end

    it "is kind_mismatch for a further field under a reserved name, written past the checks" do
      row = deposit
      row.update_column(:public_data, row.public_data.merge("valid_from" => "x"))
      expect(row.reload.state(keys: keys, kinds: kinds)).to eq(:kind_mismatch)
    end

    it "casts the rest again, filling a new default" do
      row = deposit
      changed = changed_kinds("mail_account") { |fields| fields["helo_name"] = {"type" => "string", "default" => "hitobito"} }
      expect(row.examine(keys: keys, kinds: changed).credential[:helo_name]).to eq("hitobito")
    end

    it "is kind_mismatch for a version that no longer fits" do
      row = deposit
      changed = changed_kinds("mail_account") { |fields| fields["helo_name"] = {"type" => "string", "required" => true} }
      expect(row.state(keys: keys, kinds: changed)).to eq(:kind_mismatch)

      changed = changed_kinds("mail_account") { |fields| fields["smtp_port"] = {"type" => "email"} }
      expect(row.state(keys: keys, kinds: changed)).to eq(:kind_mismatch)
    end

    it "reads a field that turned secret from its plain column, and hands it out as a secret" do
      row = deposit(values: mail_values.merge("smtp_username" => "made-up-user"))
      changed = changed_kinds("mail_account") { |fields| fields["smtp_username"]["secret"] = true }

      credential = row.examine(keys: keys, kinds: changed).credential
      expect(credential.secret(:smtp_username)).to eq("made-up-user")
      expect { credential[:smtp_username] }.to raise_error(Wsjrdp::Credentials::Credential::WrongAccess)
      expect(row.field_report(keys: keys, kinds: changed).wrong_column).to eq(["smtp_username"])
    end

    it "reads a field that stopped being secret from its sealed column, and hands it out as public" do
      row = deposit
      changed = changed_kinds("mail_account") { |fields| fields["smtp_password"].delete("secret") }

      credential = row.examine(keys: keys, kinds: changed).credential
      expect(credential[:smtp_password]).to eq(password)
      expect(row.field_report(keys: keys, kinds: changed).wrong_column).to eq(["smtp_password"])
    end
  end

  describe "the trail (PaperTrail)" do
    let(:new_keys) { Wsjrdp::Credentials::Keys.new("test:#{"b" * 64},test:#{"a" * 64}", stage: "test") }

    def versions_of(row) = PaperTrail::Version.where(item_type: described_class.name, item_id: row.id).order(:id)

    # Every column of every version row of the model, as text.
    def versions_text
      described_class.connection.select_values(
        "SELECT v::text FROM versions v WHERE item_type = #{described_class.connection.quote(described_class.name)}"
      ).join("\n")
    end

    def change!(row, keys: self.keys, **options)
      Wsjrdp::Credentials::Change.call(record: row, keys: keys, kinds: kinds, **options)
        .tap { |result| expect(result).to be_saved }.record
    end

    it "records every change, never a sealed text, and names the secret fields that changed" do
      with_versioning do
        sealed = []
        row = deposit
        sealed += row.secret_data.values
        change!(row, values: {"smtp_host" => "mail2.example.org"})
        sealed += change!(row, values: {"imap_password" => "made-up-imap"}).secret_data.values
        sealed += change!(row, values: {"smtp_password" => "made-up-new-password"}).secret_data.values
        change!(row, values: {"imap_password" => ""})
        rekeyed = Wsjrdp::Credentials::Rekey.call(record: row, keys: new_keys, kinds: kinds)
        expect(rekeyed).to be_saved
        sealed += rekeyed.record.secret_data.values
        rekeyed.record.destroy!

        expect(versions_of(row).map { |version| [version.event, version.wsjrdp_data] }).to eq([
          ["create", {"secret_fields_set" => ["smtp_password"]}],
          ["update", {}],
          ["update", {"secret_fields_set" => ["imap_password"]}],
          ["update", {"secret_fields_changed" => ["smtp_password"]}],
          ["update", {"secret_fields_removed" => ["imap_password"]}],
          ["update", {"secret_fields_resealed" => ["smtp_password"]}],
          ["destroy", {"secret_fields_removed" => ["smtp_password"]}]
        ])
        text = versions_text
        # smtp_password three times (deposit, change, re-key), imap_password once.
        expect(sealed.uniq.size).to eq(4)
        sealed.uniq.each { |sealed_text| expect(text).not_to include(sealed_text) }
        [password, "made-up-imap", "made-up-new-password"].each { |value| expect(text).not_to include(value) }
        expect(text).not_to include("secret_data")
        # The plain fields are recorded as usual.
        expect(versions_of(row).second.object_changes).to include("mail2.example.org")
        expect(versions_of(row).to_a[5].object_changes).to include("encryption_key_fingerprint")
      end
    end

    it "writes exactly one entry for a save that changes secret fields only, with the request's whodunnit and controller info" do
      with_versioning do
        row = deposit
        info = {mutation_id: "request-made-up-1", whodunnit_type: "ServiceToken"}
        expect {
          PaperTrail.request(whodunnit: "17", controller_info: info) do
            change!(row, values: {"smtp_password" => "made-up-secret-only"})
          end
        }.to change { versions_of(row).count }.by(1)

        expect(versions_of(row).last).to have_attributes(event: "update", whodunnit: "17",
          whodunnit_type: "ServiceToken", mutation_id: "request-made-up-1", main_id: nil,
          wsjrdp_data: {"secret_fields_changed" => ["smtp_password"]}, object: nil, object_changes: nil)
        expect { row.reload.save! }.not_to change { versions_of(row).count }
      end
    end

    it "writes exactly one entry for a save that changes a public and a secret field" do
      with_versioning do
        row = deposit
        expect {
          PaperTrail.request(whodunnit: "4711") do
            change!(row, values: {"smtp_host" => "mail3.example.org", "imap_password" => "made-up-mixed"})
          end
        }.to change { versions_of(row).count }.by(1)

        entry = versions_of(row).last
        expect(entry).to have_attributes(event: "update", whodunnit: "4711",
          wsjrdp_data: {"secret_fields_set" => ["imap_password"]})
        expect(entry.object_changes).to include("mail3.example.org")
        expect(entry.object_changes).not_to include("secret_data")
        expect(versions_text).not_to include(row.reload.secret_data["imap_password"])
      end
    end

    it "marks no secret field as removed after a destroy that was rolled back" do
      with_versioning do
        row = deposit
        described_class.transaction(requires_new: true) do
          row.destroy!
          raise ActiveRecord::Rollback
        end
        row.update!(name: "still here") # the same object the destroy ran on

        expect(versions_of(row).last).to have_attributes(event: "update", wsjrdp_data: {})
        expect(versions_of(row).where(event: "destroy")).to be_empty

        changed = change!(row, values: {"smtp_password" => "made-up-after-rollback"})
        expect(versions_of(changed).last.wsjrdp_data).to eq("secret_fields_changed" => ["smtp_password"])
      end
    end

    it "writes no entry for a secret-only change while PaperTrail is off" do
      row = deposit
      expect { change!(row, values: {"smtp_password" => "made-up-off"}) }.not_to change(PaperTrail::Version, :count)
    end

    it "records a change of the name, the comment and the window, but not of the health columns" do
      with_versioning do
        row = deposit
        expect { row.update!(last_success_at: Time.current, last_failure_at: Time.current, last_failure_message: "x") }
          .not_to change { versions_of(row).count }
        expect { row.update!(name: "renamed", comment: "c", revoked_at: Time.current, valid_from: Time.utc(2027, 1, 1)) }
          .to change { versions_of(row).count }.by(1)
        expect(versions_of(row).last.changeset.keys).to contain_exactly("name", "comment", "revoked_at", "valid_from")
        expect(versions_text).not_to include("last_success_at")
        expect(versions_text).not_to include("reminded_at")
      end
    end
  end

  describe "hygiene" do
    it "shows no sealed text and no value in inspect" do
      row = deposit
      [row.inspect, row.reload.inspect, row.pretty_inspect, [row].inspect].each do |text|
        row.secret_data.each_value { |sealed| expect(text).not_to include(sealed) }
        expect(text).not_to include(password)
        expect(text).not_to include("mail.example.org")
      end
    end

    it "leaves the sealed texts out of as_json, to_json, serializable_hash and to_xml, keeping public_data" do
      row = deposit.reload
      shown = [row.to_json, row.as_json.to_s, row.serializable_hash.to_s, [row].to_json,
        row.serializable_hash(except: :name).to_s, row.as_json(only: %w[id secret_data]).to_s,
        row.as_json(methods: :secret_data).to_s]
      shown << row.to_xml if row.respond_to?(:to_xml)

      shown.each do |text|
        row.secret_data.each_value { |sealed| expect(text).not_to include(sealed) }
        expect(text).not_to include(password)
      end
      expect(row.as_json).not_to have_key("secret_data")
      expect(row.as_json["public_data"]).to include("smtp_host" => "mail.example.org")
      expect(row.attributes["secret_data"]).to eq(row.secret_data)
    end

    it "masks both columns of values in the SQL log" do
      log = StringIO.new
      logger = ActiveSupport::Logger.new(log).tap { |l| l.level = :debug }
      row = nil
      ActiveRecord::Base.logger, saved = logger, ActiveRecord::Base.logger
      begin
        row = deposit
        Wsjrdp::Credentials::Change.call(record: row, values: {"smtp_password" => "made-up-changed"}, keys: keys,
          kinds: kinds)
      ensure
        ActiveRecord::Base.logger = saved
      end

      expect(log.string).to include("INSERT INTO \"wsjrdp_credentials\"")
      expect(log.string).to include("UPDATE \"wsjrdp_credentials\"")
      [password, "made-up-changed", "mail.example.org", *row.reload.secret_data.values].each do |value|
        expect(log.string).not_to include(value)
      end
    end

    it "shows no value in a validation message" do
      row = deposit
      row.assign_attributes(account_key: password, valid_from: password, comment: "#{password}\xff".force_encoding("UTF-8"))
      row.valid?
      expect(row.errors.full_messages.join).not_to include(password)
      expect(row.errors.details.to_s).not_to include(password)
    end
  end
end
