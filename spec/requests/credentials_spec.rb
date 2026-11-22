# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The credential store pages. No response may hold a secret value or an
# encrypted text, except the answer of a reveal. Every value is made up.
describe "Credential store pages", type: :request do
  let(:admin) { Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person }
  let(:kinds) { Wsjrdp::Credentials::Kinds.current }
  let(:password) { "made-up-smtp-password-4711" }
  let(:moss_secret) { "made-up-moss-secret-0815" }
  let(:mail_values) do
    {"mail_from" => "finanzen@example.org", "smtp_host" => "mail.example.org", "smtp_password" => password}
  end

  before { use_overrides }

  def html = Capybara.string(response.body)

  # The empty template row of further fields (a parser keeps a template's
  # content apart).
  def further_template = response.body[%r{<template[^>]*credential-further-template[^>]*>.*?</template>}m].to_s

  def deposit!(kind: "mail_account", account_key: "finanzen", values: mail_values, **options)
    Wsjrdp::Credentials::Deposit.call(kind: kind, account_key: account_key, values: values, **options)
      .tap { |result| expect(result).to be_saved }.record
  end

  def moss!(**options)
    deposit!(kind: "moss_api", account_key: "default",
      values: {"client_id" => "made-up-client", "client_secret" => moss_secret}, **options)
  end

  # The variables name moss_api/default.
  def use_env_override
    use_overrides(variables: Wsjrdp::Credentials::Variables.new(
      {"HITOBITO_CREDENTIAL__TEST__MOSS_API__DEFAULT__CLIENT_ID" => "env-client",
       "HITOBITO_CREDENTIAL__TEST__MOSS_API__DEFAULT__CLIENT_SECRET" => "made-up-env-secret"},
      stage: "test", kinds: kinds
    ))
  end

  # What the edit form carries as credential[lock].
  def lock_of(row) = row.reload.updated_at.utc.iso8601(6)

  def secret_of(row, field) = row.reload.field_values(keys: Wsjrdp::Credentials::Keys.current)[field]

  # A row with an encrypted public field, as a changed kind may leave it.
  def seal_public!(row, field, value)
    row.write_field(field, value, secret: true, key: Wsjrdp::Credentials::Keys.current.active)
    row.save!
    row
  end

  # A new active key; the committed test key is still accepted.
  def other_keys = Wsjrdp::Credentials::Keys.new("test:#{"c" * 64},#{Settings.credentials.keys_default}", stage: "test")

  def expect_nothing_secret(*secrets, rows: WsjrdpCredential.all)
    texts = secrets + rows.flat_map { |row| row.sealed_texts.values }
    texts.each { |text| expect(response.body).not_to include(text) }
  end

  describe "the rights" do
    it "refuse every page and action to who is no admin" do
      row = deposit!
      requests = [
        [:get, "/credentials"], [:get, "/credentials/new"], [:get, "/credentials/mail_account/finanzen"],
        [:post, "/credentials/mail_account/finanzen/reveal"], [:get, "/credentials/mail_account/finanzen/versions/new"],
        [:post, "/credentials/mail_account/finanzen/versions"], [:get, "/credentials/versions/#{row.id}/edit"],
        [:patch, "/credentials/versions/#{row.id}"], [:delete, "/credentials/versions/#{row.id}"],
        [:post, "/credentials/versions/#{row.id}/revoke"], [:post, "/credentials/versions/#{row.id}/unrevoke"],
        [:post, "/credentials/versions/#{row.id}/rekey"]
      ]
      requests.each do |verb, path|
        sign_in(people(:cmt_leader)) # for the next request only: an exception leaves no session behind
        expect { public_send(verb, path) }.to raise_error(CanCan::AccessDenied), "#{verb} #{path}"
      end
      expect(row.reload).to be_persisted
    end
  end

  describe "a sign-in by token" do
    # Each way hitobito signs in without a session, all for the admin.
    def token_headers
      service_token = ServiceToken.create!(layer: groups(:root), name: "Skript", people: true,
        permission: "layer_and_below_full", acting_person: admin)
      oauth_token = Fabricate(:access_token, application: Fabricate(:application), scopes: "api",
        resource_owner_id: admin.id)
      {"personal token" => {"X-User-Email" => admin.email, "X-User-Token" => admin.generate_authentication_token!},
       "service token" => {"X-Token" => service_token.plain_token},
       "OAuth token" => {"Authorization" => "Bearer #{oauth_token.token}"}}
    end

    it "is refused for the pages and the reveal" do
      row = deposit!
      token_headers.each do |way, headers|
        get "/credentials/mail_account/finanzen", headers: headers
        expect(response).to have_http_status(403), way
        get "/credentials/versions/#{row.id}/edit", headers: headers
        expect(response).to have_http_status(403), way
        post "/credentials/mail_account/finanzen/reveal", headers: headers,
          params: {source: "database", version_id: row.id, field: "smtp_password"}
        expect(response).to have_http_status(403), way
        expect(response.body).not_to include(password)
      end
    end

    it "leaves a browser session alone" do
      deposit!
      sign_in(admin)

      get "/credentials/mail_account/finanzen"

      expect(response).to have_http_status(200)
    end
  end

  context "as an admin" do
    before { sign_in(admin) }

    describe "a public field lying sealed" do
      it "is masked in the list, the prefill of a new version and the edit form" do
        row = seal_public!(deposit!, "mail_from", "made-up-sealed@example.org")
        seal_public!(row, "smtp_host", "made-up-sealed-host")

        sealed = %w[made-up-sealed@example.org made-up-sealed-host]
        get "/credentials"
        expect(html.find("tr[data-credential-account='finanzen']")).to have_text("aktiv")
        expect_nothing_secret(*sealed)
        get "/credentials/mail_account/finanzen/versions/new"
        expect(html.find("input[name='credential[fields][smtp_host]']")[:value].to_s).to eq("")
        expect_nothing_secret(*sealed)
        get "/credentials/versions/#{row.id}/edit"
        expect(html.find("input[name='credential[fields][smtp_host]']")[:value].to_s).to eq("")
        expect_nothing_secret(*sealed)
        get "/credentials/mail_account/finanzen"
        expect(html.find("[data-credential-field='smtp_host']")).to have_text("••••••••")
        expect_nothing_secret(*sealed)
      end

      it "keeps its value when the edit form is sent untouched" do
        row = seal_public!(deposit!, "smtp_host", "made-up-sealed-host")
        # What the form sends: every field, the encrypted one empty as
        # shown, the secret ones as filled in.
        fields = {mail_from: "finanzen@example.org", smtp_host: "", smtp_port: "587", smtp_security: "starttls",
                  imap_port: "993", smtp_username: "", imap_host: "", imap_username: "", sent_folder: ""}
        sent = {name: "Neu", comment: "", fields: fields, secret: {smtp_password: password, imap_password: ""},
                valid_from: "", expires_at: "", lock: lock_of(row)}
        patch "/credentials/versions/#{row.id}", params: {credential: sent}

        expect(row.reload.name).to eq("Neu")
        expect(secret_of(row, "smtp_host")).to eq("made-up-sealed-host")
        expect(row.sealed?("smtp_host")).to be true
        expect(secret_of(row, "smtp_password")).to eq(password)
      end
    end

    describe "the list" do
      it "is in the menu, groups the accounts by kind and names the title field of the version in use" do
        deposit!
        deposit!(account_key: "alt", values: mail_values.merge("mail_from" => "alt@example.org"),
          expires_at: 1.day.ago, valid_from: 2.days.ago)
        moss!

        get "/credentials"

        expect(response).to have_http_status(:ok)
        mail = html.find("tbody[data-credential-kind='mail_account']")
        expect(mail.all("tr[data-credential-account]").pluck("data-credential-account")).to match_array(%w[alt finanzen])
        expect(mail.find("tr[data-credential-account='finanzen']")).to have_text("finanzen@example.org")
        expect(mail.find("tr[data-credential-account='finanzen']")).to have_text("aktiv")
        alt = mail.find("tr[data-credential-account='alt']")
        expect(alt).to have_text("keine aktive Version")
        expect(alt).not_to have_text("alt@example.org")
        expect(html.find("tbody[data-credential-kind='moss_api']")).to have_text("made-up-client")
        expect(html).to have_link("Zugangsdaten", href: "/credentials")
        expect_nothing_secret(password, moss_secret)
      end

      it "marks an override in use and counts the rows of other stages" do
        deposit!(kind: "moss_api", account_key: "default",
          values: {"client_id" => "db-client", "client_secret" => moss_secret})
        deposit!.update_columns(stage: "development")
        use_env_override

        get "/credentials"

        moss = html.find("tr[data-credential-account='default']")
        expect(moss).to have_text("ENV")
        expect(moss).to have_text("überschreibt Datenbank: 1 Version")
        expect(moss).to have_text("env-client")
        expect(html.find("tr[data-credential-account='finanzen']")).to have_text("development: 1")
        expect_nothing_secret(password, moss_secret, "made-up-env-secret")
      end

      it "shows each key with its fingerprint, role, stage and source" do
        get "/credentials"
        active = Wsjrdp::Credentials::Keys.current.active.fingerprint
        card = html.find("[data-credential-key='#{active}']")
        expect(card).to have_text("Fingerabdruck #{active} aktiv", normalize_ws: true)
        expect(card).to have_text("Umgebung test", normalize_ws: true)
        expect(card.find("[data-credential-key-source]"))
          .to have_text("Quelle Datei config/settings/test.yml (Eintrag credentials.keys_default)", normalize_ws: true)

        allow(Wsjrdp::Credentials::Keys).to receive(:current).and_return(other_keys)
        get "/credentials"
        expect(html.all("[data-credential-key]").pluck("data-credential-key"))
          .to match_array(other_keys.keys.map(&:fingerprint))
        expect(html.find("[data-credential-key='#{other_keys.keys.last.fingerprint}']")).to have_text("akzeptiert")
        expect(html.find("[data-credential-key='#{other_keys.active.fingerprint}'] [data-credential-key-source]"))
          .to have_text("Quelle Umgebungsvariable HITOBITO_CREDENTIAL_KEYS", normalize_ws: true)
      end

      it "lists the keys of other stages by fingerprint only" do
        secrets = {staging: "d" * 64, own: "e" * 64, long: "f" * 64}
        keys = Wsjrdp::Credentials::Keys.new(
          "staging:#{secrets[:staging]},test:#{secrets[:own]},#{"s" * 40}:#{secrets[:long]}",
          stage: "test", label: "laptop-a"
        )
        allow(Wsjrdp::Credentials::Keys).to receive(:current).and_return(keys)

        get "/credentials"

        own, staging, long = secrets.values_at(:own, :staging, :long).map { |secret| Wsjrdp::Credentials::Keys.fingerprint_of(secret) }
        roles = html.all("[data-credential-key]").to_h { |card| [card["data-credential-key"], card["data-credential-key-role"]] }
        expect(roles).to eq(own => "active", staging => "other_stage", long => "other_stage")
        staging_card = html.find("[data-credential-key='#{staging}']")
        expect(staging_card).to have_text("Bezeichnung laptop-a", normalize_ws: true)
        expect(staging_card).to have_text("Fingerabdruck #{staging} andere Umgebung", normalize_ws: true)
        expect(staging_card).to have_text("Umgebung staging", normalize_ws: true)
        expect(html.find("[data-credential-key='#{long}']")).not_to have_text("s" * 40)
        expect(html.find("#credentials-keys")).not_to have_text("Diese Umgebung hat keinen Schlüssel.")
        expect_nothing_secret(*secrets.values)
      end

      it "keeps the notice of no key here while it lists the keys of other stages" do
        keys = Wsjrdp::Credentials::Keys.new("staging:#{"d" * 64}", stage: "test")
        allow(Wsjrdp::Credentials::Keys).to receive(:current).and_return(keys)

        get "/credentials"

        expect(html.find("#credentials-keys")).to have_text("Diese Umgebung hat keinen Schlüssel.")
        expect(html.all("[data-credential-key]").pluck("data-credential-key-role")).to eq(%w[other_stage])
        expect_nothing_secret("d" * 64)
      end

      it "says when the instance has no key and when the local file was skipped" do
        file = Wsjrdp::Credentials::LocalFile.new("stage: staging\n", stage: "test", kinds: kinds)
        expect(file.status).to eq(Wsjrdp::Credentials::LocalFile::OTHER_STAGE)
        use_overrides(file: file)
        allow(Wsjrdp::Credentials::Keys).to receive(:current).and_return(Wsjrdp::Credentials::Keys.new(nil, stage: "test"))

        get "/credentials"

        expect(html).to have_css("#credentials-no-key")
        expect(html.find("#credentials-file-skipped")).to have_text("„staging“")
        expect(html.find("#credentials-keys")).to have_text("Diese Umgebung hat keinen Schlüssel.")
      end
    end

    describe "the account's page" do
      it "shows every version with its state, secret fields masked" do
        older = deposit!(name: "Postfach alt", comment: "vom Mail-Team")
        planned = deposit!(name: "Postfach geplant", valid_from: 10.days.from_now,
          values: mail_values.merge("smtp_password" => "made-up-planned-password"))
        newest = deposit!(name: "Postfach neu", values: mail_values.merge("smtp_password" => "made-up-new-password"),
          author: admin)

        get "/credentials/mail_account/finanzen"

        expect(response).to have_http_status(:ok)
        expect(response.headers["Cache-Control"]).to include("no-store")
        newest_card = html.find("#credential-version-#{newest.id}")
        older_card = html.find("#credential-version-#{older.id}")
        expect(newest_card).to have_link(admin.to_s, href: "/people/#{admin.id}")
        expect(newest_card.find("[data-credential-key-row]")).to have_text("(aktiver Schlüssel)")
        expect(newest_card.find("[data-credential-variables-row]"))
          .to have_text("HITOBITO_CREDENTIAL__TEST__MAIL_ACCOUNT__FINANZEN__<FELD>")
        expect(html.all("#credential-versions > .card").pluck(:id)).to match_array(["credential-version-#{newest.id}",
          "credential-version-#{planned.id}", "credential-version-#{older.id}"])
        expect(html).to have_css("[data-credential-in-use]", count: 1)
        expect(newest_card).to have_css("[data-credential-in-use]")
        chips = ->(card) { card.all("[data-credential-chip]").map { |chip| [chip["data-credential-chip"], chip.text.strip] } }
        expect(chips.call(newest_card)).to contain_exactly(%w[state aktiv], %w[source DB])
        expect(chips.call(older_card)).to contain_exactly(%w[state aktiv], %w[fallback Rückfall], %w[source DB])
        expect(older_card.find("[data-credential-fields]")).to have_text("Kommentar vom Mail-Team", normalize_ws: true)
        expect(older_card.find("[data-credential-field='smtp_host']")).to have_text("mail.example.org")
        smtp = older_card.find("[data-credential-field='smtp_password']")
        expect(smtp).to have_text("••••••••")
        expect(smtp).to have_button("Anzeigen")
        expect_nothing_secret(password, "made-up-planned-password", "made-up-new-password")
      end

      it "escapes the display name" do
        deposit!(name: "<b>Postfach</b>")

        %w[/credentials/mail_account/finanzen /credentials/mail_account/finanzen/versions/new].each do |path|
          get path
          expect(response.body).to include("&lt;b&gt;Postfach&lt;/b&gt;"), path
          expect(response.body).not_to include("<b>Postfach</b>"), path
        end
      end

      it "names what is wrong with a row and lists the rows of other stages, deletable only" do
        wrong = deposit!
        wrong.update_columns(public_data: wrong.public_data.merge("smtp_password" => "made-up-plain"))
        other = deposit!(account_key: "finanzen")
        other.update_columns(stage: "development")

        get "/credentials/mail_account/finanzen"

        card = html.find("#credential-version-#{wrong.id}")
        expect(card.find("[data-credential-hints]")).to have_text("Das Feld smtp_password liegt in der falschen Spalte")
        expect(card.find("[data-credential-field='smtp_password']")).to have_text("••••••••")
        other_card = html.find("#credential-version-#{other.id}")
        expect(other_card.find("[data-credential-chip='state']")).to have_text("andere Umgebung")
        expect(other_card.find("[data-credential-stage-row]")).to have_text("development")
        expect(other_card).to have_button("Löschen")
        expect(other_card).not_to have_link("Bearbeiten")
        expect(other_card).not_to have_button("Anzeigen")
        expect_nothing_secret(password, "made-up-plain")
      end

      it "shows the overrides read-only with their source, and what they override" do
        moss!
        use_env_override

        get "/credentials/moss_api/default"

        env = html.find("[data-credential-source='variables']")
        expect(env).to have_css("[data-credential-in-use]")
        expect(env.find("[data-credential-chip='source']")).to have_text("ENV")
        source_row = env.find("[data-credential-source-row]")
        expect(source_row).to have_text("Quelle Umgebungsvariablen HITOBITO_CREDENTIAL__TEST__MOSS_API__DEFAULT__…",
          normalize_ws: true)
        variables = env.all("[data-credential-field]").to_h do |row|
          [row["data-credential-field"], row.find("[data-credential-variable]").text]
        end
        expect(variables).to eq("base_url" => "…__BASE_URL", "client_id" => "…__CLIENT_ID",
          "client_secret" => "…__CLIENT_SECRET", "scope" => "…__SCOPE")
        expect(env.find("[data-credential-field='client_secret']")).to have_button("Anzeigen")
        expect(env).not_to have_link("Bearbeiten")
        database = html.find("[data-credential-source='database']")
        expect(database).not_to have_css("[data-credential-in-use]")
        expect(database.find("[data-credential-source-row]")).to have_text("Quelle Datenbank", normalize_ws: true)
        expect(database).not_to have_css("[data-credential-variable]")
        chips = database.all("[data-credential-chip]").pluck("data-credential-chip")
        expect(chips).to contain_exactly("state", "overridden", "source")
        expect_nothing_secret(moss_secret, "made-up-env-secret")
      end

      it "shows a YAML version with the local file as its source" do
        file = Wsjrdp::Credentials::LocalFile.new(<<~YAML, stage: "test", kinds: kinds)
          stage: test
          credentials:
            moss_api:
              default:
                versions:
                  - vars: {client_id: file-client, client_secret: made-up-file-secret}
        YAML
        use_overrides(file: file)

        get "/credentials/moss_api/default"
        expect(html.find("[data-credential-source='file'] [data-credential-chip='source']")).to have_text("YAML")
        expect(html.find("[data-credential-source='file'] [data-credential-source-row]"))
          .to have_text("Quelle Lokale Datei config/wsjrdp_credentials.local.yml", normalize_ws: true)
        expect(html).not_to have_css("[data-credential-variable]")
        expect_nothing_secret("made-up-file-secret")
      end

      it "shows a version whose kind left the registry, every field masked, and lets it be renamed" do
        row = deposit!
        row.update_columns(kind: "old_mail")

        get "/credentials/old_mail/finanzen"
        card = html.find("#credential-version-#{row.id}")
        expect(card).to have_text("Art unbekannt")
        expect(card.find("[data-credential-field='smtp_host']")).to have_text("••••••••")
        expect(html).not_to have_link("Neue Version hinterlegen")

        get "/credentials/versions/#{row.id}/edit"
        expect(html).not_to have_css("[data-credential-form-field]")
        patch "/credentials/versions/#{row.id}",
          params: {credential: {name: "Alt", comment: "", valid_from: "", expires_at: "", lock: lock_of(row)}}
        expect(row.reload.name).to eq("Alt")
        expect_nothing_secret(password)
      end

      it "is not found for an account no source names and an unknown kind" do
        expect { get "/credentials/nope/default" }.to raise_error(ActiveRecord::RecordNotFound)
        sign_in(admin)
        expect { get "/credentials/moss_api/Not%20A%20Name" }.to raise_error(ActiveRecord::RecordNotFound)
        sign_in(admin)
        get "/credentials/moss_api/Kasse"
        expect(response).to redirect_to("/credentials/moss_api/kasse")
      end
    end

    describe "a new account and a new version" do
      it "asks for the kind and the account key first" do
        get "/credentials/new", params: {kind: "moss_api", account_key: "Nicht gültig"}
        expect(response).to have_http_status(422)
        expect(html).to have_text("Die Bezeichnung ist ungültig.")

        get "/credentials/new", params: {kind: "moss_api", account_key: "kasse"}
        expect(response).to redirect_to("/credentials/moss_api/kasse/versions/new")
      end

      it "hands the display name on to the form of the first version, and refuses one that is no text" do
        get "/credentials/new", params: {kind: "moss_api", account_key: "kasse", name: "Key Mai"}
        expect(response).to redirect_to("/credentials/moss_api/kasse/versions/new?name=Key+Mai")
        follow_redirect!
        expect(html.find("input[name='credential[name]']")[:value]).to eq("Key Mai")

        get "/credentials/new", params: {kind: "moss_api", account_key: "kasse", name: "Key\u0000Mai"}
        expect(response).to have_http_status(422)
        expect(html).to have_text("Der Anzeigename ist kein gültiger Text.")
        expect(html.find("input[name='account_key']")[:value]).to eq("kasse")
      end

      it "takes a wider account key, folded, and names what is wrong with one" do
        get "/credentials/new", params: {kind: "mail_account", account_key: "Foo@WorldScoutJamboree.DE"}
        expect(response).to redirect_to("/credentials/mail_account/foo@worldscoutjamboree.de/versions/new")

        get "/credentials/new", params: {kind: "mail_account", account_key: "a/b..c-"}
        expect(response).to have_http_status(422)
        expect(html).to have_text("Nicht erlaubt: „/“")
        expect(html).to have_text("Zwei der Zeichen _ @ , . + - stehen hintereinander.")
        expect(html).to have_text("Am Anfang oder am Ende steht eines der Zeichen _ @ , . + -.")
      end

      it "warns of a key that looks like a token, on the page of a refused key" do
        get "/credentials/new", params: {kind: "moss_api", account_key: "550E8400-E29B-41D4-A716-446655440000 x"}
        expect(response).to have_http_status(422)
        expect(html).to have_text("Sieht aus wie ein Schlüssel oder Token.")
      end

      it "names as a token a long hex run, a UUID and a long run mixing letters and digits, not an ordinary name" do
        helper = ApplicationController.helpers
        token = ->(key) { helper.credential_account_key_warnings(key).any? { |warning| warning.include?("Token") } }

        ["a" * 8 + "0123456789abcdef0123456789abcdef", "550e8400-e29b-41d4-a716-446655440000",
          "mk_live_ZR8q4T2nB7xW1vY9pL3s", "foo@abcdef1234567890xyzw.de"].each do |key|
          expect(token.call(key)).to be(true), key
        end
        ["finanzen", "default", "foo@worldscoutjamboree.de", "vorname.nachname+test@example.org", "kasse2027",
          "mail_account_2027_finanzen", "müller"].each do |key|
          expect(token.call(key)).to be(false), key
        end
      end

      it "hands the page's script the names of the variables of the accounts there are" do
        deposit!(account_key: "foo@worldscoutjamboree.de")
        get "/credentials/new"

        config = html.find("#credentials-new-js", visible: :all)
        expect(JSON.parse(config["data-parts"])).to eq(
          "mail_account" => {"FOO_WORLDSCOUTJAMBOREE_DE" => ["foo@worldscoutjamboree.de"]}
        )
        expect(config["data-prefix"]).to eq("HITOBITO_CREDENTIAL__TEST")
        expect(config["data-length"]).to eq("64")
      end

      it "goes the whole way with a key holding @ + . , and a letter beyond ASCII" do
        key = "müller+test,1@worldscoutjamboree.de"
        path = "/credentials/mail_account/#{ERB::Util.url_encode(key).gsub("%40", "@").gsub("%2B", "+").gsub("%2C", ",")}"
        post "#{path}/versions", params: {credential: {fields: {mail_from: "a@example.org", smtp_host: "mail.example.org"},
                                                       secret: {smtp_password: password}}}

        row = WsjrdpCredential.last
        expect(row.account_key).to eq(key)
        expect(response).to redirect_to("#{path}#credential-version-#{row.id}")
        get path
        expect(response).to have_http_status(:ok)
        get "/credentials"
        expect(html).to have_link(key, href: path)
        expect(Wsjrdp::Credentials.fetch(:mail_account, key.upcase).version_id).to eq(row.id)
      end

      it "deposits a version from the form, the secret under a filtered parameter" do
        params = {credential: {name: "Key Mai", comment: "für die Kasse", fields: {client_id: "made-up-client"},
                               secret: {client_secret: moss_secret}, valid_from: "2027-01-10T08:00",
                               valid_from_zone: "app", expires_at: "2027-07-01T00:00", expires_at_zone: "utc"}}

        expect { post "/credentials/moss_api/kasse/versions", params: params }.to change(WsjrdpCredential, :count).by(1)

        row = WsjrdpCredential.last
        expect(response).to redirect_to("/credentials/moss_api/kasse#credential-version-#{row.id}")
        expect(row).to have_attributes(name: "Key Mai", comment: "für die Kasse", author: admin,
          valid_from: Time.utc(2027, 1, 10, 7), expires_at: Time.utc(2027, 7, 1))
        expect(secret_of(row, "client_secret")).to eq(moss_secret)
        expect(row.public_data).to include("client_id" => "made-up-client", "base_url" => "https://public-api.getmoss.com")
        expect(flash.to_h.values.join).not_to include(moss_secret)
        filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter(params)
        expect(filtered.to_s).not_to include(moss_secret)
      end

      it "names the errors, gives the typed name back, and gives the typed secret back" do
        post "/credentials/moss_api/kasse/versions",
          params: {credential: {name: "Kasse Juni", fields: {client_id: ""}, secret: {client_secret: moss_secret},
                                valid_from: "2027-02-01T00:00", expires_at: "2027-01-01T00:00", expires_at_zone: "utc"}}

        expect(response).to have_http_status(422)
        expect(WsjrdpCredential.count).to eq(0)
        expect(html.find("input[name='credential[name]']")[:value]).to eq("Kasse Juni")
        expect(html).to have_text("muss ausgefüllt werden")
        expect(html).to have_text("muss nach „Gültig ab“ liegen")
        secret_input = html.find("input[name='credential[secret][client_secret]']")
        expect(secret_input[:value]).to eq(moss_secret)
        expect(secret_input[:type]).to eq("password")
        expect(secret_input[:autocomplete]).to eq("new-password")
        expect(response.headers["Cache-Control"]).to include("no-store")
      end

      it "refuses a time that is none" do
        post "/credentials/moss_api/kasse/versions",
          params: {credential: {fields: {client_id: "c"}, secret: {client_secret: moss_secret}, valid_from: "morgen"}}

        expect(response).to have_http_status(422)
        expect(html).to have_text("ist kein Zeitpunkt")
      end

      it "prefills the public fields of the version in use but its title field, no secret" do
        moss!
        get "/credentials/moss_api/default/versions/new"

        expect(html.find("input[name='credential[fields][base_url]']")[:value]).to eq("https://public-api.getmoss.com")
        expect(html.find("input[name='credential[fields][scope]']")[:value]).to eq("read")
        expect(html.find("input[name='credential[fields][client_id]']")[:value].to_s).to eq("")
        expect(html.find("input[name='credential[secret][client_secret]']")[:value]).to be_blank
        expect(html).to have_text("Die bisherige Version bleibt")
        expect_nothing_secret(moss_secret)
      end

      it "names a fallback only where the database is in use with a usable version" do
        get "/credentials/moss_api/kasse/versions/new"
        expect(html).not_to have_text("Die bisherige Version bleibt")

        deposit!(expires_at: 1.day.ago, valid_from: 2.days.ago)
        deposit!.update_columns(stage: "development")
        get "/credentials/mail_account/finanzen/versions/new"
        expect(html).not_to have_text("Die bisherige Version bleibt")

        moss!
        use_env_override
        get "/credentials/moss_api/default/versions/new"
        expect(html).not_to have_text("Die bisherige Version bleibt")
        expect(html.find("#credential-form-overridden")).to have_text("Überschrieben durch ENV")
      end

      it "warns of a url that is not https in production, and saves" do
        production = Wsjrdp::Credentials::Keys.new("production:#{"d" * 64}", stage: "production")
        allow(Wsjrdp::Credentials::Keys).to receive(:current).and_return(production)

        post "/credentials/api_key/mailcow/versions",
          params: {credential: {fields: {base_url: "http://mailcow.example.org"}, secret: {api_key: "made-up-api-key"}}}

        expect(WsjrdpCredential.last).to have_attributes(stage: "production")
        expect(flash[:warning]).to eq("base_url: ist nicht https.")
        get "/credentials/api_key/mailcow"
        expect(html).to have_text("base_url: ist nicht https.")
        expect(response.body).not_to include("made-up-api-key")
      end
    end

    describe "changing a version" do
      let!(:row) { deposit!(name: "Postfach", comment: "alt", expires_at: Time.utc(2027, 6, 1, 12, 0, 30)) }

      def form_params(**overrides)
        {name: "Postfach", comment: "alt", fields: {mail_from: "finanzen@example.org", smtp_host: "mail.example.org",
                                                    smtp_port: "587", smtp_security: "starttls", imap_port: "993"},
         valid_from: "", expires_at: "2027-06-01T12:00:30", lock: lock_of(row)}.deep_merge(overrides)
      end

      it "fills the secret fields in with their current value, without a trash can" do
        get "/credentials/versions/#{row.id}/edit"

        expect(html.find("input[name='credential[name]']")[:value]).to eq("Postfach")
        expect(html.find("input[name='credential[expires_at]']")[:value]).to eq("2027-06-01T12:00:30")
        expect(html).not_to have_css("input[name^='credential[remove]']")
        input = html.find("input[name='credential[secret][smtp_password]']")
        expect(input).to have_attributes(value: password)
        expect(input[:type]).to eq("password")
        expect(html.find("input[name='credential[secret][imap_password]']")[:value]).to be_blank
        expect(html.find("input[name='credential[lock]']", visible: :all)[:value]).to eq(lock_of(row))
        expect(lock_of(row)).to match(/\.\d{6}Z\z/)
        expect_nothing_secret
      end

      it "keeps a secret sent as filled in and changes only what was touched" do
        with_versioning do
          patch "/credentials/versions/#{row.id}", params: {credential: form_params(name: "Postfach Finanzen",
            fields: {smtp_host: "smtp.example.org"}, secret: {smtp_password: password, imap_password: ""})}
        end

        expect(response).to redirect_to("/credentials/mail_account/finanzen#credential-version-#{row.id}")
        expect(row.reload).to have_attributes(name: "Postfach Finanzen", expires_at: Time.utc(2027, 6, 1, 12, 0, 30))
        expect(row.public_data["smtp_host"]).to eq("smtp.example.org")
        expect(secret_of(row, "smtp_password")).to eq(password)
        expect(row.sealed?("imap_password")).to be false
        trail = PaperTrail::Version.where(item: row).last
        expect(trail.changeset.keys).to contain_exactly("name", "public_data")
      end

      it "makes no change of a form sent as shown" do
        with_versioning do
          sent = form_params(secret: {smtp_password: password, imap_password: ""})
          expect { patch "/credentials/versions/#{row.id}", params: {credential: sent} }
            .not_to change(PaperTrail::Version, :count)
        end
        expect(row.reload.updated_at).to eq(row.created_at)
      end

      it "leaves a field and an instant the request leaves out untouched" do
        patch "/credentials/versions/#{row.id}",
          params: {credential: {comment: "neu", fields: {smtp_host: "smtp.example.org"}, lock: lock_of(row)}}

        expect(row.reload).to have_attributes(comment: "neu", name: "Postfach", expires_at: Time.utc(2027, 6, 1, 12, 0, 30))
        expect(row.public_data).to include("smtp_host" => "smtp.example.org", "mail_from" => "finanzen@example.org",
          "smtp_port" => 587, "imap_port" => 993)
        expect(secret_of(row, "smtp_password")).to eq(password)
      end

      it "offers an enum field as text with its values as suggestions, a typed value saved as it is" do
        row.update!(public_data: row.public_data.merge("smtp_security" => "ssl"))

        get "/credentials/versions/#{row.id}/edit"
        input = html.find("input[name='credential[fields][smtp_security]']")
        expect(input[:value]).to eq("ssl")
        expect(html.find("datalist##{input[:list]}", visible: :all).all("option", visible: :all).pluck(:value))
          .to match_array(%w[starttls tls none])

        patch "/credentials/versions/#{row.id}", params: {credential: form_params(fields: {smtp_security: "ssl"})}
        expect(row.reload.public_data["smtp_security"]).to eq("ssl")
        patch "/credentials/versions/#{row.id}", params: {credential: form_params(fields: {smtp_security: "x-tls"})}
        expect(row.reload.public_data["smtp_security"]).to eq("x-tls")
      end

      it "shows an enum field without a value with its default, and does not write it when left alone" do
        row.update!(public_data: row.public_data.except("smtp_security"))

        get "/credentials/versions/#{row.id}/edit"
        expect(html.find("input[name='credential[fields][smtp_security]']")[:value]).to eq("starttls")

        patch "/credentials/versions/#{row.id}", params: {credential: form_params(comment: "neu")}
        expect(row.reload.comment).to eq("neu")
        expect(row.public_data).not_to have_key("smtp_security")
      end

      it "shows the field errors too when an instant does not read" do
        patch "/credentials/versions/#{row.id}",
          params: {credential: form_params(fields: {smtp_port: "zwei"}, valid_from: "morgen")}

        expect(response).to have_http_status(422)
        expect(html).to have_text("ist keine ganze Zahl")
        expect(html).to have_text("ist kein Zeitpunkt")
      end

      it "refuses a form drawn before someone else changed the version, setting nothing back" do
        params = form_params(comment: "von mir")
        Wsjrdp::Credentials::Change.call(record: row, values: {"smtp_host" => "smtp.example.org"})

        patch "/credentials/versions/#{row.id}", params: {credential: params}

        expect(response).to have_http_status(422)
        expect(html).to have_text("Die Version wurde inzwischen geändert.")
        expect(html.find("input[name='credential[lock]']", visible: :all)[:value]).to eq(params[:lock])
        expect(row.reload).to have_attributes(comment: "alt")
        expect(row.public_data["smtp_host"]).to eq("smtp.example.org")
        # The form sent back holds the secret as before.
        expect(html.find("input[name='credential[secret][smtp_password]']")[:value]).to eq(password)
        expect_nothing_secret
      end

      it "replaces a secret that is changed and removes one that is emptied" do
        patch "/credentials/versions/#{row.id}",
          params: {credential: form_params(secret: {imap_password: "made-up-imap-password"})}
        expect(secret_of(row, "imap_password")).to eq("made-up-imap-password")

        patch "/credentials/versions/#{row.id}",
          params: {credential: form_params(secret: {smtp_password: "made-up-other", imap_password: ""})}
        expect(secret_of(row, "smtp_password")).to eq("made-up-other")
        expect(row.reload.sealed?("imap_password")).to be false
        expect(flash.to_h.values.join).not_to include("made-up")
      end

      it "refuses to empty a required secret field, and gives the form back as sent" do
        moss = moss!
        patch "/credentials/versions/#{moss.id}",
          params: {credential: {name: "", comment: "", secret: {client_secret: ""}, lock: lock_of(moss)}}

        expect(response).to have_http_status(422)
        expect(html).to have_text("muss ausgefüllt werden")
        expect(html.find("input[name='credential[secret][client_secret]']")[:value]).to be_blank
        expect(secret_of(moss, "client_secret")).to eq(moss_secret)
      end

      it "reads an instant in the app's zone and shows the errors of Change" do
        patch "/credentials/versions/#{row.id}",
          params: {credential: form_params(valid_from: "2027-07-01T10:00", valid_from_zone: "app")}

        expect(response).to have_http_status(422)
        expect(html).to have_text("muss nach „Gültig ab“ liegen")
        expect(row.reload.valid_from).to be_nil

        patch "/credentials/versions/#{row.id}",
          params: {credential: form_params(valid_from: "2027-01-01T10:00", valid_from_zone: "app")}
        expect(row.reload.valid_from).to eq(Time.utc(2027, 1, 1, 9))
      end

      it "locks the secret fields where the key is not the active one, and changes the rest" do
        allow(Wsjrdp::Credentials::Keys).to receive(:current).and_return(other_keys)

        get "/credentials/versions/#{row.id}/edit"
        expect(html).not_to have_css("input[name='credential[secret][smtp_password]']")
        expect_nothing_secret(password)

        patch "/credentials/versions/#{row.id}",
          params: {credential: form_params(comment: "neu", secret: {smtp_password: "made-up-ignored"})}
        expect(row.reload.comment).to eq("neu")
        expect(secret_of(row, "smtp_password")).to eq(password)
      end

      it "revokes a version and takes that back" do
        post "/credentials/versions/#{row.id}/revoke"
        expect(row.reload.revoked_at).to be_within(1.minute).of(Time.current)
        expect(row.state).to eq(:revoked)
        get "/credentials/mail_account/finanzen"
        expect(html.find("#credential-version-#{row.id}")).to have_text("zurückgezogen")

        post "/credentials/versions/#{row.id}/unrevoke"
        expect(row.reload.revoked_at).to be_nil
      end

      it "refuses to change a row of another stage" do
        row.update_columns(stage: "development")
        get "/credentials/versions/#{row.id}/edit"
        expect(response).to redirect_to("/credentials/mail_account/finanzen")
        expect(flash[:alert]).to include("anderen Umgebung")
      end
    end

    describe "re-keying and deleting" do
      it "offers re-keying only where the key is not the active one" do
        row = deposit!
        get "/credentials/mail_account/finanzen"
        expect(html).not_to have_button("Neu verschlüsseln")

        allow(Wsjrdp::Credentials::Keys).to receive(:current).and_return(other_keys)
        get "/credentials/mail_account/finanzen"
        expect(html.find("#credential-version-#{row.id}")).to have_text("nicht mehr der aktive")
        expect(html.find("#credential-version-#{row.id}")).to have_button("Neu verschlüsseln")

        post "/credentials/versions/#{row.id}/rekey"
        expect(flash[:notice]).to eq("Version neu verschlüsselt.")
        expect(row.reload.encryption_key_fingerprint).to eq(other_keys.active.fingerprint)
        expect(secret_of(row, "smtp_password")).to eq(password)
      end

      it "deletes a version of any stage" do
        row = deposit!
        other = deposit!
        other.update_columns(stage: "development")

        delete "/credentials/versions/#{row.id}"
        expect(response).to redirect_to("/credentials/mail_account/finanzen")
        delete "/credentials/versions/#{other.id}"
        expect(WsjrdpCredential.count).to eq(0)
      end
    end

    describe "revealing" do
      it "answers the value, never cached, and adds no trail entry" do
        row = deposit!

        expect do
          post "/credentials/mail_account/finanzen/reveal",
            params: {source: "database", version_id: row.id, field: "smtp_password"}
        end.not_to change(PaperTrail::Version, :count)

        expect(response.parsed_body).to eq("value" => password)
        expect(response.headers["Cache-Control"]).to include("no-store")
      end

      it "reveals an override's value" do
        use_env_override

        post "/credentials/moss_api/default/reveal", params: {source: "variables", position: 1, field: "client_secret"}

        expect(response.parsed_body).to eq("value" => "made-up-env-secret")
      end

      it "refuses a public field, a row of another stage and a row that does not open" do
        row = deposit!
        other = deposit!
        other.update_columns(stage: "development")

        post "/credentials/mail_account/finanzen/reveal",
          params: {source: "database", version_id: row.id, field: "smtp_host"}
        expect(response).to have_http_status(422)
        post "/credentials/mail_account/finanzen/reveal",
          params: {source: "database", version_id: other.id, field: "smtp_password"}
        expect(response.parsed_body).to eq("error" => "Eine Version einer anderen Umgebung lässt sich hier nicht anzeigen.")
        allow(Wsjrdp::Credentials::Keys).to receive(:current)
          .and_return(Wsjrdp::Credentials::Keys.new("test:#{"e" * 64}", stage: "test"))
        post "/credentials/mail_account/finanzen/reveal",
          params: {source: "database", version_id: row.id, field: "smtp_password"}
        expect(response.parsed_body).to eq("error" => "Diese Version lässt sich hier nicht öffnen.")
        expect(response.body).not_to include(password)
      end

      it "is switched off in one place" do
        deposit!
        allow(Wsjrdp::Credentials::Reveal).to receive(:enabled?).and_return(false)

        get "/credentials/mail_account/finanzen"
        expect(html).not_to have_button("Anzeigen")
        post "/credentials/mail_account/finanzen/reveal",
          params: {source: "database", version_id: WsjrdpCredential.last.id, field: "smtp_password"}
        expect(response.parsed_body).to eq("error" => "Anzeigen ist abgeschaltet.")
      end
    end

    describe "further fields" do
      let(:pin) { "made-up-further-pin-2468" }

      def further!(**options)
        deposit!(values: mail_values.merge("tenant" => "made-up-tenant", "pin" => pin),
          secret_further_fields: ["pin"], **options)
      end

      it "keeps a public one plain and seals a secret one by itself" do
        row = further!
        expect(row.public_data["tenant"]).to eq("made-up-tenant")
        expect(row.sealed?("pin")).to be true
        expect(row.plain?("pin")).to be false
        expect(Wsjrdp::Credentials.fetch(:mail_account, "finanzen").secret(:pin)).to eq(pin)
      end

      it "shows them on the card, the sealed one masked and revealable" do
        row = further!
        get "/credentials/mail_account/finanzen"

        card = html.find("#credential-version-#{row.id}")
        expect(card.all("[data-credential-field]").pluck("data-credential-field")).to include("pin", "tenant")
        expect(card.find("[data-credential-field='tenant']")).to have_text("made-up-tenant")
        sealed = card.find("[data-credential-field='pin']")
        expect(sealed).to have_text("••••••••")
        expect(sealed).to have_button("Anzeigen")
        expect(card).not_to have_text("kennt die Art nicht")
        expect_nothing_secret(password, pin)
      end

      it "reveals a sealed one and refuses a public one" do
        row = further!
        post "/credentials/mail_account/finanzen/reveal", params: {source: "database", version_id: row.id, field: "pin"}
        expect(response.parsed_body).to eq("value" => pin)

        post "/credentials/mail_account/finanzen/reveal",
          params: {source: "database", version_id: row.id, field: "tenant"}
        expect(response.parsed_body).to eq("error" => "Dieses Feld ist nicht geheim.")
      end

      it "shows an override's further field plainly, with its variable" do
        use_overrides(variables: Wsjrdp::Credentials::Variables.new(
          {"HITOBITO_CREDENTIAL__TEST__MOSS_API__DEFAULT__CLIENT_ID" => "env-client",
           "HITOBITO_CREDENTIAL__TEST__MOSS_API__DEFAULT__CLIENT_SECRET" => "made-up-env-secret",
           "HITOBITO_CREDENTIAL__TEST__MOSS_API__DEFAULT__TENANT" => "made-up-env-tenant"},
          stage: "test", kinds: kinds
        ))
        get "/credentials/moss_api/default"

        field = html.find("[data-credential-source='variables'] [data-credential-field='tenant']")
        expect(field).to have_text("made-up-env-tenant")
        expect(field.find("[data-credential-variable]")).to have_text("…__TENANT")
        expect(field).not_to have_button("Anzeigen")
        expect_nothing_secret("made-up-env-secret")
      end

      it "deposits rows from the form, a secret one under a filtered parameter" do
        params = {credential: {fields: {client_id: "made-up-client"}, secret: {client_secret: moss_secret},
                               further: {"0" => {name: "tenant", value: "made-up-tenant"},
                                         "1" => {name: "pin", seal: "1", value: ""},
                                         "2" => {name: "", value: ""}},
                               further_secret: {"1" => pin}}}

        expect { post "/credentials/moss_api/kasse/versions", params: params }.to change(WsjrdpCredential, :count).by(1)

        row = WsjrdpCredential.last
        expect(row.public_data["tenant"]).to eq("made-up-tenant")
        expect(secret_of(row, "pin")).to eq(pin)
        expect(row.plain?("pin")).to be false
        filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter(params)
        expect(filtered.to_s).not_to include(pin)
      end

      it "strips the name of a new row, as the live check does" do
        params = {credential: {fields: {client_id: "made-up-client"}, secret: {client_secret: moss_secret},
                               further: {"0" => {name: "  tenant ", value: "made-up-tenant"}}}}

        expect { post "/credentials/moss_api/kasse/versions", params: params }.to change(WsjrdpCredential, :count).by(1)

        expect(WsjrdpCredential.last.public_data).to include("tenant" => "made-up-tenant")
      end

      it "names the problem of each row, saves nothing and gives the typed secret back" do
        rows = {"0" => {name: "Bad-Name", value: "x"}, "1" => {name: "client_id", value: "x"},
                "2" => {name: "expires_at", value: "x"}, "3" => {name: "tenant", value: "a"},
                "4" => {name: "tenant", value: "b"}, "5" => {name: "note", value: ""},
                "6" => {name: "", value: "x"}, "7" => {name: "pin", seal: "1"}}
        post "/credentials/moss_api/kasse/versions",
          params: {credential: {fields: {client_id: "c"}, secret: {client_secret: moss_secret}, further: rows,
                                further_secret: {"7" => pin}, expires_at: "morgen"}}

        expect(response).to have_http_status(422)
        expect(WsjrdpCredential.count).to eq(0)
        expected = {"0" => "aus Kleinbuchstaben", "1" => "schon ein Feld der Art", "2" => "reserviert",
                    "4" => "kommt schon vor", "5" => "Der Wert fehlt", "6" => "Der Name fehlt"}
        expected.each do |index, text|
          expect(html.find("[data-credential-further-row='#{index}']")).to have_text(text)
        end
        expect(html.find("[data-credential-further-row='3']")).not_to have_text("kommt schon vor")
        expect(html.find("input[name='credential[further_secret][7]']")[:value]).to eq(pin)
        expect(html.find("input[name='credential[secret][client_secret]']")[:value]).to eq(moss_secret)
        expect(further_template).not_to include(pin)
      end

      it "prefills the public further fields of the version in use, never a sealed one" do
        further!
        get "/credentials/mail_account/finanzen/versions/new"

        rows = html.all("#credential-further-rows [data-credential-further-row]")
        expect(rows.map { |row| row.find("input[name$='[name]']")[:value] }).to eq(["tenant"])
        expect(rows.first.find("input[name$='[value]']")[:value]).to eq("made-up-tenant")
        expect(further_template)
          .not_to include("made-up")
        expect_nothing_secret(password, pin)
      end

      describe "changing" do
        let!(:row) { further! }

        def further_params(further, further_secret: {})
          {name: "", comment: "", lock: lock_of(row), further: further, further_secret: further_secret}
        end

        it "shows a row per field, the sealed one filled in" do
          get "/credentials/versions/#{row.id}/edit"

          pin_row = html.find("[data-credential-further-row='0']")
          expect(pin_row.find("input[name='credential[further][0][was]']", visible: :all)[:value]).to eq("pin")
          pin_input = pin_row.find("input[name='credential[further_secret][0]']")
          expect(pin_input[:value]).to eq(pin)
          expect(pin_input[:type]).to eq("password")
          expect(pin_row).to have_css("[data-credential-further-state='sealed']")
          tenant_row = html.find("[data-credential-further-row='1']")
          expect(tenant_row.find("input[name='credential[further][1][value]']")[:value]).to eq("made-up-tenant")
          expect(tenant_row).to have_css("[data-credential-further-state='plain']")
          [pin_row, tenant_row].each do |existing|
            expect(existing).not_to have_css("input[name$='[seal]'], input[name$='[name]']", visible: :all)
          end
          expect(further_template).not_to include(pin)
          expect_nothing_secret
        end

        it "keeps a sealed one the request leaves out, changes a public one, adds and removes" do
          patch "/credentials/versions/#{row.id}", params: {credential: further_params(
            {"0" => {was: "pin"}, "1" => {was: "tenant", value: "made-up-other", remove: "1"},
             "2" => {name: "region", value: "eu"}}
          )}

          expect(response).to redirect_to("/credentials/mail_account/finanzen#credential-version-#{row.id}")
          expect(secret_of(row, "pin")).to eq(pin)
          expect(row.reload.public_data).not_to have_key("tenant")
          expect(row.public_data["region"]).to eq("eu")
        end

        it "keeps a sealed one sent as shown and removes one that is emptied" do
          with_versioning do
            expect do
              patch "/credentials/versions/#{row.id}",
                params: {credential: further_params({"0" => {was: "pin"}}, further_secret: {"0" => pin})}
            end.not_to change(PaperTrail::Version, :count)
          end
          expect(secret_of(row, "pin")).to eq(pin)

          patch "/credentials/versions/#{row.id}",
            params: {credential: further_params({"0" => {was: "pin"}}, further_secret: {"0" => ""})}
          expect(response).to redirect_to("/credentials/mail_account/finanzen#credential-version-#{row.id}")
          expect(row.reload.sealed?("pin")).to be false
          expect(row.plain?("pin")).to be false
        end

        it "never seals a public one in place" do
          patch "/credentials/versions/#{row.id}",
            params: {credential: further_params({"1" => {was: "tenant", seal: "1"}}, further_secret: {"1" => "made-up-x"})}

          expect(row.reload.sealed?("tenant")).to be false
          expect(row.public_data["tenant"]).to eq("made-up-tenant")
        end

        it "replaces a sealed one only under the active key, and keeps it sealed" do
          patch "/credentials/versions/#{row.id}",
            params: {credential: further_params({"0" => {was: "pin", seal: ""}}, further_secret: {"0" => "made-up-new"})}
          expect(secret_of(row, "pin")).to eq("made-up-new")
          expect(row.reload.sealed?("pin")).to be true

          allow(Wsjrdp::Credentials::Keys).to receive(:current).and_return(other_keys)
          result = Wsjrdp::Credentials::Change.call(record: row, values: {"pin" => "made-up-third"})
          expect(result.field_errors.map(&:to_s)).to eq(["pin: key_not_active"])
          expect(Wsjrdp::Credentials::Change.call(record: row, values: {"tenant" => "made-up-x"})).to be_saved
        end

        it "names a sealed one in the trail by name only" do
          with_versioning do
            patch "/credentials/versions/#{row.id}", params: {credential: further_params(
              {"0" => {was: "pin"}, "1" => {was: "tenant", value: "made-up-next"}}, further_secret: {"0" => "made-up-new-pin"}
            )}
          end
          get "/credentials/mail_account/finanzen"

          text = html.find("details[data-credential-trail='#{row.id}']").text(:all)
          expect(text).to include("tenant: „made-up-tenant“ → „made-up-next“", "geheimes Feld geändert: pin")
          expect_nothing_secret(password, pin, "made-up-new-pin")
        end
      end
    end

    describe "the trail" do
      def trail_of(row)
        get "/credentials/mail_account/finanzen"
        html.find("details[data-credential-trail='#{row.id}']")
      end

      def versioned(&block)
        with_versioning do
          PaperTrail.request(whodunnit: admin.id.to_s, controller_info: {whodunnit_type: Person.name}, &block)
        end
      end

      it "lists the changes of a version, public values shown, secret fields by name only" do
        row = nil
        versioned do
          row = deposit!
          Wsjrdp::Credentials::Change.call(record: row, name: "Neu", comment: "x" * 100,
            values: {"smtp_password" => "made-up-changed", "smtp_username" => "neu@example.org",
                     "smtp_host" => "smtp.example.org", "imap_port" => nil})
        end
        trail = trail_of(row)
        expect(trail).to have_link(admin.to_s, href: "/people/#{admin.id}", count: 2, visible: :all)
        expect(trail.all("tr[data-credential-trail-event]", visible: :all).pluck("data-credential-trail-event"))
          .to contain_exactly("update", "create")
        text = trail.text(:all)
        expect(text).to include("Felder: mail_from = finanzen@example.org, smtp_host = mail.example.org, " \
          "smtp_port = 587, smtp_security = starttls, imap_port = 993 · geheimes Feld gesetzt: smtp_password")
        expect(text).to match(/angelegt · Schlüssel: \S+ · Felder:/)
        expect(text).to include("Anzeigename: – → „Neu“")
        expect(text).to include("smtp_host: „mail.example.org“ → „smtp.example.org“")
        expect(text).to include("smtp_username hinzugefügt: „neu@example.org“")
        expect(text).to include("imap_port entfernt (war „993“)")
        expect(text).to include("geheimes Feld geändert: smtp_password")
        expect(text).to include(admin.to_s)
        expect_nothing_secret(password, "made-up-changed")
      end

      it "names a field held sealed or secret in the kind without its value, also in older entries; " \
         "shows a public further field" do
        row = nil
        versioned do
          row = deposit!
          row.update!(public_data: row.public_data.merge("smtp_password" => "made-up-plain-secret",
            "legacy_token" => "made-up-legacy"))
          seal_public!(row, "smtp_host", "made-up-sealed-host")
        end

        text = trail_of(row).text(:all)
        expect(text).to include("geändert · legacy_token hinzugefügt: „made-up-legacy“ · " \
          "Felder geändert (Werte nicht gezeigt): smtp_password")
        expect(text).to include("geändert · Felder geändert (Werte nicht gezeigt): smtp_host · geheimes Feld gesetzt: smtp_host")
        expect(text).to include("Felder: mail_from = finanzen@example.org, smtp_port = 587, smtp_security = starttls, " \
          "imap_port = 993 · Felder (Werte nicht gezeigt): smtp_host")
        expect(text).not_to include("mail.example.org")
        expect_nothing_secret(password, "made-up-plain-secret", "made-up-sealed-host")
      end

      it "escapes the values" do
        row = nil
        versioned { row = deposit!(values: mail_values.merge("smtp_username" => "<b>fett</b>")) }

        get "/credentials/mail_account/finanzen"
        expect(response.body).to include("smtp_username = &lt;b&gt;fett&lt;/b&gt;")
        expect(html.find("details[data-credential-trail='#{row.id}']")).not_to have_css("b", visible: :all)
      end
    end
  end
end
