# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The key of a service token is shown in the answer to the request that makes
# it and nowhere else (Wsjrdp2027::ServiceTokensController): not on the show
# page, not in the list, not in the flash. The stored value is shown wherever
# the token's attributes are, the answers with the key included. How the key
# is stored is chosen on the new page (Wsjrdp2027::ServiceToken::TOKEN_KINDS).
#
# Only an admin manages API keys, and only those of the root group
# (Wsjrdp2027::ServiceTokenAbility).
describe ServiceTokensController do
  render_views

  let(:group) { groups(:root) }
  # The fixture `admin` is a Group::Root::Leader (spec/fixtures/roles.yml); the
  # Admin role gives it the :admin permission.
  let(:admin) { people(:admin).tap { |person| Group::Root::Admin.create!(person: person, group: groups(:root)) } }
  # The core's root user (Person#root?) may everything without being an admin:
  # the one person besides the admins who reaches these pages.
  let(:root_user) { Fabricate(:person, email: Settings.root_email) }

  let(:token_params) do
    {name: "Skript", description: "Abmelde-Formulare", people: true, permission: "layer_read"}
  end

  def made_token = ServiceToken.find_by!(layer: group, name: "Skript")

  def hmac_keys = Wsjrdp2027::ServiceTokenHmacKeys.current

  def dev_value(key)
    Wsjrdp2027::ServiceTokenHmacKeys.new("development:#{"d" * 64}", stage: "development").digests(key).first
  end

  before { sign_in(admin) }

  describe "GET new" do
    it "draws the storage choice and the core's form in what the Turbo answer replaces" do
      get :new, params: {group_id: group.id}
      page = Capybara.string(response.body)

      expect(page).to have_css("#service_token_new form#new_service_token")
      expect(page).to have_css("#service_token_new input[name='service_token[token_kind]'][form='new_service_token']", count: 4)
      expect(page).to have_css("input#service_token_token_kind_hmac[checked]")
      expect(page).to have_css("input[name='service_token[adopted_token]'][form='new_service_token']")
      expect(page).to have_text("HMAC – gilt nur in der test Umgebung")
      expect(page).to have_css("label[for=service_token_token_kind_hmac] code", text: "test")
      expect(page).to have_css("label[for=service_token_adopted_token] [data-required-mark][hidden]", visible: false)
      expect(page).to have_css("input#service_token_adopted_token[disabled]:not([required])")
      expect(page).to have_css("input#service_token_adopted_stage[form='new_service_token'][disabled]:not([required])")
      expect(page).to have_css("input#service_token_adopted_fingerprint[form='new_service_token'][disabled][data-optional]:not([required])")
      expect(page).to have_css("code", text: hmac_keys.active.fingerprint)
      expect(page).not_to have_css("input[name='service_token[hmac_key_name]']")
    end

    it "offers no acting person to the root user, who is not an admin" do
      sign_in(root_user)
      get :new, params: {group_id: group.id}

      expect(Capybara.string(response.body)).not_to have_css("input[name='service_token[acting_person_id]']")
    end
  end

  describe "POST create" do
    it "shows the key on a page of its own, and stores its HMAC by default" do
      post :create, params: {group_id: group.id, service_token: token_params}

      expect(response).to have_http_status(:ok)
      key = Capybara.string(response.body).find("input#service_token_plain_token").value
      expect(key).to match(/\A[A-Za-z0-9_-]{50}\z/)
      expect(made_token.token).to eq(hmac_keys.active.digest(key))
      expect(ServiceToken.find_by_plain_token(key)).to eq(made_token)
      expect(response.body).to include(made_token.token)
      expect(response.body).to include("HMAC-SHA256 des Tokens. Gilt in Test.")
      expect(response.body).to include(hmac_keys.active.fingerprint)
      expect(response.body).to include("Wirkt hier.")
      expect(response.body).to include("Abmelde-Formulare")
    end

    it "stores the HMAC with the active secret, its stage and fingerprint" do
      post :create, params: {group_id: group.id, service_token: token_params.merge(token_kind: "hmac")}
      key = Capybara.string(response.body).find("input#service_token_plain_token").value
      expect(made_token.token).to eq(hmac_keys.active.digest(key))
      expect([made_token.stage, made_token.hmac_secret_key_fingerprint]).to eq(["test", hmac_keys.active.fingerprint])
    end

    it "stores the SHA-256 or the key itself as chosen" do
      post :create, params: {group_id: group.id, service_token: token_params.merge(token_kind: "sha256")}
      key = Capybara.string(response.body).find("input#service_token_plain_token").value
      expect(made_token.token).to eq(ServiceToken.digest_token(key))

      post :create, params: {group_id: group.id, service_token: token_params.merge(name: "Roh", token_kind: "plain")}
      key = Capybara.string(response.body).find("input#service_token_plain_token").value
      expect(ServiceToken.find_by!(name: "Roh").token).to eq(key)
      expect(response.body).to include("ungehasht gespeichert: Jeder")
    end

    it "adopts the stage and the token hash of another stage, with no token to show" do
      value = dev_value("x" * 50)
      post :create, params: {group_id: group.id,
                             service_token: token_params.merge(token_kind: "adopt", adopted_stage: "development",
                               adopted_token: value)}

      expect(response).to redirect_to(group_service_tokens_path(group))
      expect([made_token.token, made_token.stage]).to eq([value, "development"])
    end

    it "adopts the fingerprint of the secret when given" do
      fingerprint = Wsjrdp2027::ServiceTokenHmacKeys.fingerprint_of("d" * 64)
      post :create, params: {group_id: group.id,
                             service_token: token_params.merge(token_kind: "adopt", adopted_stage: "development",
                               adopted_token: dev_value("x" * 50), adopted_fingerprint: fingerprint)}

      expect(response).to redirect_to(group_service_tokens_path(group))
      expect(made_token.hmac_secret_key_fingerprint).to eq(fingerprint)
    end

    it "shows the choice again with the reason when an adopted value is refused" do
      post :create, params: {group_id: group.id,
                             service_token: token_params.merge(token_kind: "adopt", adopted_stage: "development",
                               adopted_token: "nonsense")}

      expect(response).to have_http_status(422)
      page = Capybara.string(response.body)
      expect(page).to have_css("input#service_token_token_kind_adopt[checked]")
      expect(page).to have_css("input[name='service_token[adopted_token]'][value='nonsense'][required]:not([disabled])")
      expect(page).to have_css("input[name='service_token[adopted_stage]'][value='development'][required]:not([disabled])")
      expect(page).to have_text("Token-Hash muss die Form hmac-sha256:")
      expect(page).to have_css("label[for=service_token_adopted_token] [data-required-mark]:not([hidden])")
    end

    it "needs the stage of an adopted token hash" do
      post :create, params: {group_id: group.id,
                             service_token: token_params.merge(token_kind: "adopt", adopted_token: dev_value("x" * 50))}

      expect(response).to have_http_status(422)
      expect(Capybara.string(response.body)).to have_css("input#service_token_adopted_stage.is-invalid")
    end

    it "keeps the key out of the flash for the next page" do
      post :create, params: {group_id: group.id, service_token: token_params}

      expect(flash[:notice]).to be_present
      expect(flash.to_session_value).to be_nil
    end

    it "answers a Turbo request with a stream that puts the key where the form was" do
      post :create, params: {group_id: group.id, service_token: token_params},
        format: :turbo_stream

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('action="replace" target="service_token_new"')
      expect(response.body).to include('action="update" target="flash"')
      # The stream's content stands in <template>, which Capybara does not search.
      key = Nokogiri::HTML(response.body).at_css("input#service_token_plain_token")["value"]
      expect(ServiceToken.find_by_plain_token(key)).to eq(made_token)
      expect(response.body).to include(made_token.token)
    end

    it "shows the form again when the token is not valid" do
      post :create, params: {group_id: group.id, service_token: token_params.merge(name: "")}

      expect(response).to have_http_status(422)
      expect(ServiceToken.where(layer: group).count).to eq(0)
    end
  end

  describe "GET show and index" do
    let!(:token) { ServiceToken.create!(layer: group, **token_params) }

    it "shows the stored HMAC, where it works, and not the key" do
      get :show, params: {group_id: group.id, id: token.id}

      expect(response.body).not_to include(token.plain_token)
      expect(response.body).to include(token.token)
      expect(response.body).to include("Gilt in Test.")
      expect(response.body).to include("Wirkt hier.")
      expect(response.body).to include("Token neu erzeugen")
      expect(response.body).not_to include("Hash übernehmen")
    end

    it "marks a token of another stage and offers no new token for it" do
      token.update_columns(token: dev_value("x" * 50), stage: "development", hmac_secret_key_fingerprint: nil)
      get :show, params: {group_id: group.id, id: token.id}

      expect(response.body).to include("Gilt in Entwicklung.")
      expect(response.body).to include("Wirkt hier nicht, das Token gehört zu einer anderen Umgebung.")
      expect(response.body).not_to include("Token neu erzeugen")
    end

    it "marks a SHA-256 value as working everywhere" do
      token.update_columns(token: ServiceToken.digest_token("k"), stage: nil)
      get :show, params: {group_id: group.id, id: token.id}

      expect(response.body).to include("SHA-256 des Tokens. Gilt in jeder Umgebung.")
      expect(Capybara.string(response.body).all("dt, .labeled-grid > *, label").map(&:text).map(&:strip)).to include("Token-Hash")
      expect(response.body).to include("Neues Token (SHA-256)", "Neues Token (HMAC)")
    end

    it "puts 'API-Key <id>' before the heading, not into the tab title" do
      get :show, params: {group_id: group.id, id: token.id}

      expect(response.body).to include(%(content: "API-Key #{token.id}"))
      expect(Capybara.string(response.body).find("title", visible: false).text(:all)).not_to include("API-Key #{token.id}")
    end

    it "makes every new token by a POST that asks first" do
      token.update_columns(token: ServiceToken.digest_token("k"), stage: nil)
      get :show, params: {group_id: group.id, id: token.id}
      page = Capybara.string(response.body)

      expect(page).to have_css("a[href$='regenerate_token?kind=hmac'][data-method=post][data-confirm]")
      expect(page).to have_css("a[href$='regenerate_token?kind=sha256'][data-method=post][data-confirm]")
    end

    it "marks a key stored as it is and offers a plain, a SHA-256 or an HMAC key" do
      token.update_column(:token, "Legacy0123456789abcdefghijklmnopqrstuvwxyzABCDEFGH")
      get :show, params: {group_id: group.id, id: token.id}

      expect(response.body).to include("Legacy0123456789abcdefghijklmnopqrstuvwxyzABCDEFGH")
      expect(response.body).to include("Das Token selbst, ungehasht gespeichert. Gilt in jeder Umgebung.")
      expect(response.body).not_to include("Token-Hash")
      expect(response.body).to include("Neues Token (ungehasht)", "Neues Token (SHA-256)", "Neues Token (HMAC)")
      expect(response.body).to include("kind=sha256", "kind=hmac")
    end

    # The lines of "Rechte": the element around the Zugriffsbereich, split at
    # its line breaks.
    def rights_lines
      all_rights_lines.grep_v(/\AScopes:/)
    end

    def all_rights_lines
      strong = Nokogiri::HTML(response.body).at_xpath("//strong[contains(., 'rechte auf')]")
      strong.parent.inner_html.split(%r{<br\s*/?>}).map { |line| Nokogiri::HTML.fragment(line).text.squish }
    end

    it "shows a read-only Zugriffsbereich and reading for every kind" do
      token.update!(groups: true, invoices: true)
      get :show, params: {group_id: group.id, id: token.id}

      # TokenAbility lets a token update invoices whatever the Zugriffsbereich.
      expect(rights_lines).to eq(["Leserechte auf dieser Ebene", "Personen Lesen", "Gruppen Lesen",
        "Rechnungen Lesen und Schreiben", "Rollen Lesen"])
    end

    it "shows writing where a Zugriffsbereich with Schreibrechte grants it" do
      token.update!(permission: "layer_and_below_full", groups: true, events: true)
      get :show, params: {group_id: group.id, id: token.id}

      expect(rights_lines).to eq(["Lese- und Schreibrechte auf dieser und darunterliegenden Ebenen",
        "Personen Lesen und Schreiben", "Anlässe Lesen", "Gruppen Lesen", "Rollen Lesen und Schreiben"])
    end

    it "adds Log to the areas with their :log scope, and names the scopes" do
      token.update!(permission: "layer_and_below_full", groups: true, events: true, invoices: true,
        acting_person: admin, wagon_scopes: %w[people:log events:log])
      get :show, params: {group_id: group.id, id: token.id}

      expect(rights_lines).to eq(["Lese- und Schreibrechte auf dieser und darunterliegenden Ebenen",
        "Nur soweit auch #{admin} (ID #{admin.id}) darf",
        "Personen Lesen und Schreiben, Log", "Anlässe Lesen, Log", "Gruppen Lesen",
        "Rechnungen Lesen und Schreiben", "Rollen Lesen und Schreiben"])
      expect(all_rights_lines.last).to eq("Scopes: people, people:log, groups, events, events:log, invoices")
    end

    it "shows the highest finance scope under Rechte" do
      token.update_columns(scopes: %w[people finance:read])
      get :show, params: {group_id: group.id, id: token.id}

      expect(rights_lines.last).to eq("Finanzen Read")
    end

    it "keeps the finance scopes when the root user, who is not an admin, sends others" do
      sign_in(root_user)
      token.update_columns(scopes: %w[people finance:read])
      patch :update, params: {group_id: group.id, id: token.id,
                              service_token: {description: "neu", wagon_scopes: ["", "finance:audit"]}}
      expect(token.reload.description).to eq("neu")
      expect(token.scopes).to eq(%w[people finance:read])
    end

    it "stores the extras only for an API key with an acting person" do
      patch :update, params: {group_id: group.id, id: token.id, service_token: {wagon_scopes: ["", "people:log"]}}
      expect(token.reload.scopes).to eq(%w[people])

      token.update_columns(acting_person_id: admin.id)
      patch :update, params: {group_id: group.id, id: token.id, service_token: {wagon_scopes: ["", "people:log"]}}
      expect(token.reload.scopes).to eq(%w[people people:log])
    end

    it "offers each :log extra behind its area, disabled with a hint without an acting person" do
      get :edit, params: {group_id: group.id, id: token.id}
      page = Capybara.string(response.body)
      people_row = page.find("input#service_token_people").ancestor(".form-check")
      expect(people_row).to have_xpath("following-sibling::div[1][@data-scope-extra='people:log']")
      line = people_row.find(:xpath, "..")
      expect(line[:class]).to include("d-flex")
      expect(line.text.squish).to eq("Personen privilegiert (:log)")
      finance_line = page.find("input#service_token_scope_finance_read").ancestor(".form-check").find(:xpath, "..")
      expect(finance_line.text.squish).to eq("Finanzen Audit Write Manage")
      expect(page).to have_css("input#service_token_scope_people_log[disabled]")
      expect(page).to have_css("input#service_token_scope_finance_audit[disabled]")
      expect(page).to have_css("[data-scope-extras-hint]:not([hidden])", text: "nur mit einer handelnden Person")

      token.update_columns(acting_person_id: admin.id)
      get :edit, params: {group_id: group.id, id: token.id}
      page = Capybara.string(response.body)
      expect(page).to have_css("input#service_token_scope_people_log:not([disabled])")
      expect(page).to have_css("[data-scope-extras-hint][hidden]", visible: false)
    end

    it "offers the finance scopes to the root user, who is not an admin, only to look at" do
      sign_in(root_user)
      token.update_columns(acting_person_id: admin.id)
      get :edit, params: {group_id: group.id, id: token.id}
      page = Capybara.string(response.body)
      expect(page).to have_css("input#service_token_scope_finance_read[disabled]")
      expect(page).to have_css("input#service_token_scope_finance_manage[disabled]")
      expect(page).to have_text("Nur Admins dürfen die Finanz-Scopes")
    end

    it "shows no roles line without both people and groups" do
      get :show, params: {group_id: group.id, id: token.id}

      expect(rights_lines).to eq(["Leserechte auf dieser Ebene", "Personen Lesen"])
    end

    it "lists the token with its digest, not the key" do
      get :index, params: {group_id: group.id}

      expect(response.body).to include("Skript")
      expect(rights_lines).to eq(["Leserechte auf dieser Ebene", "Personen Lesen"])
      expect(response.body).not_to include(token.plain_token)
      expect(response.body).to include(token.token)
    end
  end

  describe "POST regenerate_token" do
    let!(:token) { ServiceToken.create!(layer: group, **token_params) }

    it "replaces the key and shows the new one" do
      old_key = token.plain_token
      post :regenerate_token, params: {group_id: group.id, id: token.id}

      expect(response).to have_http_status(:ok)
      key = Capybara.string(response.body).find("input#service_token_plain_token").value
      expect(ServiceToken.find_by_plain_token(key)).to eq(token)
      expect(ServiceToken.find_by_plain_token(old_key)).to be_nil
      expect(response.body).to include(token.reload.token)
      expect(response.body).to include("Token neu erzeugen")
      expect(flash.to_session_value).to be_nil
    end

    it "is refused to a person who may not change the token" do
      sign_in(people(:yp_a_1))
      expect do
        post :regenerate_token, params: {group_id: group.id, id: token.id}
      end.to raise_error(CanCan::AccessDenied)
      expect(token.reload.token).to eq(hmac_keys.active.digest(token.plain_token))
    end

    it "gives a plain token a SHA-256 key when asked" do
      token.update_column(:token, "Legacy0123456789abcdefghijklmnopqrstuvwxyzABCDEFGH")
      post :regenerate_token, params: {group_id: group.id, id: token.id, kind: "sha256"}

      key = Capybara.string(response.body).find("input#service_token_plain_token").value
      expect(token.reload.token).to eq(ServiceToken.digest_token(key))
    end

    it "gives a plain token an HMAC token with the active secret" do
      token.update_columns(token: "Legacy0123456789abcdefghijklmnopqrstuvwxyzABCDEFGH", stage: nil)
      post :regenerate_token, params: {group_id: group.id, id: token.id, kind: "hmac"}

      key = Capybara.string(response.body).find("input#service_token_plain_token").value
      expect(token.reload.token).to eq(hmac_keys.active.digest(key))
      expect(token.stage).to eq("test")
    end

    it "refuses a kind the token may not get, back on its page" do
      post :regenerate_token, params: {group_id: group.id, id: token.id, kind: "plain"}

      expect(response).to redirect_to(group_service_token_path(group, token))
      expect(flash[:alert]).to include("lässt sich für diesen API-Key hier nicht erzeugen")
      expect(ServiceToken.find_by_plain_token(token.plain_token)).to eq(token)
    end
  end

  describe "acting person" do
    let!(:token) { ServiceToken.create!(layer: group, **token_params) }
    let(:person) { people(:yp_a_1) }

    context "for an admin" do
      it "is the person autocomplete after the description in the core's form" do
        [[:edit, {id: token.id}], [:new, {}]].each do |action, extra|
          get action, params: {group_id: group.id, **extra}
          form = Capybara.string(response.body).find("form.form-horizontal[id$='service_token#{"_#{token.id}" if action == :edit}']")
          labels = form.all("label.col-form-label").map { |label| label.text.strip }

          expect(labels.index("Handelnde Person")).to eq(labels.index("Beschreibung") + 1), action.to_s
          expect(form).to have_css("input[type=hidden][name='service_token[acting_person_id]']", visible: false)
          expect(form).to have_css("input[data-provide=entity][name='service_token[acting_person]']" \
                                   "[data-url='/wsjrdp/service_tokens/acting_people']")
        end
      end

      it "sets the finance scopes, an extra with its base" do
        token.update_columns(acting_person_id: person.id)
        patch :update, params: {group_id: group.id, id: token.id, service_token: {wagon_scopes: ["", "finance:audit"]}}
        expect(token.reload.scopes).to eq(%w[people finance:read finance:audit])
      end

      it "drops the extras when the acting person is removed, and asks first in the form" do
        token.update_columns(acting_person_id: person.id, scopes: %w[people people:log finance:read finance:audit])
        get :edit, params: {group_id: group.id, id: token.id}
        expect(Capybara.string(response.body).find("#service_token_scope_fields")["data-confirm-drop"])
          .to include("%{scopes}", "Trotzdem speichern?")

        patch :update, params: {group_id: group.id, id: token.id,
                                service_token: {acting_person_id: "", wagon_scopes: ["", "people:log", "finance:read", "finance:audit"]}}
        expect(token.reload.acting_person_id).to be_nil
        expect(token.scopes).to eq(%w[people finance:read])
      end

      it "is set, shown under Rechte, and cleared" do
        patch :update, params: {group_id: group.id, id: token.id, service_token: {acting_person_id: person.id}}
        expect(token.reload.acting_person).to eq(person)

        get :show, params: {group_id: group.id, id: token.id}
        expect(response.body).to include("Nur soweit auch #{person} (ID #{person.id}) darf")

        patch :update, params: {group_id: group.id, id: token.id, service_token: {acting_person_id: ""}}
        expect(token.reload.acting_person).to be_nil
      end
    end

    context "for the root user, who is not an admin" do
      before { sign_in(root_user) }

      it "is not a field of the edit page" do
        get :edit, params: {group_id: group.id, id: token.id}

        expect(Capybara.string(response.body)).not_to have_css("input[name='service_token[acting_person_id]']", visible: false)
      end

      it "is not changed by a submitted value" do
        token.update_columns(acting_person_id: person.id)
        patch :update, params: {group_id: group.id, id: token.id,
                                service_token: {description: "neu", acting_person_id: admin.id}}

        expect(token.reload.description).to eq("neu")
        expect(token.acting_person_id).to eq(person.id)
      end
    end
  end

  # Only an admin manages API keys, and only those of the root group: every
  # action raises CanCan::AccessDenied for anyone else and changes nothing.
  describe "who may manage API keys" do
    shared_examples "refuses" do |actions|
      verbs = {index: :get, new: :get, create: :post, show: :get, edit: :get, update: :patch,
               regenerate_token: :post, destroy: :delete}
      actions.each do |action|
        verb = verbs.fetch(action)
        it "refuses #{action}" do
          stored = token.reload.attributes
          params = {group_id: token_group.id}
          params[:id] = token.id unless %i[index new create].include?(action)
          params[:service_token] = token_params.merge(name: "Neu") if action == :create
          params[:service_token] = {description: "neu"} if action == :update

          expect { send(verb, action, params: params) }.to raise_error(CanCan::AccessDenied)
          expect(token.reload.attributes).to eq(stored)
          expect(ServiceToken.where(name: "Neu")).to be_empty
        end
      end
    end

    # An API key outside the root group, which the model refuses to make: it
    # is made in the root group and moved with update_column.
    def token_in(group)
      ServiceToken.create!(layer: groups(:root), **token_params).tap { |token| token.update_column(:layer_group_id, group.id) }
    end

    context "a CMT leader (Group::Root::Leader, :layer_and_below_full without :admin)" do
      let(:token_group) { group }
      let!(:token) { ServiceToken.create!(layer: group, **token_params) }

      before { sign_in(people(:cmt_leader)) }

      it_behaves_like "refuses", %i[index new create show edit update regenerate_token destroy]
    end

    context "a unit manager, for an API key of their unit" do
      let(:token_group) { groups(:unit_a) }
      let!(:token) { token_in(token_group) }

      before { sign_in(people(:um_a_1)) }

      it_behaves_like "refuses", %i[index new create show edit update regenerate_token destroy]
    end

    context "an admin, for an API key outside the root group" do
      let(:token_group) { groups(:unit_a) }
      let!(:token) { token_in(token_group) }

      it_behaves_like "refuses", %i[new create edit update regenerate_token]

      it "lists, shows and deletes the API key, with no edit and no new token offered" do
        get :index, params: {group_id: token_group.id}
        expect(response).to have_http_status(200)
        expect(response.body).to include(ERB::Util.html_escape(token.name))
        expect(Capybara.string(response.body)).not_to have_css("a[href$='/service_tokens/new']")

        get :index, params: {group_id: group.id}
        expect(Capybara.string(response.body)).to have_css("a[href$='/groups/#{group.id}/service_tokens/new']")

        get :show, params: {group_id: token_group.id, id: token.id}
        expect(response).to have_http_status(200)
        page = Capybara.string(response.body)
        expect(page).to have_link("Löschen")
        expect(page).not_to have_link("Bearbeiten")
        expect(page).not_to have_css("a[href*='regenerate_token']")

        expect { delete :destroy, params: {group_id: token_group.id, id: token.id} }
          .to change(ServiceToken, :count).by(-1)
        expect(response).to redirect_to(group_service_tokens_path(token_group, returning: true))
      end

      it "cannot make an API key there, and the model refuses one" do
        expect do
          post :create, params: {group_id: token_group.id, service_token: token_params.merge(name: "Neu")}
        end.to raise_error(CanCan::AccessDenied)

        built = ServiceToken.new(layer: token_group, name: "Neu", permission: "layer_read")
        expect(built).not_to be_valid
        expect(built.errors.of_kind?(:layer, :not_root)).to be(true)
        expect(ServiceToken.where(name: "Neu")).to be_empty
      end
    end
  end
end
