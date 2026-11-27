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
  before_all(setup_fixtures: true) {}

  let(:group) { groups(:root) }
  # The fixture `admin` is a Group::Root::Leader (spec/fixtures/roles.yml); the
  # Admin role gives it the :admin permission.
  let_it_be(:admin, refind: true) do
    people(:admin).tap { |person| Group::Root::Admin.create!(person: person, group: groups(:root)) }
  end
  # The core's root user (Person#root?) may everything without being an admin:
  # the one person besides the admins who reaches these pages.
  let_it_be(:root_user, refind: true) { Fabricate(:person, email: Settings.root_email) }

  let(:token_params) do
    {name: "Skript", description: "Abmelde-Formulare", people: true, permission: "layer_read"}
  end

  let(:token) { ServiceToken.create!(layer: group, **token_params) }
  let(:person) { people(:yp_a_1) }

  def made_token = ServiceToken.find_by!(layer: group, name: "Skript")

  # The key of the answer, as the page shows it.
  def shown_key = controller.send(:entry).plain_token

  def hmac_keys = Wsjrdp2027::ServiceTokenHmacKeys.current

  def dev_value(key)
    Wsjrdp2027::ServiceTokenHmacKeys.new("development:#{"d" * 64}", stage: "development").digests(key).first
  end

  before { sign_in(admin) }

  describe "POST create" do
    it "answers with the key, stores its HMAC by default and keeps the key out of the flash for the next page" do
      post :create, params: {group_id: group.id, service_token: token_params}

      expect(response).to have_http_status(:ok)
      expect(response).to render_template("service_tokens/plain_token")
      expect(shown_key).to match(/\A[A-Za-z0-9_-]{50}\z/)
      expect(made_token.token).to eq(hmac_keys.active.digest(shown_key))
      expect(flash[:notice]).to be_present
      expect(flash.to_session_value).to be_nil
    end

    it "stores the kind chosen" do
      post :create, params: {group_id: group.id, service_token: token_params.merge(token_kind: "sha256")}

      expect(made_token.token).to eq(ServiceToken.digest_token(shown_key))
    end

    it "adopts the stage, the token hash and the fingerprint of another stage, with no token to show" do
      value = dev_value("x" * 50)
      fingerprint = Wsjrdp2027::ServiceTokenHmacKeys.fingerprint_of("d" * 64)
      post :create, params: {group_id: group.id,
                             service_token: token_params.merge(token_kind: "adopt", adopted_stage: "development",
                               adopted_token: value, adopted_fingerprint: fingerprint)}

      expect(response).to redirect_to(group_service_tokens_path(group))
      expect([made_token.token, made_token.stage, made_token.hmac_secret_key_fingerprint])
        .to eq([value, "development", fingerprint])
    end

    it "shows the choice again when an adopted value is refused" do
      post :create, params: {group_id: group.id,
                             service_token: token_params.merge(token_kind: "adopt", adopted_token: "nonsense")}

      expect(response).to have_http_status(422)
      expect(ServiceToken.where(layer: group).count).to eq(0)
    end

    it "answers a Turbo request with the stream that puts the key where the form was" do
      post :create, params: {group_id: group.id, service_token: token_params}, format: :turbo_stream

      expect(response).to render_template("service_tokens/create")
      expect(ServiceToken.find_by_plain_token(shown_key)).to eq(made_token)
    end

    it "shows the form again when the token is not valid" do
      post :create, params: {group_id: group.id, service_token: token_params.merge(name: "")}

      expect(response).to have_http_status(422)
      expect(ServiceToken.where(layer: group).count).to eq(0)
    end
  end

  describe "POST regenerate_token" do
    it "replaces the key and shows the new one" do
      old_key = token.plain_token
      post :regenerate_token, params: {group_id: group.id, id: token.id}

      expect(response).to render_template("service_tokens/plain_token")
      expect(ServiceToken.find_by_plain_token(shown_key)).to eq(token)
      expect(ServiceToken.find_by_plain_token(old_key)).to be_nil
      expect(flash.to_session_value).to be_nil
    end

    it "is refused to a person who may not change the token" do
      sign_in(person)
      expect do
        post :regenerate_token, params: {group_id: group.id, id: token.id}
      end.to raise_error(CanCan::AccessDenied)
      expect(token.reload.token).to eq(hmac_keys.active.digest(token.plain_token))
    end

    it "gives the kind asked for" do
      token.update_column(:token, "Legacy0123456789abcdefghijklmnopqrstuvwxyzABCDEFGH")
      post :regenerate_token, params: {group_id: group.id, id: token.id, kind: "sha256"}

      expect(token.reload.token).to eq(ServiceToken.digest_token(shown_key))
    end

    it "refuses a kind the token may not get, back on its page" do
      post :regenerate_token, params: {group_id: group.id, id: token.id, kind: "plain"}

      expect(response).to redirect_to(group_service_token_path(group, token))
      expect(flash[:alert]).to be_present
      expect(ServiceToken.find_by_plain_token(token.plain_token)).to eq(token)
    end
  end

  describe "PATCH update" do
    def update(**attrs) = patch :update, params: {group_id: group.id, id: token.id, service_token: attrs}

    it "drops the extras without an acting person" do
      update(wagon_scopes: ["", "people:log"])

      expect(token.reload.scopes).to eq(%w[people])
    end

    it "stores the extras with an acting person" do
      token.update_columns(acting_person_id: admin.id)
      update(wagon_scopes: ["", "people:documents"])

      expect(token.reload.scopes).to eq(%w[people people:documents])
    end

    it "sets the finance scopes for an admin, an extra with its base" do
      token.update_columns(acting_person_id: person.id)
      update(wagon_scopes: ["", "finance:audit"])

      expect(token.reload.scopes).to eq(%w[people finance:read finance:audit])
    end

    it "sets the acting person for an admin" do
      update(acting_person_id: person.id)

      expect(token.reload.acting_person).to eq(person)
    end

    it "drops the extras with the acting person" do
      token.update_columns(acting_person_id: person.id, scopes: %w[people people:log finance:read finance:audit])
      update(acting_person_id: "", wagon_scopes: ["", "people:log", "finance:read", "finance:audit"])

      expect(token.reload.acting_person_id).to be_nil
      expect(token.scopes).to eq(%w[people finance:read])
    end

    describe "for the root user, who is not an admin" do
      before { sign_in(root_user) }

      it "keeps the finance scopes when others are sent" do
        token.update_columns(scopes: %w[people finance:read])
        update(description: "neu", wagon_scopes: ["", "finance:audit"])

        expect(token.reload.description).to eq("neu")
        expect(token.scopes).to eq(%w[people finance:read])
      end

      it "keeps the acting person" do
        token.update_columns(acting_person_id: person.id)
        update(description: "neu", acting_person_id: admin.id)

        expect(token.reload.description).to eq("neu")
        expect(token.acting_person_id).to eq(person.id)
      end
    end
  end

  # What the pages decide themselves: where the key shows, which buttons and
  # fields they offer.
  describe "pages" do
    render_views

    def page = Capybara.string(response.body)

    it "shows the key on a page of its own, with the stored value" do
      post :create, params: {group_id: group.id, service_token: token_params}

      expect(page.find("input#service_token_plain_token").value).to eq(shown_key)
      expect(response.body).to include(made_token.token)
    end

    it "puts the key into the stream" do
      post :create, params: {group_id: group.id, service_token: token_params}, format: :turbo_stream

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('action="replace" target="service_token_new"', 'action="update" target="flash"')
      # The stream's content stands in <template>, which Capybara does not search.
      expect(Nokogiri::HTML(response.body).at_css("input#service_token_plain_token")["value"]).to eq(shown_key)
    end

    it "draws the storage choice and the core's form in what the Turbo answer replaces" do
      get :new, params: {group_id: group.id}

      expect(page).to have_css("#service_token_new form#new_service_token")
      expect(page).to have_css("#service_token_new input[name='service_token[token_kind]'][form='new_service_token']", count: 4)
    end

    it "shows the stored value, not the key, and offers each new kind by a POST that asks first" do
      token.update_columns(token: ServiceToken.digest_token(token.plain_token), stage: nil)
      get :show, params: {group_id: group.id, id: token.id}

      expect(response.body).not_to include(token.plain_token)
      expect(response.body).to include(token.reload.token)
      %w[sha256 hmac].each do |kind|
        expect(page).to have_css("a[href$='regenerate_token?kind=#{kind}'][data-method=post][data-confirm]")
      end
    end

    it "offers no new token for a token of another stage" do
      token.update_columns(token: dev_value("x" * 50), stage: "development", hmac_secret_key_fingerprint: nil)
      get :show, params: {group_id: group.id, id: token.id}

      expect(page).not_to have_css("a[href*='regenerate_token']")
    end

    it "lists the token with its digest, not the key" do
      key = token.plain_token
      get :index, params: {group_id: group.id}

      expect(response.body).not_to include(key)
      expect(response.body).to include(token.token)
    end

    it "offers an admin only deleting for an API key outside the root group" do
      token.update_column(:layer_group_id, groups(:unit_a).id)
      get :show, params: {group_id: groups(:unit_a).id, id: token.id}

      expect(page).to have_css("a[href$='/service_tokens/#{token.id}'][data-method=delete]")
      expect(page).not_to have_css("a[href$='/service_tokens/#{token.id}/edit']")
      expect(page).not_to have_css("a[href*='regenerate_token']")
    end

    it "offers an admin the acting person after the description, and the extras only with one" do
      get :edit, params: {group_id: group.id, id: token.id}

      form = page.find("form.form-horizontal[id$='service_token_#{token.id}']")
      labels = form.all("label.col-form-label").map { |label| label.text.strip }
      expect(labels.index(ServiceToken.human_attribute_name(:acting_person))).to eq(labels.index(ServiceToken.human_attribute_name(:description)) + 1)
      expect(form).to have_css("input[data-provide=entity][name='service_token[acting_person]']" \
                               "[data-url='/wsjrdp/service_tokens/acting_people']")
      expect(page.find("input#service_token_people").ancestor(".form-check"))
        .to have_xpath("following-sibling::div[1][@data-scope-extra='people:log']")
      expect(page).to have_css("input#service_token_scope_finance_read:not([disabled])")
      %w[people_log people_documents finance_audit].each do |scope|
        expect(page).to have_css("input#service_token_scope_#{scope}[disabled]")
      end
      expect(page).to have_css("[data-scope-extras-hint]:not([hidden])")
      expect(page.find("#service_token_scope_fields")["data-confirm-drop"]).to include("%{scopes}")
    end

    it "enables the extras with an acting person" do
      token.update_columns(acting_person_id: admin.id)
      get :edit, params: {group_id: group.id, id: token.id}

      expect(page).to have_css("input#service_token_scope_people_log:not([disabled])")
      expect(page).to have_css("[data-scope-extras-hint][hidden]", visible: false)
    end

    it "offers the root user, who is not an admin, no acting person, and the finance scopes only to look at" do
      sign_in(root_user)
      token.update_columns(acting_person_id: admin.id)
      get :edit, params: {group_id: group.id, id: token.id}

      expect(page).not_to have_css("input[name='service_token[acting_person_id]']", visible: false)
      expect(page).to have_css("input#service_token_scope_finance_read[disabled]")
      expect(page).to have_css("input#service_token_scope_finance_manage[disabled]")
    end
  end

  # Only an admin manages API keys, and only those of the root group: every
  # action raises CanCan::AccessDenied for anyone else and changes nothing.
  describe "who may manage API keys" do
    shared_examples "refuses" do |actions|
      verbs = {index: :get, new: :get, create: :post, show: :get, edit: :get, update: :patch,
               regenerate_token: :post, destroy: :delete}
      it "refuses #{actions.join(", ")}" do
        stored = guarded.attributes
        aggregate_failures do
          actions.each do |action|
            params = {group_id: token_group.id}
            params[:id] = guarded.id unless %i[index new create].include?(action)
            params[:service_token] = token_params.merge(name: "Neu") if action == :create
            params[:service_token] = {description: "neu"} if action == :update

            expect { send(verbs.fetch(action), action, params: params) }.to raise_error(CanCan::AccessDenied), action.to_s
            expect(guarded.reload.attributes).to eq(stored), action.to_s
          end
          expect(ServiceToken.where(name: "Neu")).to be_empty
        end
      end
    end

    # An API key outside the root group, which the model refuses to make: it
    # is made in the root group and moved with update_column.
    def self.token_in(group_key)
      let_it_be(:guarded, refind: true) do
        ServiceToken.create!(layer: groups(:root), name: "Skript", people: true, permission: "layer_read")
          .tap { |token| token.update_column(:layer_group_id, groups(group_key).id) }
      end
      let(:token_group) { groups(group_key) }
    end

    context "a CMT leader (Group::Root::Leader, :layer_and_below_full without :admin)" do
      token_in(:root)

      before { sign_in(people(:cmt_leader)) }

      it_behaves_like "refuses", %i[index new create show edit update regenerate_token destroy]
    end

    context "a unit manager, for an API key of their unit" do
      token_in(:unit_a)

      before { sign_in(people(:um_a_1)) }

      it_behaves_like "refuses", %i[index new create show edit update regenerate_token destroy]
    end

    context "an admin, for an API key outside the root group" do
      token_in(:unit_a)

      it_behaves_like "refuses", %i[new create edit update regenerate_token]

      it "deletes the API key" do
        expect { delete :destroy, params: {group_id: token_group.id, id: guarded.id} }
          .to change(ServiceToken, :count).by(-1)
        expect(response).to redirect_to(group_service_tokens_path(token_group, returning: true))
      end
    end
  end
end
