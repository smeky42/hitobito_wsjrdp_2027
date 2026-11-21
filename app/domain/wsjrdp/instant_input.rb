# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "date"
require "tzinfo"

# Reads an instant that a person, a variable or a file typed, strictly: ISO
# 8601 only, nothing guessed (doc/wsjrdp/instant_input.md).
#
#   Wsjrdp::InstantInput.parse("2026-12-01T08:00")                        # => 2026-12-01 08:00:00 UTC
#   Wsjrdp::InstantInput.parse("2026-12-01T08:00+01:00")                  # => 2026-12-01 07:00:00 UTC
#   Wsjrdp::InstantInput.parse("2026-12-01T08:00", zone: "Europe/Berlin") # => 2026-12-01 07:00:00 UTC
#   Wsjrdp::InstantInput.parse("2027-05-19")                              # => 2027-05-19 00:00:00 UTC
#   Wsjrdp::InstantInput.parse("tomorrow")                                # raises Wsjrdp::InstantInput::Invalid
#
# The result is a Time in UTC, nil for blank. A bare date is 00:00 UTC in
# every zone. Invalid never repeats the input: it may be a secret typed into
# the wrong place.
module Wsjrdp::InstantInput
  class Invalid < ArgumentError; end

  FORMS = "an ISO 8601 date and time (YYYY-MM-DDTHH:MM[:SS[.fraction]] with T or a space, optionally Z or " \
    "±HH:MM) or a date (YYYY-MM-DD)"
  MESSAGE = "not an instant: expected #{FORMS}"

  # A date, optionally followed by a time and a zone.
  FORMAT = /\A(\d{4})-(\d{2})-(\d{2})
    (?:[T\ ]([01]\d|2[0-3]):([0-5]\d)(?::([0-5]\d)(?:\.(\d{1,9}))?)?(Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)?)?\z/x

  # Every identifier of UTC in tzinfo.
  UTC_ZONES = %w[UTC Etc/UTC UCT Etc/UCT Universal Etc/Universal Zulu Etc/Zulu GMT Etc/GMT GMT0 Etc/GMT0 GMT+0
    Etc/GMT+0 GMT-0 Etc/GMT-0 Greenwich Etc/Greenwich].freeze

  module_function

  # zone: the zone of a text without one: an IANA name or an
  # ActiveSupport::TimeZone; nil is UTC. Any other zone is an ArgumentError.
  def parse(value, zone: nil)
    tzinfo(zone) unless zone.nil?
    return value.getutc if value.is_a?(Time) # an ActiveSupport::TimeWithZone too
    return parse_text(value, zone) if value.is_a?(String)

    raise Invalid, MESSAGE unless value.nil?
  end

  def parse_text(value, zone)
    # A text that cannot be matched (UTF-16, invalid, with a NUL that strip
    # would drop) is no instant.
    unless value.encoding.ascii_compatible? && value.valid_encoding? && !value.include?("\u0000")
      raise Invalid, MESSAGE
    end

    text = value.strip
    return nil if text.empty?

    match = FORMAT.match(text)
    raise Invalid, MESSAGE unless match

    year, month, day, hour, minute = match.captures.first(5).map { |digits| digits && Integer(digits, 10) }
    raise Invalid, MESSAGE unless Date.valid_date?(year, month, day)
    return Time.utc(year, month, day) unless hour

    second = Integer(match[6] || "0", 10) + (match[7] ? Rational(Integer(match[7], 10), 10**match[7].length) : 0)
    offset = match[8]
    return Time.utc(year, month, day, hour, minute, second) if offset == "Z"
    return Time.new(year, month, day, hour, minute, second, offset).getutc if offset

    local(Time.utc(year, month, day, hour, minute, second), zone)
  end

  # wall: a Time whose fields are the wall clock in zone.
  def local(wall, zone)
    # UTC by its identifier, not by the zone data: a system's data can be
    # wrong (the dev container maps Etc/UTC to Berlin).
    return wall if zone.nil? || UTC_ZONES.include?(zone.respond_to?(:tzinfo) ? zone.tzinfo.identifier : zone)

    # dst nil: the repeated autumn hour is refused, whatever
    # TZInfo::Timezone.default_dst says.
    tzinfo(zone).local_to_utc(wall, nil)
  rescue TZInfo::PeriodNotFound
    raise Invalid, "not an instant: this local time does not exist in the zone named; write it with its offset"
  rescue TZInfo::AmbiguousTime
    raise Invalid, "not an instant: this local time exists twice in the zone named; write it with its offset"
  end

  def tzinfo(zone)
    return zone.tzinfo if zone.respond_to?(:tzinfo)
    raise ArgumentError, "the zone is not a time zone" unless zone.is_a?(String)

    TZInfo::Timezone.get(zone)
  rescue TZInfo::InvalidTimezoneIdentifier
    raise ArgumentError, "the zone is not a known time zone"
  end
end
