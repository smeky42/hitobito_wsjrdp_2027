# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# A request is signed in as the service token whose key it carries -- not as
# one whose stored digest it carries.
describe Authenticatable::Tokens do
  let(:token) do
    ServiceToken.create!(layer: groups(:root), name: "Skript", people: true, permission: "layer_read")
  end

  def service_token_for(headers: {}, params: {})
    request = ActionDispatch::TestRequest.create
    headers.each { |key, value| request.headers[key] = value }
    Authenticatable::Tokens.new(request, ActionController::Parameters.new(params)).service_token
  end

  it "finds the token by the key in the X-Token header" do
    expect(service_token_for(headers: {"X-Token" => token.plain_token})).to eq(token)
  end

  it "finds the token by the key in the token param" do
    expect(service_token_for(params: {token: token.plain_token})).to eq(token)
  end

  it "finds a token that holds its key as it is" do
    token.update_column(:token, "Legacy0123456789abcdefghijklmnopqrstuvwxyzABCDEFGH")

    expect(service_token_for(headers: {"X-Token" => token.token})).to eq(token)
  end

  it "finds nothing by the stored digest" do
    expect(service_token_for(headers: {"X-Token" => token.token})).to be_nil
    expect(service_token_for(params: {token: token.token})).to be_nil
  end
end
