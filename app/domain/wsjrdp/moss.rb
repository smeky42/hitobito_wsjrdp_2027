# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The start of the Moss API client (doc/plans/2026-11_moss-api-client.local.md).
# It gets its credentials handed in; it does not read the credential store.
module Wsjrdp::Moss
  OPEN_TIMEOUT = 5
  TIMEOUT = 10
  # Stands in for a secret or a token in any text shown or kept.
  REDACTED = "[entfernt]"

  # A connection to base_url: short timeouts, no retry, no redirects.
  # Paths are relative ("oauth2/token"), so a path in base_url stays.
  def self.connection(base_url)
    Faraday.new(url: "#{base_url.to_s.chomp("/")}/",
      request: {open_timeout: OPEN_TIMEOUT, timeout: TIMEOUT})
  end

  # An answer's body as a Hash; {} for anything else.
  def self.json_object(text)
    json = JSON.parse(text.to_s)
    json.is_a?(Hash) ? json : {}
  rescue JSON::ParserError
    {}
  end

  # Runs the block; a request that gets no answer raises Error, naming the
  # kind of failure only.
  def self.request
    yield
  rescue Faraday::TimeoutError
    raise Error, "no answer in time"
  rescue Faraday::ConnectionFailed => e
    raise Error, (e.wrapped_exception.is_a?(Timeout::Error) ? "no answer in time" : "no connection (ConnectionFailed)")
  rescue Faraday::SSLError => e
    raise Error, "TLS failed (#{e.class.name.demodulize})"
  rescue Faraday::Error, URI::InvalidURIError, ArgumentError => e
    raise Error, "no connection (#{e.class.name.demodulize})"
  end
end
