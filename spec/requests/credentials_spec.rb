# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# What only the whole stack shows of the credential store pages: the
# sign-in by token and the routing of an account key.
describe "Credential store pages", type: :request do
  before_all(setup_fixtures: true) {}

  let_it_be(:admin) { Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person }
  let(:password) { "made-up-smtp-password-4711" }

  before { use_overrides }

  it "refuses a sign-in by token for the pages and the reveal" do
    row = Wsjrdp::Credentials::Deposit.call(kind: "mail_account", account_key: "finanzen",
      values: {"mail_from" => "finanzen@example.org", "smtp_host" => "mail.example.org", "smtp_password" => password}).record
    service_token = ServiceToken.create!(layer: groups(:root), name: "Skript", people: true,
      permission: "layer_and_below_full", acting_person: admin)
    oauth_token = Fabricate(:access_token, application: Fabricate(:application), scopes: "api",
      resource_owner_id: admin.id)
    ways = {"personal token" => {"X-User-Email" => admin.email, "X-User-Token" => admin.generate_authentication_token!},
            "service token" => {"X-Token" => service_token.plain_token},
            "OAuth token" => {"Authorization" => "Bearer #{oauth_token.token}"}}

    aggregate_failures do
      ways.each do |way, headers|
        post "/credentials/mail_account/finanzen/reveal", headers: headers,
          params: {source: "database", version_id: row.id, field: "smtp_password"}
        expect(response).to have_http_status(403), way
        expect(response.body).not_to include(password)
      end
      get "/credentials/versions/#{row.id}/edit", headers: ways["personal token"]
      expect(response).to have_http_status(403)
    end
  end

  it "routes an account key holding @ + . , and a letter beyond ASCII" do
    sign_in(admin)
    key = "müller+test,1@worldscoutjamboree.de"
    path = "/credentials/mail_account/#{ERB::Util.url_encode(key).gsub("%40", "@").gsub("%2B", "+").gsub("%2C", ",")}"

    post "#{path}/versions", params: {credential: {fields: {mail_from: "a@example.org", smtp_host: "mail.example.org"},
                                                   secret: {smtp_password: password}}}

    row = WsjrdpCredential.last
    expect(row.account_key).to eq(key)
    expect(response).to redirect_to("#{path}#credential-version-#{row.id}")
    expect(Wsjrdp::Credentials.fetch(:mail_account, key.upcase).version_id).to eq(row.id)
  end

  it "routes the account page under its encoded path" do
    route = Rails.application.routes.recognize_path("/credentials/mail_account/m%C3%BCller+test,1@worldscoutjamboree.de")

    expect(route).to include(controller: "credentials", action: "show")
    expect(route[:account_key].dup.force_encoding(Encoding::UTF_8)).to eq("müller+test,1@worldscoutjamboree.de")
  end
end
