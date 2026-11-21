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

# config/wsjrdp_credentials.local.yml: its shape, its stage, its keys and
# label, the strictness, and YAML read without its own dates. The texts are
# handed in, and the files of .for_instance lie in a temporary directory
# outside the repository: no spec reads a developer's own file. The values
# and keys are made up.
describe Wsjrdp::Credentials::LocalFile do
  let(:kinds) { Wsjrdp::Credentials::Kinds.load }
  let(:secret) { "made-up-client-secret-4711" }
  let(:key_secret) { "a1" * 32 }
  let(:text) do
    <<~YAML
      stage: development
      keys:
        - "development:#{key_secret}"
      label: laptop-a
      credentials:
        mail_account:
          finanzen:
            versions:
              - vars:
                  mail_from: finanzen@example.org
                  smtp_host: mailcatcher
                  smtp_port: 1025
                  smtp_password: "#{secret}"
        moss_api:
          default:
            versions:
              - name: "Key December 2026"
                created_at: 2026-11-20
                valid_from: 2026-12-01
                expires_at: 2027-05-19
                vars:
                  client_id: made-up-new
                  client_secret: "#{secret}"
              - name: "Key June 2026"
                created_at: 2026-06-18
                expires_at: 2026-12-15T00:00Z
                vars:
                  client_id: made-up-old
                  client_secret: made-up-old-secret
    YAML
  end

  def file(content = text, stage: "development") = described_class.new(content, stage: stage, kinds: kinds)

  def refused(content, stage: "development")
    expect { file(content, stage: stage) }.to raise_error(Wsjrdp::Credentials::ConfigurationError) { |error|
      expect(error.message).to start_with("config/wsjrdp_credentials.local.yml (stage #{stage}): ")
      expect(error.message).not_to include(secret)
      yield error.message if block_given?
    }
  end

  # The text with the version of moss_api/default at index changed by the
  # block (a Hash).
  def with_moss_version(index = 0)
    data = YAML.safe_load(text, permitted_classes: [Date])
    yield data["credentials"]["moss_api"]["default"]["versions"][index]
    YAML.dump(data)
  end

  describe "the shape" do
    it "gives the keys, the label and the accounts with their versions" do
      local = file

      expect(local).to be_read
      expect(local).to be_keys
      expect(local.key_entries).to eq(["development:#{key_secret}"])
      expect(local.label).to eq("laptop-a")
      expect(local.account_names).to eq([%w[mail_account finanzen], %w[moss_api default]])
      versions = local.account("moss_api", "default").versions
      expect(versions.map(&:name)).to eq(["Key December 2026", "Key June 2026"])
      expect(versions.first).to have_attributes(position: 1, created_at: Time.utc(2026, 11, 20),
        valid_from: Time.utc(2026, 12, 1), expires_at: Time.utc(2027, 5, 19))
      expect(versions.last.expires_at).to eq(Time.utc(2026, 12, 15))
    end

    it "answers with the values as texts, cast by the kind" do
      credential = file.answer("mail_account", "finanzen").candidates.first

      expect(credential[:smtp_port]).to eq(1025)
      expect(credential[:smtp_host]).to eq("mailcatcher")
      expect(credential.secret(:smtp_password)).to eq(secret)
      expect(credential.version_name).to be_nil
    end

    it "orders by created_at when every version states it, else by the list" do
      expect(file.account("moss_api", "default").order).to eq(Wsjrdp::Credentials::Override::BY_CREATED_AT)

      content = YAML.dump(YAML.safe_load(text, permitted_classes: [Date]).tap do |data|
        data["credentials"]["moss_api"]["default"]["versions"].each { |version| version.delete("created_at") }
      end)
      expect(file(content).account("moss_api", "default").order).to eq(Wsjrdp::Credentials::Override::BY_LIST)
    end

    it "needs only the stage" do
      local = file("stage: development\n")

      expect(local).to be_read
      expect(local).not_to be_keys
      expect(local.label).to be_nil
      expect(local.account_names).to eq([])
    end

    it "takes an empty list of keys as none" do
      expect(file("stage: development\nkeys: []\n")).not_to be_keys
    end

    it "warns that a label without keys is not used" do
      output = StringIO.new
      file("stage: development\nlabel: laptop-a\n").log_summary(Logger.new(output))
      expect(output.string).to include("WARN", "its label is not used, the file gives no keys")

      output = StringIO.new
      file.log_summary(Logger.new(output))
      expect(output.string).not_to include("label is not used")
    end
  end

  describe "a file for another stage" do
    it "is not read: no key, no credential, a warning naming both stages" do
      local = file(text.sub("stage: development", "stage: staging"))

      expect(local.status).to eq(described_class::OTHER_STAGE)
      expect(local).not_to be_read
      expect(local).not_to be_keys
      expect(local.account_names).to eq([])
      expect(local.answer("moss_api", "default")).to be_nil
      expect(local.shown_file_stage).to eq("staging")
      expect(local.summary).to eq("config/wsjrdp_credentials.local.yml: the file is for staging, this is " \
        "development; not read: no key and no credential is taken from it")
      output = StringIO.new
      local.log_summary(Logger.new(output))
      expect(output.string).to include("WARN", "the file is for staging")
    end

    it "skips a file for production too, without stopping the boot" do
      local = file(text.sub("stage: development", "stage: production").gsub("development:", "production:"))

      expect(local.status).to eq(described_class::OTHER_STAGE)
      expect(local).not_to be_keys
      expect(local.summary).to include("the file is for production, this is development")
    end

    it "is not checked beyond its stage" do
      expect(file("stage: staging\nno_such_key: 1\n").status).to eq(described_class::OTHER_STAGE)
    end

    it "does not repeat a stage that may be a secret" do
      local = file("stage: #{"ab" * 32}\n")

      expect(local.summary).to include("the file is for another stage")
      expect(local.summary).not_to include("ab" * 32)
    end
  end

  describe "strictness" do
    it "needs a stage" do
      refused("keys: []\n") { |message| expect(message).to include("stage: is missing") }
      refused("stage: Development\n") { |message| expect(message).to include("stage: is not of a-z and 0-9") }
      refused("") { |message| expect(message).to include("(file): is empty") }
      refused("- stage\n") { |message| expect(message).to include("(top level): is not a mapping") }
    end

    it "refuses an unknown key on every level, naming it only when it is a name" do
      refused("stage: development\nkey: x\n") { |message| expect(message).to include("(top level): unknown key key") }
      refused(text.sub("      versions:", "      version: []\n      versions:")) do |message|
        expect(message).to include("credentials.mail_account.finanzen: unknown key version")
      end
      refused(with_moss_version(1) { |version| version["expiry"] = "2027-01-01" }) do |message|
        expect(message).to include("credentials.moss_api.default.versions[2]: unknown key expiry")
      end
      refused("stage: development\n#{secret}: 1\n") do |message|
        expect(message).to include("(top level): unknown key (not a name)")
      end
    end

    it "takes a value of an enum field beyond its suggestions" do
      local = file(text.sub(/^( +)client_id: made-up-new$/) { "#{$&}\n#{$1}scope: admin" })
      examination = local.account("moss_api", "default").examine(at: Time.utc(2026, 12, 2), stage: "development").first
      expect(examination.state).to eq(:active)
      expect(examination.credential[:scope]).to eq("admin")
    end

    it "folds an account key to lower case and NFC, and refuses two that fold to the same" do
      local = file(text.sub("finanzen:", '"Finanzen@Example.ORG":'))
      expect(local.account_names).to include(%w[mail_account finanzen@example.org])
      expect(local.account("mail_account", "FINANZEN@example.org").versions.size).to eq(1)

      finanzen = text[/^    finanzen:\n(?:      .*\n)+/]
      refused(text.sub(finanzen, finanzen + finanzen.sub("finanzen:", "Finanzen:"))) do |message|
        expect(message).to include("credentials.mail_account.finanzen: the account is given twice")
      end
    end

    it "refuses a kind, an account key or a field it does not know" do
      refused(text.sub("moss_api:", "moss:")) { |message| expect(message).to include("credentials.moss: no kind moss in") }
      refused(text.sub("default:", "de fault:")) do |message|
        expect(message).to include("credentials.moss_api.(not a name): the account key is not of lower-case letters")
      end
      refused(with_moss_version { |version| version["vars"]["client_secrt"] = "x" }) do |message|
        expect(message).to include("credentials.moss_api.default.versions[1].vars.client_secrt: moss_api has no such field")
      end
      refused(with_moss_version { |version| version["vars"]["name"] = "x" }) do |message|
        expect(message).to include("versions[1].vars.name: moss_api has no such field")
      end
    end

    it "refuses a version without vars, an account without versions, a key that is no list of texts" do
      refused(with_moss_version { |version| version.delete("vars") }) do |message|
        expect(message).to include("versions[1].vars: is missing")
      end
      refused("stage: development\ncredentials:\n  moss_api:\n    default:\n      versions: []\n") do |message|
        expect(message).to include("credentials.moss_api.default.versions: is not a list of at least one version")
      end
      refused("stage: development\nkeys: development:#{key_secret}\n") do |message|
        expect(message).to include("keys: is not a list of texts")
        expect(message).not_to include(key_secret)
      end
      refused("stage: development\nlabel: [a]\n") { |message| expect(message).to include("label: is not a text") }
    end

    it "refuses a name that is no text and an instant that is none" do
      refused(with_moss_version { |version| version["name"] = ["Key"] }) do |message|
        expect(message).to include("versions[1].name: is not a text")
      end
      %w[tomorrow 19.5.2027 2027-13-01 2027-05-19T08].each do |value|
        refused(with_moss_version { |version| version["expires_at"] = value }) do |message|
          expect(message).to include("versions[1].expires_at: not an instant")
        end
      end
      refused(with_moss_version { |version| version["valid_from"] = 20_270_519 }) do |message|
        expect(message).to include("versions[1].valid_from: not an instant")
      end
    end

    it "refuses an expiry not after the start" do
      refused(with_moss_version { |version| version["expires_at"] = "2026-12-01T00:00Z" }) do |message|
        expect(message).to include("versions[1].expires_at: is not after valid_from")
      end
    end

    it "refuses created_at stated by some versions only" do
      refused(with_moss_version(1) { |version| version.delete("created_at") }) do |message|
        expect(message).to include("credentials.moss_api.default.versions: created_at is stated by some versions only")
      end
    end

    it "refuses keys that Wsjrdp::Credentials::Keys would refuse, when they are read" do
      local = file("stage: development\nkeys: [\"production:#{key_secret}\"]\n")

      expect {
        Wsjrdp::Credentials::Keys.new(local.key_entries, stage: "development", source: local.keys_source)
      }.to raise_error(Wsjrdp::Credentials::ConfigurationError) { |error|
        expect(error.message).to include("config/wsjrdp_credentials.local.yml keys (stage development): entry 1: " \
          "a production secret outside production")
        expect(error.message).not_to include(key_secret)
      }
    end

    it "takes a value that does not fit the kind as a state, not a problem" do
      local = file(with_moss_version { |version| version["vars"]["client_id"] = [42] })

      examination = local.account("moss_api", "default").examine(at: Time.utc(2026, 12, 2), stage: "development").first
      expect(examination.state).to eq(:kind_mismatch)
      expect(examination.errors.map(&:to_s)).to eq(["client_id: not_a_string"])
    end
  end

  describe "YAML" do
    it "means the same instant quoted or not, and refuses alike what only YAML would read as a time" do
      %w[2027-05-19 2027-05-19T08:30Z 2027-05-19T08:30:00Z 2027-05-19T08:30 2027-05-19T08:30:00+02:00].each do |value|
        unquoted = file(text.sub("expires_at: 2027-05-19", "expires_at: #{value}"))
        quoted = file(text.sub("expires_at: 2027-05-19", "expires_at: \"#{value}\""))

        expected = Wsjrdp::InstantInput.parse(value)
        expect(unquoted.account("moss_api", "default").versions.first.expires_at).to eq(expected), value
        expect(quoted.account("moss_api", "default").versions.first.expires_at).to eq(expected), value
      end

      unquoted = file(text.sub("expires_at: 2026-12-15T00:00Z", "expires_at: 2026-12-15 00:00:00"))
      expect(unquoted.account("moss_api", "default").versions.last.expires_at).to eq(Time.utc(2026, 12, 15))
      ["2026-12-15 00:00:00 +1", "2026-1-5", "2026-12-15T0:00:00Z"].each do |value|
        [value, "\"#{value}\""].each do |written|
          refused(text.sub("expires_at: 2026-12-15T00:00Z", "expires_at: #{written}")) do |message|
            expect(message).to include("versions[2].expires_at: not an instant")
          end
        end
      end
    end

    it "keeps every plain value the text as written, as if it were quoted" do
      {
        "smtp_port: 0465" => ["smtp_port", 465], "smtp_port: 0x1F" => ["smtp_port", nil],
        "smtp_port: 1_025" => ["smtp_port", nil], "smtp_port: \"1:30\"" => ["smtp_port", nil],
        "smtp_username: 1:30" => ["smtp_username", "1:30"], "smtp_username: yes" => ["smtp_username", "yes"],
        "smtp_username: off" => ["smtp_username", "off"], "smtp_password: 12345" => ["smtp_password", "12345"],
        "smtp_username: 0x1F" => ["smtp_username", "0x1F"], "smtp_username: 1_025" => ["smtp_username", "1_025"],
        "smtp_username: 12.50" => ["smtp_username", "12.50"],
        "smtp_username: 2026-12-01" => ["smtp_username", "2026-12-01"]
      }.each do |line, (field, expected)|
        key, value = line.split(": ", 2)
        [value, "\"#{value.delete('"')}\""].each do |written|
          replaced = (key == "smtp_password") ? "smtp_password: \"#{secret}\"" : "smtp_port: 1025"
          content = text.sub(replaced, "#{key}: #{written}")
          examination = file(content).account("mail_account", "finanzen").examine(at: Time.now.utc, stage: "development")
            .first
          shown = examination.credential && ((field == "smtp_password") ? examination.credential.secret(field) :
            examination.credential[field])
          expect(shown).to eq(expected), "#{line} written as #{written}"
        end
      end
    end

    it "takes only an empty value, null and ~ as not set" do
      ["smtp_port:", "smtp_port: null", "smtp_port: ~"].each do |line|
        credential = file(text.sub("smtp_port: 1025", line)).answer("mail_account", "finanzen").candidates.first
        expect(credential[:smtp_port]).to eq(587), line
      end
      credential = file(text.sub("smtp_port: 1025", "smtp_username: \"null\""))
        .answer("mail_account", "finanzen").candidates.first
      expect(credential[:smtp_username]).to eq("null")
    end

    it "reads stage, label, name and the entries of keys as texts, quoted or not" do
      expect(file("stage: 2027\nlabel: 123\n", stage: "2027")).to have_attributes(file_stage: "2027", label: "123")
      expect(file("stage: \"2027\"\nlabel: \"123\"\n", stage: "2027")).to have_attributes(file_stage: "2027",
        label: "123")
      expect(file(with_moss_version { |version| version["name"] = "2026" }.sub("'2026'", "2026"))
        .account("moss_api", "default").versions.first.name).to eq("2026")
      expect(file("stage: development\nkeys: [development:#{key_secret}]\n").key_entries)
        .to eq(["development:#{key_secret}"])
    end

    it "refuses a nesting deeper than its limit, as a problem of the file" do
      refused("stage: development\nlabel: #{"[" * 10_000}#{"]" * 10_000}\n") do |message|
        expect(message).to include("nested deeper than #{described_class::Yaml::MAX_DEPTH} levels")
      end
      nested = (1..3000).map { |level| "#{"  " * level}k:" }.join("\n")
      refused("stage: development\nlabel:\n#{nested} x\n") do |message|
        expect(message).to include("nested deeper than")
      end
    end

    it "loads safely: no alias, no tag but !!str, no key twice, one document" do
      {
        "stage: &s development\nlabel: *s\n" => "line 2: holds an alias",
        "stage: !ruby/object:Object development\n" => "line 1: holds a tag",
        "stage: !!binary ZGV2\n" => "line 1: holds a tag",
        "stage: development\nstage: development\n" => "line 2: a key given twice",
        "stage: development\n---\nstage: development\n" => "holds more than one document",
        "stage: [development\n" => "is not YAML (line"
      }.each do |content, expected|
        refused(content) { |message| expect(message).to include(expected) }
      end
      expect(file("stage: !!str development\n")).to be_read
    end

    it "refuses a file that is not UTF-8" do
      refused("stage: development\nlabel: \xFF\n".b) { |message| expect(message).to include("(file): is not valid UTF-8") }
    end
  end

  describe ".for_instance" do
    around do |example|
      Dir.mktmpdir("wsjrdp-credentials-spec") do |dir|
        @path = File.join(dir, "wsjrdp_credentials.local.yml")
        example.run
      end
    end

    def for_instance(stage:, test: false)
      described_class.for_instance(@path, stage: stage, kinds: kinds, test: test)
    end

    it "is ABSENT without a file" do
      expect(for_instance(stage: "development").status).to eq(described_class::ABSENT)
    end

    it "reads the file in development and staging" do
      File.write(@path, text)
      expect(for_instance(stage: "development")).to be_keys

      File.write(@path, text.sub("stage: development", "stage: staging").gsub("development:", "staging:"))
      expect(for_instance(stage: "staging").account_names.size).to eq(2)
    end

    it "does not open the file in production, and says so" do
      File.write(@path, "not: [even: yaml")
      expect(File).not_to receive(:binread)

      local = for_instance(stage: "production")
      expect(local.status).to eq(described_class::NOT_READ_PRODUCTION)
      expect(local.summary).to eq("config/wsjrdp_credentials.local.yml: lies here, but is not read in production")
      output = StringIO.new
      local.log_summary(Logger.new(output))
      expect(output.string).to include("WARN", "not read in production")
    end

    it "cannot be made to parse for production" do
      expect { file(stage: "production") }.to raise_error(ArgumentError, /production never reads/)
    end

    it "does not read the file in the Rails environment test" do
      File.write(@path, "not: [even: yaml")
      expect(File).not_to receive(:binread)

      expect(for_instance(stage: "test", test: true).status).to eq(described_class::NOT_READ_TEST)
    end

    it "refuses a file it cannot read, naming the error's class only" do
      File.write(@path, text)
      File.chmod(0o000, @path)
      skip "the file is readable for this user all the same" if File.readable?(@path)

      expect { for_instance(stage: "development") }.to raise_error(Wsjrdp::Credentials::ConfigurationError,
        /cannot be read \(Errno::EACCES\)/)
    end
  end

  describe "hygiene" do
    let(:local) { file }
    let(:shown) { [local, local.answer("moss_api", "default", at: Time.utc(2026, 12, 2))] }
    let(:secrets) { [secret, key_secret, "Key December 2026"] }

    include_examples "credential hygiene"

    it "names the keys and the accounts in its summary" do
      expect(local.summary).to eq("config/wsjrdp_credentials.local.yml: stage development, keys given, " \
        "overriding mail_account/finanzen, moss_api/default")
    end
  end
end
