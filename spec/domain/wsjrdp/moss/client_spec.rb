# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Every request is stubbed (WebMock): no spec ever calls Moss. Hosts, ids,
# secrets and tokens are made up.
describe Wsjrdp::Moss::Client do
  let(:base_url) { "https://moss.example.org" }
  let(:secret) { "sk_made-up-secret-4711" }
  let(:now) { [1000.0] }
  let(:waits) { [] }
  let(:client) do
    described_class.new(base_url: base_url, client_id: "kid_made-up", client_secret: secret, scope: "read",
      clock: -> { now.first }, sleeper: ->(seconds) { waits << seconds })
  end

  def json(body, status: 200) = {status: status, body: body.to_json, headers: {"Content-Type" => "application/json"}}

  def stub_token(*tokens, expires_in: 3600)
    stub_request(:post, "#{base_url}/oauth2/token")
      .to_return(*tokens.map { |token| json({access_token: token, token_type: "Bearer", expires_in: expires_in}) })
  end

  def page(records, has_more:, page: 1, total: nil)
    json({data: records, meta: {apiVersion: "0.1.0", tracingId: "t",
                                pagination: {type: "offset", page: page, pageSize: 2, hasMore: has_more,
                                             totalItems: total}.compact}})
  end

  def stub_page(number, records, has_more:)
    stub_request(:get, "#{base_url}/v1/users?page=#{number}&page_size=2")
      .to_return(page(records, has_more: has_more, page: number))
  end

  it "reads every page until Moss says there are no more, with one token" do
    token = stub_token("token-a")
    stub_page(1, [{id: "u1"}, {id: "u2"}], has_more: true)
    stub_page(2, [{id: "u3"}], has_more: false)

    expect(client.all("v1/users", page_size: 2).pluck("id")).to eq(%w[u1 u2 u3])
    expect(token).to have_been_requested.once
    expect(client.total_items("v1/users")).to be_nil
  end

  it "reads lazily: taking the first records asks for the first page only" do
    stub_token("token-a")
    stub_page(1, [{id: "u1"}, {id: "u2"}], has_more: true)
    second = stub_page(2, [{id: "u3"}], has_more: false)

    expect(client.each("v1/users", page_size: 2).first(2).pluck("id")).to eq(%w[u1 u2])
    expect(second).not_to have_been_requested
  end

  it "passes filters along on every page and keeps how many records Moss says there are" do
    stub_token("token-a")
    filtered = stub_request(:get, "#{base_url}/v1/teams?department_id=d1&page=1&page_size=100")
      .to_return(page([{id: "t1"}], has_more: false, total: 1))

    expect(client.all("v1/teams", {department_id: "d1"}).pluck("id")).to eq(%w[t1])
    expect(filtered).to have_been_requested
    expect(client.total_items("v1/teams")).to eq(1)
  end

  it "fetches a new token once after a 401 and repeats the request" do
    stub_token("token-a", "token-b")
    stub_request(:get, "#{base_url}/v1/departments")
      .with(headers: {"Authorization" => "Bearer token-a"}).to_return(json({}, status: 401))
    stub_request(:get, "#{base_url}/v1/departments")
      .with(headers: {"Authorization" => "Bearer token-b"}).to_return(json({data: [{id: "d1"}]}))

    expect(client.get("v1/departments")["data"]).to eq([{"id" => "d1"}])
  end

  it "renews the token shortly before it runs out" do
    token = stub_token("token-a", "token-b", expires_in: 600)
    stub_request(:get, "#{base_url}/v1/departments").to_return(json({data: []}))

    client.get("v1/departments")
    now[0] += 299
    client.get("v1/departments")
    expect(token).to have_been_requested.once

    now[0] += 2
    client.get("v1/departments")
    expect(token).to have_been_requested.twice
  end

  it "raises Moss's error and keeps no secret or token in the transcript" do
    stub_token("token-secret-a")
    stub_request(:get, "#{base_url}/v1/users?page=1&page_size=100")
      .to_return(json({errors: [{title: "Forbidden", detail: "token-secret-a lacks a scope"}]}, status: 403))

    expect { client.all("v1/users") }.to raise_error(Wsjrdp::Moss::Error, "Forbidden: [entfernt] lacks a scope")
    expect(client.transcript.exchanges.size).to eq(2)
    expect(client.transcript.exchanges.inspect).not_to include("token-secret-a", secret)
  end

  it "tries a read again after no answer or a busy Moss, waiting as Moss asks" do
    stub_token("token-a")
    stub_request(:get, "#{base_url}/v1/departments").to_timeout
      .then.to_return(status: 503, headers: {"Retry-After" => "3"})
      .then.to_return(json({data: [{id: "d1"}]}))

    expect(client.get("v1/departments")["data"]).to eq([{"id" => "d1"}])
    expect(waits).to eq([1, 3])
  end

  it "gives up after the last try" do
    stub_token("token-a")
    stub_request(:get, "#{base_url}/v1/departments").to_timeout

    expect { client.get("v1/departments") }.to raise_error(Wsjrdp::Moss::Error, "no answer in time")
    expect(waits).to eq([1, 2])
  end

  it "stops a list that never ends" do
    stub_const("#{described_class}::MAX_PAGES", 2)
    stub_token("token-a")
    stub_request(:get, %r{\A#{base_url}/v1/users\?}).to_return(page([{id: "u"}], has_more: true))

    expect { client.all("v1/users") }.to raise_error(Wsjrdp::Moss::Error, /more than 2 pages/)
  end
end
