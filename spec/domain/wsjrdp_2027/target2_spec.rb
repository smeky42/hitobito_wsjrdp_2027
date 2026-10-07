# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Wsjrdp2027::Target2 do
  # Gauss's Easter algorithm for the Gregorian calendar, with its two
  # exceptions -- a second, independent way to the date.
  def gauss_easter(year)
    a = year % 19
    b = year % 4
    c = year % 7
    k = year / 100
    p = (13 + 8 * k) / 25
    q = k / 4
    m = (15 - p + k - q) % 30
    n = (4 + k - q) % 7
    d = (19 * a + m) % 30
    e = (2 * b + 4 * c + 6 * d + n) % 7
    # Easter is the (22 + d + e)th of March, counted on into April.
    days_after_march_22 = d + e
    days_after_march_22 = 28 if d == 29 && e == 6
    days_after_march_22 = 27 if d == 28 && e == 6 && (11 * m + 11) % 30 < 19
    Date.new(year, 3, 22) + days_after_march_22
  end

  it "computes Easter Sunday like Gauss's algorithm, 2020 to 2040" do
    (2020..2040).each do |year|
      expect(described_class.easter_sunday(year)).to eq(gauss_easter(year)), "Easter #{year}"
    end
  end

  it "knows the Easter Sundays of the contingent's years" do
    expect(described_class.easter_sunday(2025)).to eq Date.new(2025, 4, 20)
    expect(described_class.easter_sunday(2026)).to eq Date.new(2026, 4, 5)
    expect(described_class.easter_sunday(2027)).to eq Date.new(2027, 3, 28)
  end

  it "closes on weekends and the six TARGET holidays" do
    expect(described_class.closing_days(2026)).to eq [Date.new(2026, 1, 1), Date.new(2026, 4, 3), Date.new(2026, 4, 6),
      Date.new(2026, 5, 1), Date.new(2026, 12, 25), Date.new(2026, 12, 26)]
    expect(described_class).to be_closing_day(Date.new(2026, 4, 3))
    expect(described_class).to be_closing_day(Date.new(2026, 4, 4))
    expect(described_class).to be_bank_day(Date.new(2026, 4, 7))
    expect(described_class).to be_bank_day(Date.new(2026, 10, 8))
    expect(described_class).not_to be_bank_day(Date.new(2026, 10, 3))
  end

  it "finds the bank day on, or after, a date -- the collection days of 2026" do
    expect(described_class.bank_day_on_or_after(Date.new(2026, 3, 5))).to eq Date.new(2026, 3, 5)
    expect(described_class.bank_day_on_or_after(Date.new(2026, 4, 5))).to eq Date.new(2026, 4, 7)
    expect(described_class.bank_day_on_or_after(Date.new(2026, 7, 5))).to eq Date.new(2026, 7, 6)
    expect(described_class.bank_day_on_or_after(Date.new(2026, 9, 5))).to eq Date.new(2026, 9, 7)
    expect(described_class.bank_day_after(Date.new(2026, 4, 2))).to eq Date.new(2026, 4, 7)
  end

  it "counts the bank days of a month" do
    expect(described_class.nth_bank_day_of_month(2026, 11, 2)).to eq Date.new(2026, 11, 3)
    expect(described_class.nth_bank_day_of_month(2026, 1, 2)).to eq Date.new(2026, 1, 5)
    expect(described_class.nth_bank_day_of_month(2026, 10, 1)).to eq Date.new(2026, 10, 1)
    expect(described_class.nth_bank_day_of_month(2027, 1, 2)).to eq Date.new(2027, 1, 5)
  end
end
