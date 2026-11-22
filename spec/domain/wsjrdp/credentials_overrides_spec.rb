# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"
require "tmpdir"

# What the standalone specs of spec/domain/wsjrdp/credentials/ cannot cover:
# the order of the sources over the table (variables, the local file, the
# database, per account as a whole), the lookup end to end, the keys from
# the file, the read model for the pages, and the boot wiring. Every
# override is handed in (Overrides.current is stubbed): no spec depends on
# a developer's own environment or config/wsjrdp_credentials.local.yml.
# Files lie in a temporary directory outside the repository. The values and
# keys are made up.
module CredentialsOverridesSpec
  OVERRIDES_AT_BOOT = Wsjrdp::Credentials::Overrides.instance_variable_get(:@current)
end

describe "Wsjrdp::Credentials: the overrides" do
  let(:kinds) { Wsjrdp::Credentials::Kinds.current }
  let(:db_secret) { "made-up-database-secret" }
  let(:file_secret) { "made-up-file-secret" }
  let(:env_secret) { "made-up-variable-secret" }
  let(:prefix) { "HITOBITO_CREDENTIAL__TEST__MOSS_API__DEFAULT__" }
  let(:env) { {"#{prefix}CLIENT_ID" => "env-client", "#{prefix}CLIENT_SECRET" => env_secret} }
  let(:file_text) do
    <<~YAML
      stage: test
      credentials:
        moss_api:
          default:
            versions:
              - name: file version
                vars: {client_id: file-client, client_secret: "#{file_secret}"}
    YAML
  end

  def variables(values = env) = Wsjrdp::Credentials::Variables.new(values, stage: "test", kinds: kinds)

  def local_file(text = file_text) = Wsjrdp::Credentials::LocalFile.new(text, stage: "test", kinds: kinds)

  def deposit!(values: {"client_id" => "db-client", "client_secret" => db_secret}, account_key: "default", **options)
    Wsjrdp::Credentials::Deposit.call(kind: "moss_api", account_key: account_key, values: values, **options)
      .tap { |result| expect(result).to be_saved }.record
  end

  def fetch(account_key = "default") = Wsjrdp::Credentials.fetch(:moss_api, account_key)

  describe "the order of the sources" do
    it "overrides an account whose key is no name by the variables of its part, listed under its key" do
      row = deposit!(account_key: "Foo@WorldScoutJamboree.de")
      part = "HITOBITO_CREDENTIAL__TEST__MOSS_API__FOO_WORLDSCOUTJAMBOREE_DE__"
      use_overrides(variables: variables({"#{part}CLIENT_ID" => "env-client", "#{part}CLIENT_SECRET" => env_secret}))

      expect(row.account_key).to eq("foo@worldscoutjamboree.de")
      expect(fetch("FOO@worldscoutjamboree.de").secret(:client_secret)).to eq(env_secret)
      overview = Wsjrdp::Credentials::Overview.new
      expect(overview.account_names).to eq([%w[moss_api foo@worldscoutjamboree.de]])
      expect(overview.account(:moss_api, "foo@worldscoutjamboree.de").in_use).to eq("variables")

      row.destroy!
      expect(Wsjrdp::Credentials::Overview.new.account_names).to eq([%w[moss_api foo_worldscoutjamboree_de]])
    end

    it "takes the database when no override names the account" do
      use_overrides(variables: variables({"HITOBITO_CREDENTIAL__TEST__MOSS_API__OTHER__CLIENT_ID" => "x"}),
        file: local_file(file_text.sub("default:", "another:")))
      row = deposit!

      expect(fetch.version_id).to eq(row.id)
      expect(fetch.secret(:client_secret)).to eq(db_secret)
    end

    it "takes the file before the database and the variables before both, per account" do
      deposit!
      other = deposit!(account_key: "other")
      use_overrides(file: local_file)
      expect(fetch.secret(:client_secret)).to eq(file_secret)
      expect(fetch).to have_attributes(version_id: nil, version_name: "file version", key_fingerprint: nil)

      use_overrides(variables: variables, file: local_file)
      expect(fetch.secret(:client_secret)).to eq(env_secret)
      expect(Wsjrdp::Credentials.candidates(:moss_api, "default").size).to eq(1)
      expect(fetch("other").version_id).to eq(other.id)
    end

    it "lets an override answer for the account as a whole: nothing is mixed, the database is not asked" do
      deposit!
      use_overrides(variables: variables({"#{prefix}CLIENT_ID" => "env-client"}), file: local_file)

      expect(WsjrdpCredential).not_to receive(:of_account)
      message = "moss_api/default: no usable version in stage test (variables: 1 version, none usable: kind_mismatch 1)"
      expect { fetch }.to raise_error(Wsjrdp::Credentials::NoCredentialError, message) { |error|
        expect(error.message).not_to include("made-up")
      }

      use_overrides(file: local_file(file_text.sub("- name: file version", "- expires_at: 2020-01-01\n          name: x")))
      expect { fetch }.to raise_error(Wsjrdp::Credentials::NoCredentialError, /\(file: 1 version, none usable: expired 1\)/)
    end
  end

  describe "the keys" do
    let(:file_key) { "c3" * 32 }
    let(:variable_key) { "d4" * 32 }
    let(:keys_text) { "stage: test\nkeys: [\"test:#{file_key}\"]\nlabel: laptop-file\n" }
    let(:log) { StringIO.new }
    let(:logger) { Logger.new(log) }

    def from_sources(**options)
      Wsjrdp::Credentials::Keys.from_sources(variable: nil, label: nil, file: no_local_file, test_value: nil,
        logger: logger, **options)
    end

    def fingerprint(secret) = Wsjrdp::Credentials::Keys.fingerprint_of(secret)

    it "takes the keys and the label of the file where the variable is not set" do
      keys = from_sources(file: local_file(keys_text), test_value: "test:#{variable_key}")

      expect(keys.keys.map(&:fingerprint)).to eq([fingerprint(file_key)])
      expect(keys.label).to eq("laptop-file")
      expect(keys.source).to eq("config/wsjrdp_credentials.local.yml keys")
      expect(keys.label_source).to eq("config/wsjrdp_credentials.local.yml label")
    end

    it "takes the variable before the file, with the label variable; never merges" do
      keys = from_sources(variable: "test:#{variable_key}", label: "laptop-env", file: local_file(keys_text))

      expect(keys.keys.map(&:fingerprint)).to eq([fingerprint(variable_key)])
      expect(keys.label).to eq("laptop-env")
      expect(keys.source).to eq("HITOBITO_CREDENTIAL_KEYS")
    end

    it "says when the variable leaves the file's keys (and label) unused" do
      from_sources(variable: "test:#{variable_key}", file: local_file(keys_text))
      from_sources(variable: "test:#{variable_key}", file: local_file(keys_text.sub("label: laptop-file\n", "")))

      expect(log.string).to include("config/wsjrdp_credentials.local.yml: its keys and label are not used, " \
        "HITOBITO_CREDENTIAL_KEYS is set")
      expect(log.string).to include("config/wsjrdp_credentials.local.yml: its keys are not used, " \
        "HITOBITO_CREDENTIAL_KEYS is set")
      expect(log.string).not_to include(file_key)
    end

    it "does not use the label variable with the file's keys, and says so" do
      keys = from_sources(label: "laptop-env", file: local_file(keys_text))

      expect(keys.label).to eq("laptop-file")
      expect(log.string).to include("HITOBITO_CREDENTIAL_LABEL: not used, the keys come from " \
        "config/wsjrdp_credentials.local.yml")
    end

    it "falls back to the committed test key when neither gives keys" do
      keys = from_sources(label: "laptop-env", file: local_file, test_value: Settings.credentials.keys_default)

      expect(Wsjrdp::Credentials::Keys::PUBLIC_FINGERPRINTS).to include(keys.active.fingerprint)
      expect(keys.source).to eq("config/settings/test.yml credentials.keys_default")
      expect(keys.label).to eq("laptop-env")
      expect(from_sources.keys).to eq([])
    end

    it "takes no key from a file for another stage" do
      skipped = Wsjrdp::Credentials::LocalFile.new(keys_text.sub("stage: test", "stage: development"), stage: "test",
        kinds: kinds)

      expect(from_sources(file: skipped).keys).to eq([])
    end

    it "applies the rules of the keys to the file's entries, the committed public keys included" do
      public_secret = Settings.credentials.keys_default.split(":", 2).last
      entry = "development:#{public_secret}"
      file = Wsjrdp::Credentials::LocalFile.new("stage: development\nkeys: [\"#{entry}\"]\n", stage: "development",
        kinds: kinds)
      allow(Wsjrdp::Credentials::Keys).to receive(:stage).and_return("development")

      expect { from_sources(file: file) }.to raise_error(Wsjrdp::Credentials::ConfigurationError) { |error|
        expect(error.message).to include("config/wsjrdp_credentials.local.yml keys (stage development): entry 1: " \
          "the committed, public key of test")
        expect(error.message).not_to include(public_secret)
      }
    end

    it "is what Keys.current takes from the overrides of this process" do
      config = Rails.configuration.x
      saved = [config.credential_keys, config.credential_label]
      config.credential_keys = nil
      use_overrides(file: local_file(keys_text))
      Wsjrdp::Credentials::Keys.reset!

      expect(Wsjrdp::Credentials::Keys.current.source).to eq("config/wsjrdp_credentials.local.yml keys")
    ensure
      config.credential_keys, config.credential_label = saved
      Wsjrdp::Credentials::Keys.reset!
    end
  end

  describe Wsjrdp::Credentials::Overview do
    def overview = described_class.new

    it "shows every source of an account, the one in use, the roles and what is overridden" do
      old = travel_to(2.days.ago) { deposit!(name: "db old") }
      new = travel_to(1.day.ago) { deposit!(name: "db new") }
      deposit!(name: "db other stage").update_column(:stage, "staging")
      use_overrides(file: local_file)

      report = overview.account(:moss_api, "default")
      expect(report.in_use).to eq("file")
      expect(report.sources.map { |source| [source.source, source.names_account, source.in_use] })
        .to eq([["variables", false, false], ["file", true, true], ["database", true, false]])
      expect(report.overridden_sources).to eq(["database"])
      expect(report.versions.map { |version| [version.source, version.name, version.state, version.role, version.overridden_by] })
        .to eq([["file", "file version", :active, :active, nil],
          ["database", "db other stage", :other_stage, nil, "file"],
          ["database", "db new", :active, nil, "file"],
          ["database", "db old", :active, nil, "file"]])
      database = report.versions.select { |version| version.source == "database" }
      expect(database.map(&:id).last(2)).to eq([new.id, old.id])
      expect(database.last.credential.secret(:client_secret)).to eq(db_secret)
      expect(report.versions.find(&:role).credential.secret(:client_secret)).to eq(file_secret)
    end

    it "marks the active version and the fallbacks of the source in use" do
      old = travel_to(2.days.ago) { deposit! }
      new = travel_to(1.day.ago) { deposit! }
      use_overrides

      report = overview.account(:moss_api, "default")
      expect(report.in_use).to eq("database")
      expect(report.versions.map { |version| [version.id, version.role] }).to eq([[new.id, :active], [old.id, :fallback]])
      expect(report.versions.select(&:role).map(&:id)).to eq(Wsjrdp::Credentials.candidates(:moss_api, "default")
        .map(&:version_id))
    end

    it "marks everything below the variables as overridden by them" do
      deposit!
      use_overrides(variables: variables, file: local_file)

      report = overview.account(:moss_api, "default")
      expect(report.in_use).to eq("variables")
      expect(report.versions.map { |version| [version.source, version.overridden_by] })
        .to eq([["variables", nil], ["file", "variables"], ["database", "variables"]])
    end

    it "lists every account of every source, and says what became of the file and where the keys came from" do
      deposit!(account_key: "in_db")
      use_overrides(variables: variables({"HITOBITO_CREDENTIAL__TEST__API_KEY__ENV_ONLY__API_KEY" => "x"}),
        file: local_file)

      expect(overview.accounts.map { |report| [report.kind, report.account_key, report.in_use] })
        .to eq([["api_key", "env_only", "variables"], ["moss_api", "default", "file"], ["moss_api", "in_db", "database"]])
      expect(overview.file.status).to eq(:read)
      expect(overview.keys.source).to eq(Wsjrdp::Credentials::Keys.current.source)
    end

    it "hands on the warnings of a database version" do
      production = Wsjrdp::Credentials::Keys.new("production:#{"d" * 64}", stage: "production")
      Wsjrdp::Credentials::Deposit.call(kind: "api_key", account_key: "mailcow", keys: production,
        values: {"base_url" => "http://mailcow.example.org", "api_key" => "made-up-api-key"})
      report = Wsjrdp::Credentials::Overview.new(keys: production).account(:api_key, "mailcow")

      expect(report.versions.first.warnings.map(&:to_s)).to eq(["base_url: not_https"])
    end

    it "lists every key: this stage's, the active one first, then those of other stages" do
      fingerprint = ->(secret) { Wsjrdp::Credentials::Keys.fingerprint_of(secret) }
      keys = Wsjrdp::Credentials::Keys.new("staging:#{"a" * 64},test:#{"b" * 64},test:#{"c" * 64}", stage: "test")
      entries = Wsjrdp::Credentials::Overview.new(keys: keys).keys.entries

      expect(entries.map { |entry| [entry.stage, entry.fingerprint, entry.role] }).to eq([
        ["test", fingerprint.call("b" * 64), :active],
        ["test", fingerprint.call("c" * 64), :accepted],
        ["staging", fingerprint.call("a" * 64), :other_stage]
      ])
    end

    it "keeps the fact that a file was skipped" do
      use_overrides(file: local_file(file_text.sub("stage: test", "stage: staging")))

      expect(overview.file.status).to eq(:other_stage)
      expect(overview.file.file_stage).to eq("staging")
      expect(overview.account(:moss_api, "default").in_use).to eq("database")
    end

    it "prints no value, no version name, no comment and no key in anything it hands out" do
      key_secret = "f7" * 32
      other_secret = "e8" * 32
      keys_text = "stage: test\nkeys: [\"test:#{key_secret}\", \"staging:#{other_secret}\"]\nlabel: laptop-file\n"
      file = local_file(file_text.sub("stage: test\n", keys_text))
      deposit!(name: "made-up db name", comment: "made-up db comment")
      use_overrides(variables: variables(env.merge("#{prefix}NAME" => "made-up env name")), file: file)
      keys = Wsjrdp::Credentials::Keys.from_sources(variable: nil, label: nil, file: file, test_value: nil,
        logger: Logger.new(StringIO.new))
      handed_out = described_class.new(keys: keys)
      report = handed_out.account(:moss_api, "default")
      dumpable_checked = [handed_out, report, *report.sources, *report.versions, handed_out.file, handed_out.keys,
        *handed_out.keys.entries, *keys.other_stage_keys]
      objects = dumpable_checked + [handed_out.accounts]

      expect(report.versions.map(&:name)).to include("made-up env name", "file version", "made-up db name")
      objects.each do |object|
        shown = [object.inspect, object.to_s, object.pretty_inspect, PP.pp({o: object}, +""), object.to_json,
          object.as_json.to_s, JSON.generate({"o" => object}), [object].inspect]
        [db_secret, file_secret, env_secret, key_secret, other_secret, "made-up env name", "file version", "made-up db name",
          "made-up db comment"].each do |secret|
          shown.each { |text| expect(text).not_to include(secret), "#{object.class}: #{text}" }
        end
      end
      dumpable_checked.each do |object|
        expect { Marshal.dump(object) }.to raise_error(TypeError), object.class.name
        expect { YAML.dump(object) }.to raise_error(TypeError), object.class.name
      end
      expect(handed_out.keys.fingerprints).to eq([Wsjrdp::Credentials::Keys.fingerprint_of(key_secret)])
      expect(handed_out.keys.entries.map(&:fingerprint))
        .to eq([key_secret, other_secret].map { |secret| Wsjrdp::Credentials::Keys.fingerprint_of(secret) })
      expect(handed_out.file).not_to respond_to(:key_entries)
      expect(handed_out).not_to respond_to(:overrides)
    end
  end

  describe "the boot wiring" do
    def initializer
      HitobitoWsjrdp2027::Wagon.initializers.find { |init| init.name == "wsjrdp_2027.credential_environment" }
    end

    it "takes the keys and the variables of the store behind lambdas, and the label, into the configuration" do
      app = Struct.new(:config).new(ActiveSupport::OrderedOptions.new.tap { |c| c.x = ActiveSupport::OrderedOptions.new })
      allow(ENV).to receive(:to_h).and_return("PATH" => "/bin", "HITOBITO_CREDENTIAL_KEYS" => "k",
        "HITOBITO_CREDENTIAL_LABEL" => "l", "#{prefix}CLIENT_SECRET" => env_secret, "HITOBITO_CREDENTIALS" => "x")

      key_text = "test:#{"e6" * 32}"
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("HITOBITO_CREDENTIAL_KEYS").and_return(key_text)
      allow(ENV).to receive(:[]).with("HITOBITO_CREDENTIAL_LABEL").and_return("laptop-a")

      initializer.run(app)
      expect(app.config.x.credential_label).to eq("laptop-a")
      expect(app.config.x.credential_variables.call).to eq("#{prefix}CLIENT_SECRET" => env_secret,
        "HITOBITO_CREDENTIALS" => "x")
      expect(app.config.x.credential_variables.call).to be_frozen
      expect(app.config.x.credential_keys.call).to eq(key_text)
      [app.config.x.inspect, app.config.x.to_s, app.config.inspect].each do |shown|
        expect(shown).not_to include(env_secret)
        expect(shown).not_to include("e6" * 32)
      end
    end

    it "has read the overrides at boot, before any example ran, without the file in test" do
      expect(CredentialsOverridesSpec::OVERRIDES_AT_BOOT).to be_a(Wsjrdp::Credentials::Overrides)
      expect(CredentialsOverridesSpec::OVERRIDES_AT_BOOT.file.status).to be_in([:absent, :not_read_test])
    end

    it "builds the overrides from the captured variables and the file, never reading the file in test" do
      Dir.mktmpdir("wsjrdp-credentials-spec") do |dir|
        path = File.join(dir, "wsjrdp_credentials.local.yml")
        File.write(path, file_text)
        allow(Rails.configuration.x).to receive(:credential_variables).and_return(-> { env })

        overrides = Wsjrdp::Credentials::Overrides.build(path: path)
        expect(overrides.variables.account_names).to eq([%w[moss_api default]])
        expect(overrides.file.status).to eq(:not_read_test)

        read = Wsjrdp::Credentials::Overrides.build(path: path, test: false)
        expect(read.file.account_names).to eq([%w[moss_api default]])
      end
    end

    describe ".reload!" do
      around do |example|
        saved = [Wsjrdp::Credentials::Overrides, Wsjrdp::Credentials::Keys].map { |c| c.instance_variable_get(:@current) }
        example.run
      ensure
        [Wsjrdp::Credentials::Overrides, Wsjrdp::Credentials::Keys].zip(saved) { |c, v| c.instance_variable_set(:@current, v) }
      end

      it "takes the file read again, and the keys with it" do
        read = Wsjrdp::Credentials::Overrides.new(variables: variables({}), file: local_file)
        allow(Wsjrdp::Credentials::Overrides).to receive(:build).and_return(read)
        Wsjrdp::Credentials::Keys.current

        Wsjrdp::Credentials::Overrides.reload!
        expect(Wsjrdp::Credentials::Overrides.current).to be(read)
        expect(Wsjrdp::Credentials::Keys.instance_variable_get(:@current)).not_to be_nil
      end

      it "keeps the old state when the file has a problem" do
        before = Wsjrdp::Credentials::Overrides.current
        allow(Wsjrdp::Credentials::Overrides).to receive(:build)
          .and_raise(Wsjrdp::Credentials::ConfigurationError, "broken")

        expect { Wsjrdp::Credentials::Overrides.reload! }.to raise_error(Wsjrdp::Credentials::ConfigurationError)
        expect(Wsjrdp::Credentials::Overrides.current).to be(before)
      end
    end
  end
end
