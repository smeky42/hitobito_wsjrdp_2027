# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Every request is stubbed (WebMock): no spec ever calls Moss. Hosts,
# ids, secrets and tokens are made up; the answers follow the local spec
# doc/moss/openapi_spec/openapi.yaml.
describe Wsjrdp::Moss::ConnectionCheck do
  let(:base_url) { "https://moss.example.org" }
  let(:secret) { "sk_made-up-secret-4711" }
  let(:access_token) { "made-up-access-token-0815" }
  let(:token_url) { "#{base_url}/oauth2/token" }
  let(:users_url) { "#{base_url}/v1/users?page_size=1" }

  def check(**options)
    described_class.new(base_url: base_url, client_id: "kid_made-up", client_secret: secret, scope: "read", **options)
  end

  def json(body, status: 200) = {status: status, body: body.to_json, headers: {"Content-Type" => "application/json"}}

  def stub_token(**answer)
    stub_request(:post, token_url).to_return(json({access_token: access_token, token_type: "Bearer",
      expires_in: 3600, scope: "read"}, **answer))
  end

  def moss_error(title, detail: nil, status: 401)
    json({data: nil, meta: {apiVersion: "0.1.0", tracingId: "trace-123"},
          errors: [{type: "ERR_X", title: title, detail: detail}.compact]}, status: status)
  end

  it "fetches a token with the form, then reads one user with it" do
    token = stub_token
    users = stub_request(:get, users_url).with(headers: {"Authorization" => "Bearer #{access_token}"})
      .to_return(json({data: [], meta: {apiVersion: "0.1.0", tracingId: "t"}}))

    result = check.call

    expect(result).to be_ok
    expect(result).to have_attributes(scope: "read", expires_in: 3600, host: "moss.example.org", step: nil)
    expect(token.with(body: {grant_type: "client_credentials", client_id: "kid_made-up", client_secret: secret,
                             scope: "read"})).to have_been_requested
    expect(users).to have_been_requested
  end

  it "keeps a path in base_url" do
    stub_request(:post, "https://moss.example.org/api/oauth2/token")
      .to_return(json({access_token: access_token, expires_in: 3600}))
    stub_request(:get, "https://moss.example.org/api/v1/users?page_size=1").to_return(json({data: []}))

    expect(check(base_url: "https://moss.example.org/api/").call).to be_ok
  end

  it "reports a refused token with Moss's text, the status and the tracing id, and never reads" do
    stub_request(:post, token_url).to_return(moss_error("Invalid client", detail: "client #{secret} unknown"))

    result = check.call

    expect(result).not_to be_ok
    expect(result).to have_attributes(step: :token, status: 401, tracing_id: "trace-123")
    expect(result.message).to eq("Invalid client: client [entfernt] unknown")
    expect(a_request(:get, users_url)).not_to have_been_made
  end

  it "reads the OAuth form of an error" do
    stub_request(:post, token_url).to_return(json({error: "invalid_client", error_description: "bad"}, status: 400))

    expect(check.call.message).to eq("invalid_client: bad")
  end

  it "reports a failed read, without the token" do
    stub_token
    stub_request(:get, users_url).to_return(moss_error("Forbidden", detail: "token #{access_token}", status: 403))

    result = check.call

    expect(result).to have_attributes(ok: false, step: :read, status: 403, scope: "read")
    expect(result.message).not_to include(access_token)
  end

  it "names a timeout, a connection failure and a redirect without following it" do
    stub_request(:post, token_url).to_timeout
    expect(check.call.message).to eq("no answer in time")

    stub_request(:post, token_url).to_raise(Faraday::ConnectionFailed.new("refused"))
    expect(check.call.message).to eq("no connection (ConnectionFailed)")

    stub_request(:post, token_url).to_return(status: 302, headers: {"Location" => "https://elsewhere.example.org/"})
    expect(check.call).to have_attributes(ok: false, status: 302, message: "HTTP 302")
    expect(a_request(:any, /elsewhere/)).not_to have_been_made
  end

  it "takes an answer without a token as a failure" do
    stub_request(:post, token_url).to_return(json({token_type: "Bearer"}))

    expect(check.call).to have_attributes(ok: false, step: :token, message: "the answer holds no access token")
  end

  it "records every request and answer, with the secret, the token and the Authorization cut out" do
    stub_token
    stub_request(:get, users_url).to_return(json({data: [{id: "u-1", email: "made-up@example.org"}],
      meta: {tracingId: "t-1"}}).merge(headers: {"Content-Type" => "application/json", "X-RateLimit-Remaining" => "9",
                                                 "Set-Cookie" => "session=made-up"}))

    token, read = check.call.exchanges

    expect(token).to have_attributes(step: :token, method: "POST", url: token_url, status: 200)
    expect(token.request_body).to include("client_id" => "kid_made-up", "client_secret" => "[entfernt]")
    expect(token.response_body).to include("access_token" => "[entfernt]", "expires_in" => 3600)
    expect(read.request_headers["authorization"]).to eq("Bearer [entfernt]")
    expect(read.response_headers["set-cookie"]).to eq("[entfernt]")
    expect(read.response_body["data"]).to eq([{"id" => "u-1", "email" => "made-up@example.org"}])
    [token, read].each do |exchange|
      expect(exchange.to_h.to_json).not_to include(secret)
      expect(exchange.to_h.to_json).not_to include(access_token)
    end

    log = read.for_log
    expect(log).to include(step: :read, method: "GET", status: 200)
    expect(log[:response][:headers]).to eq("content-type" => "application/json", "x-ratelimit-remaining" => "9")
    expect(log[:response][:body]).to eq("data" => ["u-1"], "meta" => {"tracingId" => "t-1"})
    expect(log).not_to have_key(:request_body)
  end

  it "records a request that got no answer, and cuts a long body for the log" do
    stub_request(:post, token_url).to_timeout
    expect(check.call.exchanges.sole).to have_attributes(step: :token, status: nil, error: "no answer in time")

    stub_request(:post, token_url).to_return(status: 500, body: "x" * 20_000)
    body = check.call.exchanges.sole.for_log[:response][:body]
    expect(body).to include("truncated" => true, "size" => 20_000)
    expect(body["text"].size).to eq(10_000)
  end

  it "never shows the secret or the token in inspect" do
    stub_token
    token = Wsjrdp::Moss::TokenRequest.new(base_url: base_url, client_id: "kid", client_secret: secret).call

    [token.inspect, token.to_s, check.inspect,
      Wsjrdp::Moss::TokenRequest.new(base_url: base_url, client_id: "kid", client_secret: secret).inspect].each do |shown|
      expect(shown).not_to include(secret)
      expect(shown).not_to include(access_token)
    end
  end
end
