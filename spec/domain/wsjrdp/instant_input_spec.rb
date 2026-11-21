# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Deliberately standalone (no rails spec_helper): Wsjrdp::InstantInput is
# pure, the spec needs neither the app nor a database. From the wagon
# directory:
#
#   bundle exec rspec spec/domain/wsjrdp/instant_input_spec.rb
#
# The file declares `module Wsjrdp::InstantInput` (compact style); loading
# it without Rails needs the parent constant first.
module Wsjrdp; end
require_relative "../../../app/domain/wsjrdp/instant_input"
# For ActiveSupport::TimeZone, the zone a form will pass.
require "active_support"
require "active_support/time"

describe Wsjrdp::InstantInput do
  def parse(value, **options) = described_class.parse(value, **options)

  describe ".parse" do
    it "reads a date and a time in ISO 8601, with T or a space, seconds and a fraction optional" do
      expect(parse("2026-12-01T08:00")).to eq(Time.utc(2026, 12, 1, 8, 0))
      expect(parse("2026-12-01 08:00:00")).to eq(Time.utc(2026, 12, 1, 8, 0))
      expect(parse("2026-12-01T08:00:30")).to eq(Time.utc(2026, 12, 1, 8, 0, 30))
      expect(parse("2026-12-01T08:00:30.5")).to eq(Time.utc(2026, 12, 1, 8, 0, Rational(61, 2)))
      expect(parse("2026-12-01T08:00:30.123456789").nsec).to eq(123_456_789)
      expect(parse(" 2026-12-01T08:00\n")).to eq(Time.utc(2026, 12, 1, 8, 0))
    end

    it "takes Z and an offset" do
      expect(parse("2026-12-01T08:00Z")).to eq(Time.utc(2026, 12, 1, 8, 0))
      expect(parse("2026-12-01T08:00+01:00")).to eq(Time.utc(2026, 12, 1, 7, 0))
      expect(parse("2026-12-01T08:00:00.25-05:30")).to eq(Time.utc(2026, 12, 1, 13, 30, Rational(1, 4)))
      expect(parse("2026-12-01T00:30+01:00")).to eq(Time.utc(2026, 11, 30, 23, 30))
    end

    it "reads a text without a zone as UTC, unless the caller names a zone" do
      expect(parse("2026-07-01T10:00")).to eq(Time.utc(2026, 7, 1, 10, 0))
      expect(parse("2026-07-01T10:00", zone: "UTC")).to eq(Time.utc(2026, 7, 1, 10, 0))
      expect(parse("2026-07-01T10:00", zone: "Etc/Zulu")).to eq(Time.utc(2026, 7, 1, 10, 0))
      expect(parse("2026-07-01T10:00", zone: ActiveSupport::TimeZone["UTC"])).to eq(Time.utc(2026, 7, 1, 10, 0))
      expect(parse("2026-07-01T10:00", zone: "Europe/Berlin")).to eq(Time.utc(2026, 7, 1, 8, 0))
      expect(parse("2026-12-01T10:00", zone: "Europe/Berlin")).to eq(Time.utc(2026, 12, 1, 9, 0))
      expect(parse("2026-12-01T10:00", zone: "America/New_York")).to eq(Time.utc(2026, 12, 1, 15, 0))
      expect(parse("2026-12-01T10:00", zone: ActiveSupport::TimeZone["Berlin"])).to eq(Time.utc(2026, 12, 1, 9, 0))
    end

    it "keeps a stated zone over the one the caller names" do
      expect(parse("2026-07-01T10:00Z", zone: "Europe/Berlin")).to eq(Time.utc(2026, 7, 1, 10, 0))
      expect(parse("2026-07-01T10:00+03:00", zone: "Europe/Berlin")).to eq(Time.utc(2026, 7, 1, 7, 0))
    end

    it "refuses a local time that does not exist or exists twice in the zone named" do
      expect { parse("2026-03-29T02:30", zone: "Europe/Berlin") }.to raise_error(described_class::Invalid, /does not exist/)
      expect { parse("2026-10-25T02:30", zone: "Europe/Berlin") }.to raise_error(described_class::Invalid, /exists twice/)
      expect(parse("2026-10-25T02:30+02:00", zone: "Europe/Berlin")).to eq(Time.utc(2026, 10, 25, 0, 30))
    end

    it "refuses the repeated hour whatever TZInfo's default_dst says" do
      saved = TZInfo::Timezone.default_dst
      [true, false].each do |dst|
        TZInfo::Timezone.default_dst = dst
        expect { parse("2026-10-25T02:30", zone: "Europe/Berlin") }.to raise_error(described_class::Invalid, /exists twice/)
      end
    ensure
      TZInfo::Timezone.default_dst = saved
    end

    it "reads a bare date as 00:00 UTC of that day, whatever the zone" do
      expect(parse("2027-05-19")).to eq(Time.utc(2027, 5, 19))
      expect(parse("2027-05-19", zone: "Europe/Berlin")).to eq(Time.utc(2027, 5, 19))
    end

    it "takes a time object as it is, without changing it" do
      time = Time.new(2026, 12, 1, 8, 0, 0, "+01:00")
      expect(parse(time)).to eq(time)
      expect(time.utc_offset).to eq(3600)
    end

    it "answers nil for blank" do
      expect(parse(nil)).to be_nil
      expect(parse("")).to be_nil
      expect(parse("  ")).to be_nil
    end

    it "refuses everything else, without repeating it" do
      [
        "tomorrow", "now", "19.5.2027", "2027-5-19", "2027-05-19T8:00", "2027-05-19T08", "2027-05-19T08:0",
        "2027-13-01", "2027-02-30", "2027-02-29T00:00", "2027-05-19T24:00", "2027-05-19T08:60", "2027-05-19T08:00:60",
        "2027-05-19T08:00+1", "2027-05-19T08:00+0100", "2027-05-19T08:00+24:00", "2027-05-19T08:00 Z",
        "2027-05-19T08:00z", "2027-05-19t08:00", "2027-05-19T08:00:00,5", "2027-05-19T08:00:00.1234567890",
        "08:00", "20270519", "2027-05-19T08:00:00Z junk", "secret-2027-05-19", "٢027-05-19",
        "2027-05-19T08:00\u0000"
      ].each do |text|
        expect { parse(text) }.to raise_error(described_class::Invalid) { |error|
          expect(error.message).not_to include(text.strip)
        }, text
      end
    end

    it "refuses a value that is neither text nor a time, a Date included" do
      [20_270_519, 1.5, true, [], {}, :tomorrow, Date.new(2027, 5, 19)].each do |value|
        expect { parse(value) }.to raise_error(described_class::Invalid), value.inspect
      end
      expect { parse((+"2027-05-19\xFF").force_encoding("UTF-8")) }.to raise_error(described_class::Invalid)
      utf16 = "2026-12-01".encode("UTF-16LE")
      expect { parse(utf16) }.to raise_error(described_class::Invalid)
    end

    it "is an ArgumentError, with the forms it accepts in the message" do
      expect { parse("tomorrow") }.to raise_error(ArgumentError, /ISO 8601/)
    end

    it "refuses a zone that is none, as a programming error" do
      expect { parse("2026-12-01T08:00", zone: "Mars/Olympus") }.to raise_error(ArgumentError, /not a known time zone/)
      expect { parse("2026-12-01", zone: "Mars/Olympus") }.to raise_error(ArgumentError, /not a known time zone/)
      expect { parse("2026-12-01T08:00", zone: 3600) }.to raise_error(ArgumentError, /not a time zone/)
      expect { parse("2026-12-01T08:00", zone: TZInfo::Timezone.get("Europe/Berlin")) }
        .to raise_error(ArgumentError, /not a time zone/)
    end
  end
end
