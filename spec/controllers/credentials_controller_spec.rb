# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The pages decide what is masked, so most examples render them.
describe CredentialsController do
  before_all(setup_fixtures: true) {}

  include_context "credential pages"
  render_views

  let_it_be(:admin, refind: true) do
    people(:admin).tap { |person| Group::Root::Admin.create!(person: person, group: groups(:root)) }
  end

  def reveal!(account = mail_account, **params) = post(:reveal, params: account.merge(source: "database", **params))

  it "refuses every action to who is no admin" do
    row = deposit!
    sign_in(people(:cmt_leader))
    requests = [[:get, :index, {}], [:get, :new, {}], [:get, :show, mail_account],
      [:post, :reveal, mail_account.merge(version_id: row.id, field: "smtp_password")],
      [:post, :reload_local_file, {}], [:post, :test_connection, moss_account]]

    requests.each do |verb, action, params|
      expect { public_send(verb, action, params: params) }.to raise_error(CanCan::AccessDenied), action.to_s
    end
  end

  describe "the list" do
    it "is in the menu, groups the accounts by kind and names the title field of the version in use" do
      deposit!
      deposit!(account_key: "alt", values: mail_values.merge("mail_from" => "alt@example.org"),
        expires_at: 1.day.ago, valid_from: 2.days.ago)
      moss!

      get :index

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

    it "masks a public field lying sealed" do
      row = seal_public!(deposit!, "mail_from", "made-up-sealed@example.org")
      seal_public!(row, "smtp_host", "made-up-sealed-host")

      get :index

      expect(html.find("tr[data-credential-account='finanzen']")).to have_text("aktiv")
      expect_nothing_secret("made-up-sealed@example.org", "made-up-sealed-host")
    end

    it "marks an override in use and counts the rows of other stages" do
      deposit!(kind: "moss_api", account_key: "default",
        values: {"client_id" => "db-client", "client_secret" => moss_secret})
      deposit!.update_columns(stage: "development")
      use_env_override

      get :index

      moss = html.find("tr[data-credential-account='default']")
      expect(moss).to have_text("ENV")
      expect(moss).to have_text("überschreibt Datenbank: 1 Version")
      expect(moss).to have_text("env-client")
      expect(html.find("tr[data-credential-account='finanzen']")).to have_text("development: 1")
      expect_nothing_secret(password, moss_secret, "made-up-env-secret")
    end

    it "shows the active key with its fingerprint, stage and source, and no reload without the local file" do
      get :index

      active = Wsjrdp::Credentials::Keys.current.active.fingerprint
      card = html.find("[data-credential-key='#{active}']")
      expect(card).to have_text("Fingerabdruck #{active} aktiv", normalize_ws: true)
      expect(card).to have_text("Umgebung test", normalize_ws: true)
      expect(card.find("[data-credential-key-source]"))
        .to have_text("Quelle Datei config/settings/test.yml (Eintrag credentials.keys_default)", normalize_ws: true)
      expect(html).not_to have_css("#credentials-reload")
    end

    it "shows an accepted key beside the active one, and the variable as the source" do
      use_keys(other_keys)

      get :index

      expect(html.all("[data-credential-key]").pluck("data-credential-key"))
        .to match_array(other_keys.keys.map(&:fingerprint))
      expect(html.find("[data-credential-key='#{other_keys.keys.last.fingerprint}']")).to have_text("akzeptiert")
      expect(html.find("[data-credential-key='#{other_keys.active.fingerprint}'] [data-credential-key-source]"))
        .to have_text("Quelle Umgebungsvariable HITOBITO_CREDENTIAL_KEYS", normalize_ws: true)
    end

    it "lists the keys of other stages by fingerprint only" do
      secrets = {staging: "d" * 64, own: "e" * 64, long: "f" * 64}
      use_keys(Wsjrdp::Credentials::Keys.new(
        "staging:#{secrets[:staging]},test:#{secrets[:own]},#{"s" * 40}:#{secrets[:long]}",
        stage: "test", label: "laptop-a"
      ))

      get :index

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
      use_keys(Wsjrdp::Credentials::Keys.new("staging:#{"d" * 64}", stage: "test"))

      get :index

      expect(html.find("#credentials-keys")).to have_text("Diese Umgebung hat keinen Schlüssel.")
      expect(html.all("[data-credential-key]").pluck("data-credential-key-role")).to eq(%w[other_stage])
      expect_nothing_secret("d" * 64)
    end

    it "says when the instance has no key and when the local file was skipped" do
      file = Wsjrdp::Credentials::LocalFile.new("stage: staging\n", stage: "test", kinds: kinds)
      expect(file.status).to eq(Wsjrdp::Credentials::LocalFile::OTHER_STAGE)
      use_overrides(file: file)
      use_keys(Wsjrdp::Credentials::Keys.new(nil, stage: "test"))

      get :index

      expect(html).to have_css("#credentials-no-key")
      expect(html.find("#credentials-file-skipped")).to have_text("„staging“")
      expect(html.find("#credentials-keys")).to have_text("Diese Umgebung hat keinen Schlüssel.")
    end

    it "offers the reload when the local file is there" do
      use_overrides(file: Wsjrdp::Credentials::LocalFile.new("stage: test\n", stage: "test", kinds: kinds))

      get :index

      expect(html).to have_css("#credentials-reload")
    end
  end

  describe "reading the local file again" do
    it "reads it again" do
      expect(Wsjrdp::Credentials::Overrides).to receive(:reload!)

      post :reload_local_file

      expect(response).to redirect_to("/credentials")
      expect(flash[:notice]).to be_present
    end

    it "keeps the old state and says why" do
      allow(Wsjrdp::Credentials::Overrides).to receive(:reload!)
        .and_raise(Wsjrdp::Credentials::ConfigurationError, "config/wsjrdp_credentials.local.yml: line 2: broken")

      post :reload_local_file

      expect(response).to redirect_to("/credentials")
      expect(flash[:alert]).to include("line 2: broken")
    end
  end

  describe "a new account" do
    it "refuses an account key that is no name, warning of one that looks like a token" do
      get :new, params: {kind: "moss_api", account_key: "550E8400-E29B-41D4-A716-446655440000 x"}

      expect(response).to have_http_status(422)
      expect(html).to have_text("Die Bezeichnung ist ungültig.")
      expect(html).to have_text("Sieht aus wie ein Schlüssel oder Token.")
    end

    it "goes on to the form of the first version, with the display name" do
      get :new, params: {kind: "moss_api", account_key: "kasse", name: "Key Mai"}

      expect(response).to redirect_to("/credentials/moss_api/kasse/versions/new?name=Key+Mai")
    end

    it "refuses a display name that is no text, keeping the typed key" do
      get :new, params: {kind: "moss_api", account_key: "kasse", name: "Key\u0000Mai"}

      expect(response).to have_http_status(422)
      expect(html).to have_text("Der Anzeigename ist kein gültiger Text.")
      expect(html.find("input[name='account_key']")[:value]).to eq("kasse")
    end

    it "takes a wider account key, folded" do
      get :new, params: {kind: "mail_account", account_key: "Foo@WorldScoutJamboree.DE"}

      expect(response).to redirect_to("/credentials/mail_account/foo@worldscoutjamboree.de/versions/new")
    end

    it "names what is wrong with an account key" do
      get :new, params: {kind: "mail_account", account_key: "a/b..c-"}

      expect(response).to have_http_status(422)
      expect(html).to have_text("Nicht erlaubt: „/“")
      expect(html).to have_text("Zwei der Zeichen _ @ , . + - stehen hintereinander.")
      expect(html).to have_text("Am Anfang oder am Ende steht eines der Zeichen _ @ , . + -.")
    end

    it "hands the page's script the names of the variables of the accounts there are" do
      deposit!(account_key: "foo@worldscoutjamboree.de")

      get :new

      config = html.find("#credentials-new-js", visible: :all)
      expect(JSON.parse(config["data-parts"])).to eq(
        "mail_account" => {"FOO_WORLDSCOUTJAMBOREE_DE" => ["foo@worldscoutjamboree.de"]}
      )
      expect(config["data-prefix"]).to eq("HITOBITO_CREDENTIAL__TEST")
      expect(config["data-length"]).to eq("64")
    end
  end

  describe "the account's page" do
    it "shows every version with its state, secret fields masked, no re-keying under the active key " \
       "and no connection test for a kind other than Moss" do
      older = deposit!(name: "Postfach alt", comment: "vom Mail-Team")
      planned = deposit!(name: "Postfach geplant", valid_from: 10.days.from_now,
        values: mail_values.merge("smtp_password" => "made-up-planned-password"))
      newest = deposit!(name: "Postfach neu", values: mail_values.merge("smtp_password" => "made-up-new-password"),
        author: admin)

      get :show, params: mail_account

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
      expect(html).not_to have_button("Neu verschlüsseln")
      expect(html).not_to have_button("Verbindung testen")
      expect_nothing_secret(password, "made-up-planned-password", "made-up-new-password")
    end

    it "masks a public field lying sealed" do
      seal_public!(deposit!, "smtp_host", "made-up-sealed-host")

      get :show, params: mail_account

      expect(html.find("[data-credential-field='smtp_host']")).to have_text("••••••••")
      expect_nothing_secret("made-up-sealed-host")
    end

    it "escapes the display name" do
      deposit!(name: "<b>Postfach</b>")

      get :show, params: mail_account

      expect(response.body).to include("&lt;b&gt;Postfach&lt;/b&gt;")
      expect(response.body).not_to include("<b>Postfach</b>")
    end

    it "names what is wrong with a row and lists the rows of other stages, deletable only" do
      wrong = deposit!
      wrong.update_columns(public_data: wrong.public_data.merge("smtp_password" => "made-up-plain"))
      other = deposit!(account_key: "finanzen")
      other.update_columns(stage: "development")

      get :show, params: mail_account

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

      get :show, params: moss_account

      env = html.find("[data-credential-source='variables']")
      expect(env).to have_css("[data-credential-in-use]")
      expect(env.find("[data-credential-chip='source']")).to have_text("ENV")
      expect(env.find("[data-credential-source-row]"))
        .to have_text("Quelle Umgebungsvariablen HITOBITO_CREDENTIAL__TEST__MOSS_API__DEFAULT__…", normalize_ws: true)
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
      use_overrides(file: Wsjrdp::Credentials::LocalFile.new(<<~YAML, stage: "test", kinds: kinds))
        stage: test
        credentials:
          moss_api:
            default:
              versions:
                - vars: {client_id: file-client, client_secret: made-up-file-secret}
      YAML

      get :show, params: moss_account

      expect(html.find("[data-credential-source='file'] [data-credential-chip='source']")).to have_text("YAML")
      expect(html.find("[data-credential-source='file'] [data-credential-source-row]"))
        .to have_text("Quelle Lokale Datei config/wsjrdp_credentials.local.yml", normalize_ws: true)
      expect(html).not_to have_css("[data-credential-variable]")
      expect_nothing_secret("made-up-file-secret")
    end

    it "shows a version whose kind left the registry, every field masked" do
      row = deposit!
      row.update_columns(kind: "old_mail")

      get :show, params: {kind: "old_mail", account_key: "finanzen"}

      card = html.find("#credential-version-#{row.id}")
      expect(card).to have_text("Art unbekannt")
      expect(card.find("[data-credential-field='smtp_host']")).to have_text("••••••••")
      expect(html).not_to have_link("Neue Version hinterlegen")
      expect_nothing_secret(password)
    end

    it "shows a revoked version as such" do
      row = deposit!
      Wsjrdp::Credentials::Change.call(record: row, revoked_at: Time.current)

      get :show, params: mail_account

      expect(html.find("#credential-version-#{row.id}")).to have_text("zurückgezogen")
    end

    it "offers re-keying where the key is not the active one" do
      row = deposit!
      use_keys(other_keys)

      get :show, params: mail_account

      expect(html.find("#credential-version-#{row.id}")).to have_text("nicht mehr der aktive")
      expect(html.find("#credential-version-#{row.id}")).to have_button("Neu verschlüsseln")
    end

    it "is not found for an unknown kind no source names, or an account key that is no name" do
      expect { get :show, params: {kind: "nope", account_key: "default"} }.to raise_error(ActiveRecord::RecordNotFound)
      expect { get :show, params: {kind: "moss_api", account_key: "Not A Name"} }
        .to raise_error(ActiveRecord::RecordNotFound)
    end

    it "redirects an account key written in another case" do
      get :show, params: {kind: "moss_api", account_key: "Kasse"}

      expect(response).to redirect_to("/credentials/moss_api/kasse")
    end
  end

  describe "further fields" do
    let(:pin) { "made-up-further-pin-2468" }
    let!(:row) do
      deposit!(values: mail_values.merge("tenant" => "made-up-tenant", "pin" => pin), secret_further_fields: ["pin"])
    end

    it "shows them on the card, the sealed one masked and revealable" do
      get :show, params: mail_account

      card = html.find("#credential-version-#{row.id}")
      expect(card.all("[data-credential-field]").pluck("data-credential-field")).to include("pin", "tenant")
      expect(card.find("[data-credential-field='tenant']")).to have_text("made-up-tenant")
      sealed = card.find("[data-credential-field='pin']")
      expect(sealed).to have_text("••••••••")
      expect(sealed).to have_button("Anzeigen")
      expect(card).not_to have_text("kennt die Art nicht")
      expect_nothing_secret(password, pin)
    end

    it "reveals a sealed one" do
      reveal!(version_id: row.id, field: "pin")

      expect(response.parsed_body).to eq("value" => pin)
    end

    it "refuses to reveal a public one" do
      reveal!(version_id: row.id, field: "tenant")

      expect(response.parsed_body).to eq("error" => "Dieses Feld ist nicht geheim.")
    end

    it "shows an override's further field plainly, with its variable" do
      use_env_override("HITOBITO_CREDENTIAL__TEST__MOSS_API__DEFAULT__TENANT" => "made-up-env-tenant")

      get :show, params: moss_account

      field = html.find("[data-credential-source='variables'] [data-credential-field='tenant']")
      expect(field).to have_text("made-up-env-tenant")
      expect(field.find("[data-credential-variable]")).to have_text("…__TENANT")
      expect(field).not_to have_button("Anzeigen")
      expect_nothing_secret("made-up-env-secret")
    end
  end

  describe "the trail" do
    def versioned(&block)
      with_versioning do
        PaperTrail.request(whodunnit: admin.id.to_s, controller_info: {whodunnit_type: Person.name}, &block)
      end
    end

    def trail_of(row)
      get :show, params: mail_account
      html.find("details[data-credential-trail='#{row.id}']")
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

    it "names a sealed further field by name only" do
      pin = "made-up-further-pin-2468"
      row = nil
      versioned do
        row = deposit!(values: mail_values.merge("tenant" => "made-up-tenant", "pin" => pin),
          secret_further_fields: ["pin"])
        Wsjrdp::Credentials::Change.call(record: row, values: {"pin" => "made-up-new-pin", "tenant" => "made-up-next"})
      end

      text = trail_of(row).text(:all)

      expect(text).to include("tenant: „made-up-tenant“ → „made-up-next“", "geheimes Feld geändert: pin")
      expect_nothing_secret(password, pin, "made-up-new-pin")
    end

    it "escapes the values" do
      row = nil
      versioned { row = deposit!(values: mail_values.merge("smtp_username" => "<b>fett</b>")) }

      trail = trail_of(row)

      expect(response.body).to include("smtp_username = &lt;b&gt;fett&lt;/b&gt;")
      expect(trail).not_to have_css("b", visible: :all)
    end
  end

  describe "revealing" do
    it "answers the value, never cached, and adds no trail entry" do
      row = deposit!

      expect { reveal!(version_id: row.id, field: "smtp_password") }.not_to change(PaperTrail::Version, :count)

      expect(response.parsed_body).to eq("value" => password)
      expect(response.headers["Cache-Control"]).to include("no-store")
    end

    it "reveals an override's value" do
      use_env_override

      post :reveal, params: moss_account.merge(source: "variables", position: 1, field: "client_secret")

      expect(response.parsed_body).to eq("value" => "made-up-env-secret")
    end

    it "refuses a public field" do
      row = deposit!

      reveal!(version_id: row.id, field: "smtp_host")

      expect(response).to have_http_status(422)
    end

    it "refuses a row of another stage" do
      other = deposit!
      other.update_columns(stage: "development")

      reveal!(version_id: other.id, field: "smtp_password")

      expect(response.parsed_body).to eq("error" => "Eine Version einer anderen Umgebung lässt sich hier nicht anzeigen.")
    end

    it "refuses a row that does not open" do
      row = deposit!
      use_keys(Wsjrdp::Credentials::Keys.new("test:#{"e" * 64}", stage: "test"))

      reveal!(version_id: row.id, field: "smtp_password")

      expect(response.parsed_body).to eq("error" => "Diese Version lässt sich hier nicht öffnen.")
    end

    context "when switched off" do
      before { allow(Wsjrdp::Credentials::Reveal).to receive(:enabled?).and_return(false) }

      it "offers no reveal" do
        deposit!

        get :show, params: mail_account

        expect(html).not_to have_button("Anzeigen")
      end

      it "refuses it" do
        row = deposit!

        reveal!(version_id: row.id, field: "smtp_password")

        expect(response.parsed_body).to eq("error" => "Anzeigen ist abgeschaltet.")
      end
    end
  end

  # Moss is never called: every request is stubbed (WebMock).
  describe "testing a Moss connection" do
    let(:moss_url) { "https://moss.example.org" }
    let(:access_token) { "made-up-access-token-0815" }

    def moss_row!(base_url: moss_url, **options)
      deposit!(kind: "moss_api", account_key: "default", values: {"base_url" => base_url,
                                                                  "client_id" => "kid_made-up", "client_secret" => moss_secret}, **options)
    end

    def stub_moss(base_url: moss_url, token_status: 200)
      stub_request(:post, "#{base_url}/oauth2/token").to_return(status: token_status,
        body: ((token_status == 200) ? {access_token: access_token, expires_in: 3600, scope: "read"} : {error: "invalid_client"}).to_json)
      stub_request(:get, "#{base_url}/v1/users?page_size=1").to_return(status: 200,
        body: {data: [{id: "u-1", email: "made-up@example.org"}], meta: {tracingId: "t-1"}}.to_json)
    end

    def test!(row, **params)
      post :test_connection, params: moss_account.merge(source: "database", version_id: row.id, **params)
    end

    def log_entries = HitobitoLogEntry.where(category: "credentials").order(:id)

    it "offers the test on active and planned Moss versions only" do
      active = moss_row!
      planned = moss_row!(valid_from: 2.days.from_now)
      expired = moss_row!(valid_from: 3.days.ago, expires_at: 1.day.ago)

      get :show, params: moss_account

      [active, planned].each do |row|
        expect(html.find("#credential-version-#{row.id}")).to have_button("Verbindung testen")
      end
      expect(html.find("#credential-version-#{expired.id}")).not_to have_button("Verbindung testen")
    end

    it "tests a version, keeps the outcome without touching updated_at, and shows no secret" do
      row = moss_row!
      stub_moss
      updated_at = row.reload.updated_at

      expect { test!(row) }.not_to change(PaperTrail::Version, :count)

      expect(response.headers["Cache-Control"]).to include("no-store")
      expect(response.parsed_body["ok"]).to be(true)
      history = Capybara.string(response.parsed_body["history"])
      expect(history.find("[data-credential-connection-history]", visible: :all).text(:all))
        .to include("Verbindungstests (1)")
      expect(row.reload.last_success_at).to be_present
      expect(row.updated_at).to eq(updated_at)
      expect_nothing_secret(moss_secret, access_token)
    end

    it "writes a test into the Hitobito log, without a value or personal data" do
      row = moss_row!
      stub_moss

      test!(row)

      entry = log_entries.sole
      expect(entry).to have_attributes(level: "info", subject: row)
      payload = entry.payload
      expect(payload).to include("event" => "moss_connection_test", "payload_version" => 1, "person_id" => admin.id,
        "account" => {"kind" => "moss_api", "account_key" => "default", "source" => "database",
                      "version_id" => row.id, "position" => nil})
      expect(payload["outcome"]).to include("ok" => true, "host" => "moss.example.org")
      expect(payload["requests"].pluck("step", "method", "status")).to eq([["token", "POST", 200], ["read", "GET", 200]])
      expect(payload["requests"].first.dig("response", "body", "access_token")).to eq("[entfernt]")
      expect(payload["requests"].last.dig("response", "body", "data")).to eq(["u-1"])
      [moss_secret, access_token, "made-up@example.org"].each { |text| expect(payload.to_json).not_to include(text) }
    end

    it "reports, keeps and logs a failure, the log entries of the version newest first" do
      row = moss_row!
      stub_moss
      test!(row)
      stub_moss(token_status: 401)

      test!(row)

      expect(response.parsed_body["ok"]).to be(false)
      expect(row.reload.last_failure_message).to eq("invalid_client")
      older, entry = log_entries.to_a
      expect(entry).to have_attributes(level: "warn", subject: row)
      expect(entry.message).to eq("Moss-Verbindung getestet: moss_api/default – fehlgeschlagen beim Holen " \
        "des Tokens: invalid_client")
      expect(entry.payload.to_json).not_to include(moss_secret)
      version = Wsjrdp::Credentials::Overview.new.account("moss_api", "default").versions.find { |v| v.id == row.id }
      expect(Wsjrdp::Credentials::MossConnectionTest.log_entries("moss_api", "default", version)).to eq([entry, older])
    end

    it "tests an override and logs it by its payload" do
      use_env_override
      stub_moss(base_url: "https://public-api.getmoss.com")

      post :test_connection, params: moss_account.merge(source: "variables", position: 1)

      expect(response.parsed_body["ok"]).to be(true)
      expect_nothing_secret("made-up-env-secret", access_token)
      entry = log_entries.sole
      expect(entry).to have_attributes(subject: nil, level: "info")
      version = Wsjrdp::Credentials::Overview.new.account("moss_api", "default").versions
        .find { |v| v.source == "variables" }
      expect(Wsjrdp::Credentials::MossConnectionTest.log_entries("moss_api", "default", version)).to eq([entry])
    end

    describe "over plain http" do
      let!(:row) { moss_row!(base_url: "http://moss.example.org") }

      before { stub_moss(base_url: "http://moss.example.org") }

      it "asks for a confirmation on the card" do
        get :show, params: moss_account

        expect(html.find("#credential-version-#{row.id} [data-credential-connection]")["data-confirm-insecure"])
          .to include("moss.example.org")
      end

      it "refuses the test unconfirmed" do
        test!(row)

        expect(response).to have_http_status(422)
        expect(response.parsed_body).to eq("error" => "Der Test über http braucht eine Bestätigung.")
        expect(a_request(:post, "http://moss.example.org/oauth2/token")).not_to have_been_made
      end

      it "tests once confirmed" do
        test!(row, confirmed: "1")

        expect(a_request(:post, "http://moss.example.org/oauth2/token")).to have_been_made
      end
    end

    it "refuses a version it does not offer the test for" do
      row = moss_row!(valid_from: 3.days.ago, expires_at: 1.day.ago)

      test!(row)

      expect(response).to have_http_status(422)
      expect(response.parsed_body).to eq("error" => "Diese Version lässt sich nicht testen.")
    end
  end
end
