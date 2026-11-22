# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Moss
  # Every request sent and its answer, for debugging, with the secrets cut
  # out: the client secret, every token, the Authorization header and
  # cookies. Each Exchange also has a smaller form for a log (#for_log).
  class Transcript
    LOG_BODY_LIMIT = 10_000
    LOG_HEADER = /\A(content-type|retry-after|x-ratelimit-.*|.*trace.*|.*request-id.*)\z/i
    SECRET_KEYS = %w[access_token client_secret refresh_token id_token].freeze

    # One request. response_body is parsed JSON where it is JSON; error is
    # set when no answer came.
    Exchange = Data.define(:step, :method, :url, :request_headers, :request_body, :status, :response_headers,
      :response_body, :duration_ms, :error) do
      # The form a log keeps: no request body, a few headers, the data of a
      # list as its ids only, at most LOG_BODY_LIMIT characters of body.
      def for_log
        {step: step, method: method, url: url, status: status, duration_ms: duration_ms, error: error,
         response: response_for_log}.compact
      end

      private

      def response_for_log
        return nil if status.nil?

        {headers: response_headers.select { |name, _value| name.match?(LOG_HEADER) },
         body: limited(ids_only(response_body))}
      end

      def ids_only(body)
        return body unless body.is_a?(Hash) && body["data"].is_a?(Array)

        body.merge("data" => body["data"].map { |record| record.is_a?(Hash) ? record["id"] : nil })
      end

      def limited(body)
        text = body.is_a?(String) ? body : body.to_json
        return body if text.size <= LOG_BODY_LIMIT

        {"truncated" => true, "size" => text.size, "text" => text[0, LOG_BODY_LIMIT]}
      end
    end

    attr_reader :exchanges

    def initialize(clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @secrets = []
      @clock = clock
      @exchanges = []
    end

    # A value that must never show, such as a token once it is known.
    def add_secret(secret) = secret.present? && @secrets << secret

    def inspect = "#<#{self.class.name} #{@exchanges.size} exchanges>"
    alias_method :to_s, :inspect

    # Sends the request of the block (Wsjrdp::Moss.request) and records it.
    def run(step, method:, url:)
      started = @clock.call
      response = Wsjrdp::Moss.request { yield }
      @exchanges << answered(step, response, elapsed(started))
      response
    rescue Error => e
      @exchanges << Exchange.new(step: step, method: method, url: url, request_headers: {}, request_body: nil,
        status: nil, response_headers: {}, response_body: nil, duration_ms: elapsed(started), error: e.message)
      raise
    end

    private

    def elapsed(started) = ((@clock.call - started) * 1000).round

    def answered(step, response, duration_ms)
      env = response.env
      Exchange.new(step: step, method: env.method.to_s.upcase, url: scrub(env.url.to_s),
        request_headers: headers(env.request_headers), request_body: request_body(env.request_body),
        status: response.status, response_headers: headers(response.headers), response_body: body(response.body),
        duration_ms: duration_ms, error: nil)
    end

    def headers(given)
      given.to_h.to_h do |name, value|
        name = name.to_s.downcase
        shown = if name == "authorization" then value.to_s[/\A\S+\s/].to_s + REDACTED
        elsif name.match?(/cookie/) then REDACTED
        else
          scrub(value.to_s)
        end
        [name, shown]
      end
    end

    # A form body as its fields; anything else as text.
    def request_body(text)
      return nil if text.blank?

      fields = URI.decode_www_form(text.to_s).to_h
      deep_scrub(fields)
    rescue ArgumentError
      scrub(text.to_s)
    end

    def body(text)
      return nil if text.blank?

      deep_scrub(JSON.parse(text.to_s))
    rescue JSON::ParserError
      scrub(text.to_s)
    end

    def deep_scrub(value)
      case value
      when Hash then value.to_h { |key, inner| [key, SECRET_KEYS.include?(key.to_s) ? REDACTED : deep_scrub(inner)] }
      when Array then value.map { |inner| deep_scrub(inner) }
      when String then scrub(value)
      else value
      end
    end

    def scrub(text) = @secrets.reduce(text) { |shown, secret| shown.gsub(secret, REDACTED) }
  end
end
