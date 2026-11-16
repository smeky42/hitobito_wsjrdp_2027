# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "date"

# A day as people and scripts type it, read exactly -- the one place the
# wagon turns a typed date into a Date (doc/wsjrdp/date_input.md):
#
#   Wsjrdp::DateInput.parse("2026-10-31")  # => #<Date 2026-10-31>
#   Wsjrdp::DateInput.parse("31.10.2026")  # => #<Date 2026-10-31>
#   Wsjrdp::DateInput.parse("1.2.26")      # => #<Date 2026-02-01>
#   Wsjrdp::DateInput.parse(" ")           # => nil
#   Wsjrdp::DateInput.parse("3")           # raises Wsjrdp::DateInput::Invalid
#
# Accepted, surrounding whitespace aside:
#
# - ISO 8601 as a calendar date: YYYY-MM-DD (month and day may drop their
#   leading zero, 2026-1-5);
# - German: D.M.YYYY and D.M.YY, day and month with one or two digits
#   (31.10.2026, 1.2.2026, 01.02.26). A two-digit year follows POSIX
#   (Date.strptime's %y): 69..99 are 1969..1999, 00..68 are 2000..2068.
# - a Date, or anything else that is not a String and answers to_date (a
#   Time, an ActiveSupport::TimeWithZone): its day.
#
# Nothing else is a date -- not a fragment Date.parse would complete ("3",
# "1.1", "Mai 5"), not a day that does not exist (31.02.2026). Blank (nil, "",
# whitespace) is no date at all and answers nil.
module Wsjrdp::DateInput
  # A text that is no date; an ArgumentError, like Date's own.
  class Invalid < ArgumentError; end

  ISO = /\A(\d{4})-(\d{1,2})-(\d{1,2})\z/
  GERMAN = /\A(\d{1,2})\.(\d{1,2})\.(\d{4}|\d{2})\z/
  # POSIX's pivot of a two-digit year (Date.strptime "%y").
  CENTURY_PIVOT = 69

  module_function

  # The Date the value stands for; nil for blank. Raises Invalid for
  # anything else.
  def parse(value)
    return nil if value.nil?
    return value.to_date if !value.is_a?(String) && value.respond_to?(:to_date)

    text = value.to_s.strip
    return nil if text.empty?

    year, month, day = parts(text)
    raise Invalid, "not a date: #{value.inspect}" unless year && Date.valid_date?(year, month, day)

    Date.new(year, month, day)
  end

  # As #parse, but nil for a text that is no date.
  def parse_or_nil(value)
    parse(value)
  rescue Invalid
    nil
  end

  # Whether the value reads as a date (blank does not).
  def valid?(value) = !parse_or_nil(value).nil?

  # [year, month, day] as integers, nil for a text of neither form.
  def parts(text)
    if (match = ISO.match(text))
      [match[1].to_i, match[2].to_i, match[3].to_i]
    elsif (match = GERMAN.match(text))
      [full_year(match[3]), match[2].to_i, match[1].to_i]
    end
  end

  def full_year(digits)
    year = digits.to_i
    return year if digits.length == 4

    (year >= CENTURY_PIVOT) ? 1900 + year : 2000 + year
  end
end
