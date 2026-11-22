# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Moss
  # Fetches one access token from Moss (OAuth2 client credentials,
  # POST /oauth2/token). It gets the credentials handed in and knows nothing
  # of where they are kept.
  #
  #   token = Wsjrdp::Moss::TokenRequest.new(base_url: "https://public-api.getmoss.com",
  #     client_id: "kid_…", client_secret: "sk_…", scope: "read").call
  #
  # No retry, and no redirect is followed, so the secret only goes to
  # base_url. Raises Wsjrdp::Moss::Error. A transcript, if given, records
  # the request and its answer.
  class TokenRequest
    # The token; inspect never shows it.
    Token = Data.define(:access_token, :token_type, :scope, :expires_in) do
      def inspect = "#<#{self.class.name} #{token_type} scope=#{scope} expires_in=#{expires_in}>"
      alias_method :to_s, :inspect
    end

    def initialize(base_url:, client_id:, client_secret:, scope: nil, transcript: nil)
      @base_url = base_url.to_s.chomp("/")
      @transcript = transcript || Transcript.new
      @transcript.add_secret(client_secret)
      @client_id = client_id
      @client_secret = client_secret
      @scope = scope
    end

    def inspect = "#<#{self.class.name} #{@base_url} scope=#{@scope}>"
    alias_method :to_s, :inspect

    def call
      response = @transcript.run(:token, method: "POST", url: "#{@base_url}/oauth2/token") do
        Wsjrdp::Moss.connection(@base_url).post("oauth2/token") do |request|
          request.headers["Content-Type"] = "application/x-www-form-urlencoded"
          request.headers["Accept"] = "application/json"
          request.body = URI.encode_www_form(form)
        end
      end
      raise Error.from_response(response, secrets: [@client_secret]) unless response.success?

      token_of(Wsjrdp::Moss.json_object(response.body), response)
    end

    private

    def form
      {grant_type: "client_credentials", client_id: @client_id, client_secret: @client_secret, scope: @scope}.compact
    end

    def token_of(body, response)
      access_token = body["access_token"]
      raise Error.new("the answer holds no access token", status: response.status) unless access_token.is_a?(String)

      Token.new(access_token: access_token, token_type: body["token_type"], scope: body["scope"],
        expires_in: body["expires_in"])
    end
  end
end
