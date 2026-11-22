# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Standalone, without Rails (see standalone.rb).
require_relative "standalone"

# HITOBITO_CREDENTIAL__<STAGE>__<KIND>__<ACCOUNT>__<FIELD>: one version per
# account, only the instance's own stage, every variable of the prefix
# understood. The environment is handed in; the values are made up.
describe Wsjrdp::Credentials::Variables do
  let(:kinds) { Wsjrdp::Credentials::Kinds.load }
  let(:prefix) { "HITOBITO_CREDENTIAL__DEVELOPMENT__MOSS_API__DEFAULT__" }
  let(:secret) { "made-up-client-secret-4711" }
  let(:moss) { {"#{prefix}CLIENT_ID" => "made-up-client", "#{prefix}CLIENT_SECRET" => secret} }

  def variables(env, stage: "development") = described_class.new(env, stage: stage, kinds: kinds)

  def refused(env, stage: "development")
    expect { variables(env, stage: stage) }.to raise_error(Wsjrdp::Credentials::ConfigurationError) { |error|
      yield error.message if block_given?
      env.each_value { |value| expect(error.message).not_to include(value) if value.length > 3 }
    }
  end

  describe "the grammar" do
    it "names an account by its key in upper case, each of _ @ , . + - as _" do
      {"default" => "DEFAULT", "finanzen_test" => "FINANZEN_TEST", "foo@worldscoutjamboree.de" => "FOO_WORLDSCOUTJAMBOREE_DE",
       "a.b" => "A_B", "a-b" => "A_B", "straße" => "STRASSE", "müller+1" => "MÜLLER_1"}.each do |key, part|
        expect(described_class.account_part(key)).to eq(part), key
        expect(described_class.account_part?(part)).to be(true), part
      end
    end

    it "reads the variables of a key that is no name, for every key that maps to its part" do
      source = variables({"HITOBITO_CREDENTIAL__DEVELOPMENT__MOSS_API__FOO_WORLDSCOUTJAMBOREE_DE__CLIENT_ID" => "made-up-client",
                          "HITOBITO_CREDENTIAL__DEVELOPMENT__MOSS_API__FOO_WORLDSCOUTJAMBOREE_DE__CLIENT_SECRET" => secret})

      credential = source.answer("moss_api", "Foo@WorldScoutJamboree.de").candidates.first
      expect(credential.account_key).to eq("foo@worldscoutjamboree.de")
      expect(credential.secret(:client_secret)).to eq(secret)
      expect(source.answer("moss_api", "foo-worldscoutjamboree.de").candidates.first.account_key)
        .to eq("foo-worldscoutjamboree.de")
      expect(source.answer("moss_api", "foo@worldscoutjamboree.org")).to be_nil
      expect(source.account_names).to eq([%w[moss_api foo_worldscoutjamboree_de]])
    end

    it "makes one version of the variables of an account, with its name and instants" do
      env = moss.merge("#{prefix}NAME" => "Key December", "#{prefix}CREATED_AT" => "2026-11-20T09:00Z",
        "#{prefix}VALID_FROM" => "2026-12-01", "#{prefix}EXPIRES_AT" => "2027-05-19T00:00+01:00")
      account = variables(env).account("moss_api", "default")

      expect(account.versions.size).to eq(1)
      expect(account.versions.first).to have_attributes(position: 1, name: "Key December",
        created_at: Time.utc(2026, 11, 20, 9), valid_from: Time.utc(2026, 12, 1),
        expires_at: Time.utc(2027, 5, 18, 23))
      expect(account.versions.first.given_values).to eq("client_id" => "made-up-client", "client_secret" => secret)
    end

    it "answers for an account it names, and casts the strings with the kind" do
      env = {"HITOBITO_CREDENTIAL__DEVELOPMENT__MAIL_ACCOUNT__FINANZEN__MAIL_FROM" => "finanzen@example.org",
             "HITOBITO_CREDENTIAL__DEVELOPMENT__MAIL_ACCOUNT__FINANZEN__SMTP_HOST" => "mail.example.org",
             "HITOBITO_CREDENTIAL__DEVELOPMENT__MAIL_ACCOUNT__FINANZEN__SMTP_PORT" => "1025",
             "HITOBITO_CREDENTIAL__DEVELOPMENT__MAIL_ACCOUNT__FINANZEN__SMTP_PASSWORD" => secret}
      source = variables(env)
      credential = source.answer("mail_account", "finanzen").candidates.first

      expect(credential[:smtp_port]).to eq(1025)
      expect(credential.secret(:smtp_password)).to eq(secret)
      expect(credential[:smtp_security]).to eq("starttls")
      expect(source.answer("mail_account", "other")).to be_nil
      expect(source.answer("moss_api", "finanzen")).to be_nil
    end

    it "takes a field the kind does not have as a public further field, a misspelt one too" do
      env = moss.merge("#{prefix}TENANT" => "made-up-tenant", "#{prefix}CLIENT_SECRT" => "made-up-typo")
      source = variables(env)
      credential = source.answer("moss_api", "default").candidates.first

      expect(source.problems).to be_empty
      expect(credential.further_field_names).to eq(%w[client_secrt tenant])
      expect([credential[:tenant], credential[:client_secrt]]).to eq(%w[made-up-tenant made-up-typo])
      expect { credential.secret(:tenant) }.to raise_error(Wsjrdp::Credentials::Credential::WrongAccess)
    end

    it "takes an empty value as not set" do
      env = moss.merge("#{prefix}SCOPE" => "", "#{prefix}EXPIRES_AT" => "", "#{prefix}NAME" => "")
      version = variables(env).account("moss_api", "default").versions.first

      expect(version).to have_attributes(name: nil, expires_at: nil)
      expect(variables(env).answer("moss_api", "default").candidates.first[:scope]).to eq("read")
    end

    it "takes a value of an enum field beyond its suggestions, in production too" do
      env = moss.merge("#{prefix}SCOPE" => "admin")
      expect(variables(env).answer("moss_api", "default").candidates.first[:scope]).to eq("admin")

      production = env.transform_keys { |name| name.sub("__DEVELOPMENT__", "__PRODUCTION__") }
      source = variables(production, stage: "production")
      expect(source.problems).to be_empty
      expect(source.answer("moss_api", "default").candidates.first[:scope]).to eq("admin")
    end

    it "leaves alone what does not begin with HITOBITO_CREDENTIAL, and the two variables of the keys" do
      env = {"PATH" => "/usr/bin", "HITOBITO_SERVICE_TOKEN_HMAC_KEYS" => "x",
             "HITOBITO_CREDENTIAL_KEYS" => "development:#{"a" * 64}", "HITOBITO_CREDENTIAL_LABEL" => "laptop-a"}

      expect(variables(env).accounts).to eq({})
    end
  end

  describe "the stage" do
    it "ignores a variable of another stage with a warning, without checking its kind or field" do
      source = variables(moss.merge("HITOBITO_CREDENTIAL__STAGING__MOSS_API__OTHER__CLIENT_ID" => "x",
        "HITOBITO_CREDENTIAL__TEST__NO_SUCH_KIND__DEFAULT__NO_FIELD" => "y"))

      expect(source.account_names).to eq([%w[moss_api default]])
      expect(source.warnings).to eq([
        "HITOBITO_CREDENTIAL__STAGING__MOSS_API__OTHER__CLIENT_ID belongs to stage staging, this is development",
        "HITOBITO_CREDENTIAL__TEST__NO_SUCH_KIND__DEFAULT__NO_FIELD belongs to stage test, this is development"
      ])
    end

    it "refuses a production variable outside production" do
      %w[development staging test].each do |stage|
        refused({"HITOBITO_CREDENTIAL__PRODUCTION__MOSS_API__DEFAULT__CLIENT_SECRET" => secret}, stage: stage) do |message|
          expect(message).to include("a production variable outside production (stage #{stage})")
        end
      end
    end

    it "takes the production variables in production" do
      env = {"HITOBITO_CREDENTIAL__PRODUCTION__MOSS_API__DEFAULT__CLIENT_ID" => "made-up-client",
             "HITOBITO_CREDENTIAL__PRODUCTION__MOSS_API__DEFAULT__CLIENT_SECRET" => secret}

      expect(variables(env, stage: "production").answer("moss_api", "default").candidates.size).to eq(1)
    end

    it "does not repeat a stage that may be a secret" do
      source = variables({"HITOBITO_CREDENTIAL__#{"AB" * 32}__MOSS_API__DEFAULT__CLIENT_ID" => "x"})

      expect(source.warnings.join).to include("belongs to another stage")
      expect(source.warnings.join).not_to include("AB" * 32)
    end
  end

  describe "strictness" do
    {
      "HITOBITO_CREDENTIALS_KEYS" => "not a variable of the credential store",
      "HITOBITO_CREDENTIAL_KEY" => "not a variable of the credential store",
      "HITOBITO_CREDENTIAL__DEVELOPMENT__MOSS_API__CLIENT_ID" => "not of the form",
      "HITOBITO_CREDENTIAL__DEVELOPMENT__MOSS_API__DEFAULT__CLIENT_ID__X" => "not of the form",
      "HITOBITO_CREDENTIAL__development__MOSS_API__DEFAULT__CLIENT_ID" => "not in upper case",
      "HITOBITO_CREDENTIAL__DEVELOPMENT__MOSS_API___DEFAULT__CLIENT_ID" => "the account key is not an account key in upper case",
      "HITOBITO_CREDENTIAL__DEVELOPMENT__MOSS_API__#{"A" * 193}__CLIENT_ID" => "the account key is not an account key in upper case",
      "HITOBITO_CREDENTIAL__DEVELOPMENT__MOSS_API__İSTANBUL__CLIENT_ID" => "the account key is not an account key in upper case",
      "HITOBITO_CREDENTIAL__DEVELOPMENT__MOSS_API__DEFAULT_ __CLIENT_ID" => "a part is not in upper case",
      "HITOBITO_CREDENTIAL__DEVELOPMENT__MOSS_API__Müller__CLIENT_ID" => "a part is not in upper case",
      "HITOBITO_CREDENTIAL__DEVELOPMENT__1MOSS__DEFAULT__CLIENT_ID" => "the kind is not upper-case snake",
      "HITOBITO_CREDENTIAL__DEV-1__MOSS_API__DEFAULT__CLIENT_ID" => "not in upper case",
      "HITOBITO_CREDENTIAL__DEVELOPMENT__NO_SUCH_KIND__DEFAULT__CLIENT_ID" => "no kind no_such_kind in",
      "HITOBITO_CREDENTIAL__DEVELOPMENT__MOSS_API__DEFAULT__VALID_FROM" => "not an instant",
      "HITOBITO_CREDENTIAL__DEVELOPMENT__MOSS_API__DEFAULT__EXPIRES_AT" => "not an instant",
      "HITOBITO_CREDENTIAL__DEVELOPMENT__MOSS_API__DEFAULT__CREATED_AT" => "not an instant"
    }.each do |name, expected|
      it "refuses #{name[0, 70]} outside production" do
        refused({name => "made-up-value-31.12.2026"}) { |message| expect(message).to include(expected) }
      end
    end

    it "refuses a NAME that is not valid text, and an expiry not after the start" do
      refused({"#{prefix}NAME" => "made-up\u0000name"}) { |message| expect(message).to include("NAME: is not valid text") }
      refused(moss.merge("#{prefix}VALID_FROM" => "2027-01-01", "#{prefix}EXPIRES_AT" => "2027-01-01")) do |message|
        expect(message).to include("#{prefix}EXPIRES_AT: is not after valid_from")
      end
    end

    it "names every problem in one message, never a value" do
      refused(moss.merge("#{prefix}EXPIRES_AT" => "tomorrow-#{secret}", "#{prefix}VALID_FROM" => secret)) do |message|
        expect(message).to start_with("HITOBITO_CREDENTIAL__… variables (stage development): ")
        expect(message).to include("EXPIRES_AT: not an instant", "VALID_FROM: not an instant")
        expect(message).not_to include(secret)
      end
    end

    it "shows a part of a name only when it is a name" do
      long = "A1" * 32
      refused({"#{prefix}#{long}" => "x", "HITOBITO_CREDENTIAL#{long}" => "y"}) do |message|
        expect(message).not_to include(long)
        expect(message).to include("#{prefix}(not a name)", "HITOBITO_CREDENTIAL(not a name)")
      end
    end

    it "names the variables of an account by their common start, a part that is no name as such" do
      expect(described_class.account_prefix("development", "moss_api", "default"))
        .to eq("HITOBITO_CREDENTIAL__DEVELOPMENT__MOSS_API__DEFAULT")
      expect(described_class.account_prefix("development", "moss_api", "Not A Name"))
        .to eq("HITOBITO_CREDENTIAL__DEVELOPMENT__MOSS_API__(not a name)")
      expect(described_class.account_prefix("development", "mail_account", "Foo@WorldScoutJamboree.de"))
        .to eq("HITOBITO_CREDENTIAL__DEVELOPMENT__MAIL_ACCOUNT__FOO_WORLDSCOUTJAMBOREE_DE")
    end

    describe "in production" do
      let(:prefix) { "HITOBITO_CREDENTIAL__PRODUCTION__MOSS_API__DEFAULT__" }

      it "starts, ignoring a variable that does not belong to this stage as far as one can tell" do
        source = variables(moss.merge("HITOBITO_CREDENTIALS" => "y",
          "HITOBITO_CREDENTIAL__PRODUKTION__MOSS_API__DEFAULT__EXPIRES_AT" => "2026-01-01",
          "HITOBITO_CREDENTIAL__STAGING__MOSS_API__DEFAULT__EXPIRES__AT" => "2026-01-01"), stage: "production")

        expect(source.problems.size).to eq(2)
        expect(source.warnings.size).to eq(1)
        expect(source.answer("moss_api", "default").candidates.size).to eq(1)
      end

      it "refuses an account with a problem as a whole, without falling back" do
        source = variables(moss.merge("#{prefix}EXPIRES_AT" => "tomorrow"), stage: "production")

        expect(source.problems).to eq(["#{prefix}EXPIRES_AT: #{Wsjrdp::InstantInput::MESSAGE}"])
        answer = source.answer("moss_api", "default")
        expect(answer.candidates).to eq([])
        expect(answer.states).to eq({refused: 1})
      end

      describe "a variable of this stage that is not understood" do
        let(:api) do
          {"HITOBITO_CREDENTIAL__PRODUCTION__API_KEY__A__BASE_URL" => "https://api.example.org",
           "HITOBITO_CREDENTIAL__PRODUCTION__API_KEY__A__API_KEY" => secret}
        end

        # A source behind the variables that must not be asked.
        let(:database) do
          Class.new do
            def answer(*) = raise("the database was asked")
          end.new
        end

        def unusable!(source, kind, account_key)
          lookup = Wsjrdp::Credentials::Lookup.new([source, database])
          expect(lookup.candidates(kind, account_key)).to eq([])
          expect(source.answer(kind, account_key).states).to eq({refused: 1})
        end

        it "refuses the account its first parts name, beside the well-formed variables of it" do
          %w[
            HITOBITO_CREDENTIAL__PRODUCTION__API_KEY__A__EXPIRES__AT
            HITOBITO_CREDENTIAL__PRODUCTION__API_KEY__A__expires_at
            HITOBITO_CREDENTIAL__PRODUCTION__API_KEY__a__EXPIRES_AT
          ].each do |name|
            source = variables(api.merge(moss).merge(name => "2026-01-01"), stage: "production")

            expect(source.problems.size).to eq(1), name
            unusable!(source, "api_key", "a")
            expect(source.answer("moss_api", "default").candidates.size).to eq(1), name
          end
        end

        it "refuses every account of the variables when it points at none of them" do
          %w[
            HITOBITO_CREDENTIAL__PRODUCTION__API_KEY__A_EXPIRES_AT
            HITOBITO_CREDENTIAL__PRODUCTION__API_KEY_A__EXPIRES_AT
            HITOBITO_CREDENTIAL__PRODUCTION_API_KEY__A__EXPIRES_AT
            HITOBITO_CREDENTIAL__PRODUCTION__APIKEY__A__EXPIRES_AT
          ].each do |name|
            source = variables(api.merge(moss).merge(name => "2026-01-01"), stage: "production")

            expect(source.problems.size).to eq(1), name
            expect(source.account_names).to contain_exactly(%w[api_key a], %w[moss_api default]), name
            unusable!(source, "api_key", "a")
            unusable!(source, "moss_api", "default")
          end
        end

        it "says so once in the log, naming the variable and no guessed account" do
          output = StringIO.new
          variables(api.merge("HITOBITO_CREDENTIAL__PRODUCTION__API_KEY__A_EXPIRES_AT" => "2026-01-01"),
            stage: "production").log_summary(Logger.new(output))

          lines = output.string.lines.grep(/ERROR/)
          expect(lines.size).to eq(1)
          expect(lines.first).to include("HITOBITO_CREDENTIAL__PRODUCTION__API_KEY__A_EXPIRES_AT: not of the form",
            "-- refused, no version is used: api_key/a")
          expect(output.string).not_to include(secret)
        end

        it "refuses the account it names, whether or not a well-formed variable names it" do
          %w[
            HITOBITO_CREDENTIAL__PRODUCTION__MOSS_API__DEFAULT__expires_at
            HITOBITO_CREDENTIAL__PRODUCTION__MOSS_API__DEFAULT__CLIENT__SECRET
          ].each do |name|
            [{}, api].each do |others|
              source = variables(others.merge(name => "2026-01-01"), stage: "production")

              unusable!(source, "moss_api", "default")
              expect(source.answer("api_key", "a")&.candidates&.size).to eq(others.empty? ? nil : 1), name
              output = StringIO.new
              source.log_summary(Logger.new(output))
              expect(output.string.lines.grep(/ERROR/).size).to eq(1)
              expect(output.string).to include("#{name}: ",
                "-- refused, no version is used: moss_api/default")
            end
          end
        end

        it "says when it names no account and the variables name none: nothing is refused" do
          output = StringIO.new
          source = variables({"HITOBITO_CREDENTIAL__PRODUCTION__API_KEY__A_EXPIRES_AT" => "2026-01-01"},
            stage: "production")
          source.log_summary(Logger.new(output))

          expect(source.account_names).to eq([])
          expect(source.answer("api_key", "a")).to be_nil
          expect(output.string).to include("HITOBITO_CREDENTIAL__PRODUCTION__API_KEY__A_EXPIRES_AT: not of the form",
            "-- the variable is ignored: the variables of stage production name no account to refuse")
          expect(output.string).not_to include("refused,")
        end

        it "refuses the account a name without the full prefix names, and stops every other stage" do
          name = "HITOBITO_CREDENTIAL_PRODUCTION__MOSS_API__DEFAULT__EXPIRES_AT"
          source = variables(api.merge(moss).merge(name => "2026-01-01"), stage: "production")

          unusable!(source, "moss_api", "default")
          expect(source.answer("api_key", "a").candidates.size).to eq(1)
          refused({"HITOBITO_CREDENTIAL_DEVELOPMENT__MOSS_API__DEFAULT__EXPIRES_AT" => "2026-01-01"}) do |message|
            expect(message).to include("not a variable of the credential store")
          end
        end

        it "refuses every account for a name that is not valid UTF-8, and stops every other stage" do
          name = (+"HITOBITO_CREDENTIAL__PRODUCTION__MOSS_API__DEFAULT__\xFF").force_encoding("UTF-8")
          source = variables(api.merge(moss).merge(name => "2026-01-01"), stage: "production")

          unusable!(source, "moss_api", "default")
          unusable!(source, "api_key", "a")
          expect { variables({name.sub("PRODUCTION", "DEVELOPMENT") => "x"}) }
            .to raise_error(Wsjrdp::Credentials::ConfigurationError, /the name is not valid text/)
        end

        it "leaves a well-formed set without it as it was" do
          source = variables(api.merge(moss), stage: "production")

          expect(source.problems).to eq([])
          expect(source.answer("api_key", "a").candidates.size).to eq(1)
          expect(source.answer("moss_api", "default").candidates.size).to eq(1)
        end

        it "is not one when it belongs to another stage: that refuses nothing" do
          source = variables(api.merge("HITOBITO_CREDENTIAL__STAGING__API_KEY__A_EXPIRES_AT" => "2026-01-01",
            "HITOBITO_CREDENTIAL__STAGING__API_KEY__A__EXPIRES_AT" => "2026-01-01"), stage: "production")

          expect(source.answer("api_key", "a").candidates.size).to eq(1)
        end
      end

      it "logs a variable it cannot place as ignored" do
        output = StringIO.new
        variables({"HITOBITO_CREDENTIALS" => "y"}, stage: "production").log_summary(Logger.new(output))

        expect(output.string).to include("HITOBITO_CREDENTIALS: not a variable of the credential store",
          "-- the variable is ignored")
      end

      it "logs the problems and the warnings, never a value" do
        output = StringIO.new
        variables(moss.merge("#{prefix}EXPIRES_AT" => secret,
          "HITOBITO_CREDENTIAL__STAGING__MOSS_API__DEFAULT__CLIENT_ID" => secret), stage: "production")
          .log_summary(Logger.new(output))

        expect(output.string).to include("ERROR",
          "EXPIRES_AT: not an instant", "-- refused, no version is used: moss_api/default", "WARN",
          "belongs to stage staging", "overriding moss_api/default")
        expect(output.string).not_to include(secret)
      end
    end
  end

  describe "hygiene" do
    let(:source) { variables(moss.merge("#{prefix}NAME" => "made-up name")) }
    let(:shown) { [source, source.answer("moss_api", "default"), *source.account("moss_api", "default").versions] }
    let(:secrets) { [secret, "made-up name"] }

    include_examples "credential hygiene"

    it "shows the stage and the accounts" do
      expect(source.inspect).to eq("#<Wsjrdp::Credentials::Variables stage=development accounts=moss_api/default>")
      expect(source.summary).to eq("HITOBITO_CREDENTIAL__… variables: stage development, overriding moss_api/default")
    end
  end
end
