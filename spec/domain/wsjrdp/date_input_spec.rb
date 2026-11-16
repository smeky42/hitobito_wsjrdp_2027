# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Deliberately standalone (no rails spec_helper): Wsjrdp::DateInput is pure,
# the spec needs neither the app nor a database. Runs against any bundle with
# rspec, e.g. from the core app directory:
#
#   bundle exec rspec ../hitobito_wsjrdp_2027/spec/domain/wsjrdp/date_input_spec.rb
require "time"
# The file declares `module Wsjrdp::DateInput` (compact style); loading it
# without Rails needs the parent constant first.
module Wsjrdp; end
require_relative "../../../app/domain/wsjrdp/date_input"

describe Wsjrdp::DateInput do
  def parse(value) = described_class.parse(value)

  describe ".parse" do
    it "reads ISO 8601 calendar dates, leading zeros optional" do
      expect(parse("2026-10-31")).to eq(Date.new(2026, 10, 31))
      expect(parse("2026-1-5")).to eq(Date.new(2026, 1, 5))
    end

    it "reads German dates with a four-digit year, leading zeros optional" do
      expect(parse("31.10.2026")).to eq(Date.new(2026, 10, 31))
      expect(parse("01.02.2026")).to eq(Date.new(2026, 2, 1))
      expect(parse("1.2.2026")).to eq(Date.new(2026, 2, 1))
    end

    it "reads a two-digit year with the POSIX pivot" do
      expect(parse("1.2.26")).to eq(Date.new(2026, 2, 1))
      expect(parse("31.12.68")).to eq(Date.new(2068, 12, 31))
      expect(parse("1.1.69")).to eq(Date.new(1969, 1, 1))
      expect(parse("15.06.99")).to eq(Date.new(1999, 6, 15))
      expect(parse("1.1.00")).to eq(Date.new(2000, 1, 1))
    end

    it "ignores surrounding whitespace" do
      expect(parse("  31.10.2026\n")).to eq(Date.new(2026, 10, 31))
    end

    it "answers nil for blank" do
      expect(parse(nil)).to be_nil
      expect(parse("")).to be_nil
      expect(parse("   ")).to be_nil
    end

    it "takes the day of a Date or a Time as it is" do
      expect(parse(Date.new(2026, 3, 4))).to eq(Date.new(2026, 3, 4))
      expect(parse(Time.utc(2026, 3, 4, 23, 59))).to eq(Date.new(2026, 3, 4))
    end

    it "refuses fragments Date.parse would complete" do
      %w[3 1.1 1.1. 12.2026 2026 2026-10 Mai].each do |text|
        expect { parse(text) }.to raise_error(described_class::Invalid), text
      end
      expect { parse("Mai 5") }.to raise_error(described_class::Invalid)
    end

    it "refuses other spellings and noise" do
      ["31/10/2026", "2026.10.31", "31.10.2026 12:00", "31.10.202", "x31.10.2026", "2026-10-31T00:00", "kein Datum"]
        .each { |text| expect { parse(text) }.to raise_error(described_class::Invalid), text }
    end

    it "refuses days that do not exist" do
      %w[31.02.2026 29.2.2027 2026-13-01 0.1.2026 2026-04-31].each do |text|
        expect { parse(text) }.to raise_error(described_class::Invalid), text
      end
      expect(parse("29.2.2028")).to eq(Date.new(2028, 2, 29))
    end

    it "raises an ArgumentError, as Date's own parsers do" do
      expect(described_class::Invalid.ancestors).to include(ArgumentError)
    end
  end

  describe ".parse_or_nil and .valid?" do
    it "answer nil and false where parse would raise" do
      expect(described_class.parse_or_nil("31.02.2026")).to be_nil
      expect(described_class.parse_or_nil("1.2.26")).to eq(Date.new(2026, 2, 1))
      expect(described_class.valid?("1.2.26")).to be(true)
      expect(described_class.valid?("3")).to be(false)
      expect(described_class.valid?("")).to be(false)
    end
  end
end
