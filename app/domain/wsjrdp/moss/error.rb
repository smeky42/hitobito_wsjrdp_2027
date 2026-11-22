# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp::Moss
  # A failed Moss request: no answer (status nil), or an answer that is not
  # a success. The message is Moss's own error text where it gives one; it
  # never holds a secret or a token.
  class Error < StandardError
    attr_reader :status, :tracing_id

    def initialize(message, status: nil, tracing_id: nil)
      @status = status
      @tracing_id = tracing_id
      super(message)
    end

    # The error of an answer that is not a success: Moss's ErrorResponse
    # (errors[].title/detail), the OAuth form (error, error_description), or
    # the bare status. The secrets are cut out of the text.
    def self.from_response(response, secrets: [])
      body = Wsjrdp::Moss.json_object(response.body)
      new(scrub(text_of(body), secrets).presence || "HTTP #{response.status}",
        status: response.status, tracing_id: body.dig("meta", "tracingId"))
    end

    def self.text_of(body)
      errors = Array(body["errors"]).grep(Hash)
      texts = errors.map { |error| [error["title"], error["detail"]].compact.uniq.join(": ") }
      texts << [body["error"], body["error_description"]].compact.join(": ") if body["error"].is_a?(String)
      texts.compact_blank.join("; ").truncate(500)
    end

    def self.scrub(text, secrets)
      secrets.compact_blank.reduce(text.to_s) { |shown, secret| shown.gsub(secret, REDACTED) }
    end
  end
end
