# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The forms decide which value they hand back, so most examples render them.
describe CredentialVersionsController do
  include_context "credential pages"
  render_views
  before_all(setup_fixtures: true) {}

  let_it_be(:admin) { people(:admin).tap { |person| Group::Root::Admin.create!(person: person, group: groups(:root)) } }
  let(:kasse) { {kind: "moss_api", account_key: "kasse"} }

  def create!(account = kasse, **credential) = post(:create, params: account.merge(credential: credential))

  def update!(row, **credential) = patch(:update, params: {id: row.id, credential: credential})

  def problem_codes = (assigns(:errors) + assigns(:field_errors)).map(&:code)

  def filtered(params) = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter(params)

  it "refuses every action to who is no admin" do
    row = deposit!
    sign_in(people(:cmt_leader))
    requests = [[:get, :new, mail_account], [:post, :create, mail_account], [:get, :edit, {id: row.id}],
      [:patch, :update, {id: row.id}], [:delete, :destroy, {id: row.id}], [:post, :revoke, {id: row.id}],
      [:post, :unrevoke, {id: row.id}], [:post, :rekey, {id: row.id}]]

    requests.each do |verb, action, params|
      expect { public_send(verb, action, params: params) }.to raise_error(CanCan::AccessDenied), action.to_s
    end
    expect(row.reload).to be_persisted
  end

  describe "a public field lying sealed" do
    let(:row) { seal_public!(deposit!, "smtp_host", "made-up-sealed-host") }

    it "is left empty in the prefill of a new version" do
      row

      get :new, params: mail_account

      expect(html.find("input[name='credential[fields][smtp_host]']")[:value].to_s).to eq("")
      expect_nothing_secret("made-up-sealed-host")
    end

    it "is left empty in the edit form" do
      get :edit, params: {id: row.id}

      expect(html.find("input[name='credential[fields][smtp_host]']")[:value].to_s).to eq("")
      expect_nothing_secret("made-up-sealed-host")
    end

    it "keeps its value when the edit form is sent untouched" do
      # What the form sends: every field, the encrypted one empty as
      # shown, the secret ones as filled in.
      fields = {mail_from: "finanzen@example.org", smtp_host: "", smtp_port: "587", smtp_security: "starttls",
                imap_port: "993", smtp_username: "", imap_host: "", imap_username: "", sent_folder: ""}
      update!(row, name: "Neu", comment: "", fields: fields, secret: {smtp_password: password, imap_password: ""},
        valid_from: "", expires_at: "", lock: lock_of(row))

      expect(row.reload.name).to eq("Neu")
      expect(secret_of(row, "smtp_host")).to eq("made-up-sealed-host")
      expect(row.sealed?("smtp_host")).to be true
      expect(secret_of(row, "smtp_password")).to eq(password)
    end
  end

  describe "a new version" do
    it "takes the display name of the first version from the query and names no fallback without a version" do
      get :new, params: kasse.merge(name: "Key Mai")

      expect(html.find("input[name='credential[name]']")[:value]).to eq("Key Mai")
      expect(html).not_to have_text("Die bisherige Version bleibt")
    end

    it "escapes the display name" do
      deposit!(name: "<b>Postfach</b>")

      get :new, params: mail_account

      expect(response.body).to include("&lt;b&gt;Postfach&lt;/b&gt;")
      expect(response.body).not_to include("<b>Postfach</b>")
    end

    it "deposits a version from the form, the secret under a filtered parameter" do
      credential = {name: "Key Mai", comment: "für die Kasse", fields: {client_id: "made-up-client"},
                    secret: {client_secret: moss_secret}, valid_from: "2027-01-10T08:00",
                    valid_from_zone: "app", expires_at: "2027-07-01T00:00", expires_at_zone: "utc"}

      expect { create!(**credential) }.to change(WsjrdpCredential, :count).by(1)

      row = WsjrdpCredential.last
      expect(response).to redirect_to("/credentials/moss_api/kasse#credential-version-#{row.id}")
      expect(row).to have_attributes(name: "Key Mai", comment: "für die Kasse", author: admin,
        valid_from: Time.utc(2027, 1, 10, 7), expires_at: Time.utc(2027, 7, 1))
      expect(secret_of(row, "client_secret")).to eq(moss_secret)
      expect(row.public_data).to include("client_id" => "made-up-client", "base_url" => "https://public-api.getmoss.com")
      expect(flash.to_h.values.join).not_to include(moss_secret)
      expect(filtered(credential: credential).to_s).not_to include(moss_secret)
    end

    it "names the errors, gives the typed name back, and gives the typed secret back" do
      create!(name: "Kasse Juni", fields: {client_id: ""}, secret: {client_secret: moss_secret},
        valid_from: "2027-02-01T00:00", expires_at: "2027-01-01T00:00", expires_at_zone: "utc")

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

    it "prefills the public fields of the version in use but its title field, no secret" do
      moss!

      get :new, params: moss_account

      expect(html.find("input[name='credential[fields][base_url]']")[:value]).to eq("https://public-api.getmoss.com")
      expect(html.find("input[name='credential[fields][scope]']")[:value]).to eq("read")
      expect(html.find("input[name='credential[fields][client_id]']")[:value].to_s).to eq("")
      expect(html.find("input[name='credential[secret][client_secret]']")[:value]).to be_blank
      expect(html).to have_text("Die bisherige Version bleibt")
      expect_nothing_secret(moss_secret)
    end

    it "names no fallback without a usable version of this stage" do
      deposit!(expires_at: 1.day.ago, valid_from: 2.days.ago)
      deposit!.update_columns(stage: "development")

      get :new, params: mail_account

      expect(html).not_to have_text("Die bisherige Version bleibt")
    end

    it "names no fallback but the override where one is in use" do
      moss!
      use_env_override

      get :new, params: moss_account

      expect(html).not_to have_text("Die bisherige Version bleibt")
      expect(html.find("#credential-form-overridden")).to have_text("Überschrieben durch ENV")
    end

    it "warns of a url that is not https in production, and saves" do
      use_keys(Wsjrdp::Credentials::Keys.new("production:#{"d" * 64}", stage: "production"))

      create!({kind: "api_key", account_key: "mailcow"},
        fields: {base_url: "http://mailcow.example.org"}, secret: {api_key: "made-up-api-key"})

      expect(WsjrdpCredential.last).to have_attributes(stage: "production")
      expect(flash[:warning]).to eq("base_url: ist nicht https.")
      expect(response.body).not_to include("made-up-api-key")
    end

    context "refused, without the form" do
      render_views false

      it "refuses a time that is none" do
        create!(fields: {client_id: "c"}, secret: {client_secret: moss_secret}, valid_from: "morgen")

        expect(response).to have_http_status(422)
        expect(problem_codes).to include(:not_an_instant)
      end
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
      get :edit, params: {id: row.id}

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
        update!(row, **form_params(name: "Postfach Finanzen", fields: {smtp_host: "smtp.example.org"},
          secret: {smtp_password: password, imap_password: ""}))
      end

      expect(response).to redirect_to("/credentials/mail_account/finanzen#credential-version-#{row.id}")
      expect(row.reload).to have_attributes(name: "Postfach Finanzen", expires_at: Time.utc(2027, 6, 1, 12, 0, 30))
      expect(row.public_data["smtp_host"]).to eq("smtp.example.org")
      expect(secret_of(row, "smtp_password")).to eq(password)
      expect(row.sealed?("imap_password")).to be false
      expect(PaperTrail::Version.where(item: row).last.changeset.keys).to contain_exactly("name", "public_data")
    end

    it "makes no change of a form sent as shown" do
      with_versioning do
        expect { update!(row, **form_params(secret: {smtp_password: password, imap_password: ""})) }
          .not_to change(PaperTrail::Version, :count)
      end
      expect(row.reload.updated_at).to eq(row.created_at)
    end

    it "leaves a field and an instant the request leaves out untouched" do
      update!(row, comment: "neu", fields: {smtp_host: "smtp.example.org"}, lock: lock_of(row))

      expect(row.reload).to have_attributes(comment: "neu", name: "Postfach", expires_at: Time.utc(2027, 6, 1, 12, 0, 30))
      expect(row.public_data).to include("smtp_host" => "smtp.example.org", "mail_from" => "finanzen@example.org",
        "smtp_port" => 587, "imap_port" => 993)
      expect(secret_of(row, "smtp_password")).to eq(password)
    end

    it "offers an enum field as text with its values as suggestions" do
      row.update!(public_data: row.public_data.merge("smtp_security" => "ssl"))

      get :edit, params: {id: row.id}

      input = html.find("input[name='credential[fields][smtp_security]']")
      expect(input[:value]).to eq("ssl")
      expect(html.find("datalist##{input[:list]}", visible: :all).all("option", visible: :all).pluck(:value))
        .to match_array(%w[starttls tls none])
    end

    it "saves a typed value of an enum field as it is" do
      update!(row, **form_params(fields: {smtp_security: "x-tls"}))

      expect(row.reload.public_data["smtp_security"]).to eq("x-tls")
    end

    context "with an enum field without a value" do
      before { row.update!(public_data: row.public_data.except("smtp_security")) }

      it "shows its default" do
        get :edit, params: {id: row.id}

        expect(html.find("input[name='credential[fields][smtp_security]']")[:value]).to eq("starttls")
      end

      it "does not write it when left alone" do
        update!(row, **form_params(comment: "neu"))

        expect(row.reload.comment).to eq("neu")
        expect(row.public_data).not_to have_key("smtp_security")
      end
    end

    context "refused, without the form" do
      render_views false

      it "names the field errors too when an instant does not read" do
        update!(row, **form_params(fields: {smtp_port: "zwei"}, valid_from: "morgen"))

        expect(response).to have_http_status(422)
        expect(problem_codes).to include(:not_an_integer, :not_an_instant)
      end

      it "names the errors of Change" do
        update!(row, **form_params(valid_from: "2027-07-01T10:00", valid_from_zone: "app"))

        expect(response).to have_http_status(422)
        expect(problem_codes).to include(:not_after_valid_from)
        expect(row.reload.valid_from).to be_nil
      end
    end

    it "refuses a form drawn before someone else changed the version, setting nothing back" do
      params = form_params(comment: "von mir")
      Wsjrdp::Credentials::Change.call(record: row, values: {"smtp_host" => "smtp.example.org"})

      update!(row, **params)

      expect(response).to have_http_status(422)
      expect(html).to have_text("Die Version wurde inzwischen geändert.")
      expect(html.find("input[name='credential[lock]']", visible: :all)[:value]).to eq(params[:lock])
      expect(row.reload).to have_attributes(comment: "alt")
      expect(row.public_data["smtp_host"]).to eq("smtp.example.org")
      # The form sent back holds the secret as before.
      expect(html.find("input[name='credential[secret][smtp_password]']")[:value]).to eq(password)
      expect_nothing_secret
    end

    it "replaces a secret that is changed" do
      update!(row, **form_params(secret: {smtp_password: "made-up-other"}))

      expect(secret_of(row, "smtp_password")).to eq("made-up-other")
      expect(flash.to_h.values.join).not_to include("made-up")
    end

    it "removes a secret that is emptied" do
      Wsjrdp::Credentials::Change.call(record: row, values: {"imap_password" => "made-up-imap-password"})

      update!(row, **form_params(secret: {smtp_password: password, imap_password: ""}))

      expect(row.reload.sealed?("imap_password")).to be false
    end

    it "refuses to empty a required secret field, and gives the form back as sent" do
      moss = moss!

      update!(moss, name: "", comment: "", secret: {client_secret: ""}, lock: lock_of(moss))

      expect(response).to have_http_status(422)
      expect(html).to have_text("muss ausgefüllt werden")
      expect(html.find("input[name='credential[secret][client_secret]']")[:value]).to be_blank
      expect(secret_of(moss, "client_secret")).to eq(moss_secret)
    end

    it "reads an instant in the app's zone" do
      update!(row, **form_params(valid_from: "2027-01-01T10:00", valid_from_zone: "app"))

      expect(row.reload.valid_from).to eq(Time.utc(2027, 1, 1, 9))
    end

    context "where the key is not the active one" do
      before { use_keys(other_keys) }

      it "offers no secret field" do
        get :edit, params: {id: row.id}

        expect(html).not_to have_css("input[name='credential[secret][smtp_password]']")
        expect_nothing_secret(password)
      end

      it "changes the rest and keeps the secret" do
        update!(row, **form_params(comment: "neu", secret: {smtp_password: "made-up-ignored"}))

        expect(row.reload.comment).to eq("neu")
        expect(secret_of(row, "smtp_password")).to eq(password)
      end

      it "re-keys a version" do
        post :rekey, params: {id: row.id}

        expect(flash[:notice]).to eq("Version neu verschlüsselt.")
        expect(row.reload.encryption_key_fingerprint).to eq(other_keys.active.fingerprint)
        expect(secret_of(row, "smtp_password")).to eq(password)
      end
    end

    it "lets a version whose kind left the registry be renamed, offering no field" do
      row.update_columns(kind: "old_mail")

      get :edit, params: {id: row.id}

      expect(html).not_to have_css("[data-credential-form-field]")
      expect_nothing_secret(password)
    end

    it "renames a version whose kind left the registry" do
      row.update_columns(kind: "old_mail")

      update!(row, name: "Alt", comment: "", valid_from: "", expires_at: "", lock: lock_of(row))

      expect(row.reload.name).to eq("Alt")
    end

    it "revokes a version" do
      post :revoke, params: {id: row.id}

      expect(row.reload.revoked_at).to be_within(1.minute).of(Time.current)
      expect(row.state).to eq(:revoked)
    end

    it "takes a revocation back" do
      Wsjrdp::Credentials::Change.call(record: row, revoked_at: Time.current)

      post :unrevoke, params: {id: row.id}

      expect(row.reload.revoked_at).to be_nil
    end

    it "refuses to change a row of another stage" do
      row.update_columns(stage: "development")

      get :edit, params: {id: row.id}

      expect(response).to redirect_to("/credentials/mail_account/finanzen")
      expect(flash[:alert]).to include("anderen Umgebung")
    end

    it "deletes a version" do
      delete :destroy, params: {id: row.id}

      expect(response).to redirect_to("/credentials/mail_account/finanzen")
      expect(WsjrdpCredential.exists?(row.id)).to be(false)
    end

    it "deletes a version of another stage" do
      row.update_columns(stage: "development")

      delete :destroy, params: {id: row.id}

      expect(WsjrdpCredential.exists?(row.id)).to be(false)
    end
  end

  describe "further fields" do
    let(:pin) { "made-up-further-pin-2468" }

    def further!
      deposit!(values: mail_values.merge("tenant" => "made-up-tenant", "pin" => pin), secret_further_fields: ["pin"])
    end

    it "deposits rows from the form, a secret one under a filtered parameter" do
      credential = {fields: {client_id: "made-up-client"}, secret: {client_secret: moss_secret},
                    further: {"0" => {name: "tenant", value: "made-up-tenant"},
                              "1" => {name: "pin", seal: "1", value: ""},
                              "2" => {name: "", value: ""}},
                    further_secret: {"1" => pin}}

      expect { create!(**credential) }.to change(WsjrdpCredential, :count).by(1)

      row = WsjrdpCredential.last
      expect(row.public_data["tenant"]).to eq("made-up-tenant")
      expect(secret_of(row, "pin")).to eq(pin)
      expect(row.plain?("pin")).to be false
      expect(filtered(credential: credential).to_s).not_to include(pin)
    end

    it "strips the name of a new row, as the live check does" do
      create!(fields: {client_id: "made-up-client"}, secret: {client_secret: moss_secret},
        further: {"0" => {name: "  tenant ", value: "made-up-tenant"}})

      expect(WsjrdpCredential.last.public_data).to include("tenant" => "made-up-tenant")
    end

    it "names the problem of each row, saves nothing and gives the typed secret back" do
      rows = {"0" => {name: "Bad-Name", value: "x"}, "1" => {name: "client_id", value: "x"},
              "2" => {name: "expires_at", value: "x"}, "3" => {name: "tenant", value: "a"},
              "4" => {name: "tenant", value: "b"}, "5" => {name: "note", value: ""},
              "6" => {name: "", value: "x"}, "7" => {name: "pin", seal: "1"}}

      create!(fields: {client_id: "c"}, secret: {client_secret: moss_secret}, further: rows,
        further_secret: {"7" => pin}, expires_at: "morgen")

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

      get :new, params: mail_account

      rows = html.all("#credential-further-rows [data-credential-further-row]")
      expect(rows.map { |row| row.find("input[name$='[name]']")[:value] }).to eq(["tenant"])
      expect(rows.first.find("input[name$='[value]']")[:value]).to eq("made-up-tenant")
      expect(further_template).not_to include("made-up")
      expect_nothing_secret(password, pin)
    end

    describe "changing" do
      let!(:row) { further! }

      def further_params(further, further_secret: {})
        {name: "", comment: "", lock: lock_of(row), further: further, further_secret: further_secret}
      end

      it "shows a row per field, the sealed one filled in" do
        get :edit, params: {id: row.id}

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
        update!(row, **further_params({"0" => {was: "pin"}, "1" => {was: "tenant", value: "made-up-other", remove: "1"},
                                       "2" => {name: "region", value: "eu"}}))

        expect(response).to redirect_to("/credentials/mail_account/finanzen#credential-version-#{row.id}")
        expect(secret_of(row, "pin")).to eq(pin)
        expect(row.reload.public_data).not_to have_key("tenant")
        expect(row.public_data["region"]).to eq("eu")
      end

      it "keeps a sealed one sent as shown" do
        with_versioning do
          expect { update!(row, **further_params({"0" => {was: "pin"}}, further_secret: {"0" => pin})) }
            .not_to change(PaperTrail::Version, :count)
        end
        expect(secret_of(row, "pin")).to eq(pin)
      end

      it "removes a sealed one that is emptied" do
        update!(row, **further_params({"0" => {was: "pin"}}, further_secret: {"0" => ""}))

        expect(response).to redirect_to("/credentials/mail_account/finanzen#credential-version-#{row.id}")
        expect(row.reload.sealed?("pin")).to be false
        expect(row.plain?("pin")).to be false
      end

      it "never seals a public one in place" do
        update!(row, **further_params({"1" => {was: "tenant", seal: "1"}}, further_secret: {"1" => "made-up-x"}))

        expect(row.reload.sealed?("tenant")).to be false
        expect(row.public_data["tenant"]).to eq("made-up-tenant")
      end

      it "replaces a sealed one and keeps it sealed" do
        update!(row, **further_params({"0" => {was: "pin", seal: ""}}, further_secret: {"0" => "made-up-new"}))

        expect(secret_of(row, "pin")).to eq("made-up-new")
        expect(row.reload.sealed?("pin")).to be true
      end
    end
  end
end
