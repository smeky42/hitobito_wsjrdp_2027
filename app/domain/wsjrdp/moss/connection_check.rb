# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Moss
  # Checks that credentials work: fetches a token, then reads one user
  # (GET /v1/users?page_size=1). The result never holds the secret or the
  # token; its exchanges are every request and answer, for debugging.
  #
  #   result = Wsjrdp::Moss::ConnectionCheck.new(base_url: …, client_id: …, client_secret: …, scope: "read").call
  #   result.ok?   # false: result.step (:token or :read) and result.message say why
  class ConnectionCheck
    TOKEN = :token
    READ = :read

    Result = Data.define(:ok, :step, :message, :status, :tracing_id, :scope, :expires_in, :host, :duration_ms,
      :exchanges) do
      def ok? = ok
    end

    def initialize(base_url:, client_id:, client_secret:, scope: nil,
      clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @base_url = base_url.to_s.chomp("/")
      @client_secret = client_secret
      @clock = clock
      @transcript = Transcript.new(clock: clock)
      @token_request = TokenRequest.new(base_url: base_url, client_id: client_id, client_secret: client_secret,
        scope: scope, transcript: @transcript)
    end

    def inspect = "#<#{self.class.name} #{host}>"
    alias_method :to_s, :inspect

    def call
      started = @clock.call
      step = TOKEN
      token = @token_request.call
      @transcript.add_secret(token.access_token)
      step = READ
      read(token)
      result(started, ok: true, step: nil, token: token)
    rescue Error => e
      result(started, ok: false, step: step, token: token, error: e)
    end

    private

    def read(token)
      response = @transcript.run(READ, method: "GET", url: "#{@base_url}/v1/users?page_size=1") do
        Wsjrdp::Moss.connection(@base_url).get("v1/users", page_size: 1) do |request|
          request.headers["Authorization"] = "Bearer #{token.access_token}"
          request.headers["Accept"] = "application/json"
        end
      end
      return if response.success?

      raise Error.from_response(response, secrets: [@client_secret, token.access_token])
    end

    def result(started, ok:, step:, token:, error: nil)
      Result.new(ok: ok, step: step, message: error&.message, status: error&.status, tracing_id: error&.tracing_id,
        scope: token&.scope, expires_in: token&.expires_in, host: host,
        duration_ms: ((@clock.call - started) * 1000).round, exchanges: @transcript.exchanges.dup.freeze)
    end

    def host
      URI.parse(@base_url).host
    rescue URI::InvalidURIError
      nil
    end
  end
end
