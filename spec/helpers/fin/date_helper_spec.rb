# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# THE date format of the Finanzen pages (Fin::DateHelper): the notation every
# date cell and every date on an overview page renders, and the two ways of
# saying "there is no date" -- nil for a table cell, whose widget renders the
# blank, and the em dash for a text that has to write it itself.
#
# All dates here are invented.
describe Fin::DateHelper do
  let(:date) { Date.new(2026, 3, 7) }

  let(:time) { Time.zone.local(2026, 3, 7, 9, 5) }

  describe "a date" do
    # Day, month, year, each part padded -- the German notation, and the only
    # one the finance pages show.
    it "reads day.month.year with leading zeroes" do
      expect(helper.fin_date(date)).to eq("07.03.2026")
      expect(helper.fin_date(Date.new(2026, 12, 24))).to eq("24.12.2026")
    end

    # A Time answers the same format: the day of a timestamp, without its time.
    it "shows the day of a timestamp too" do
      expect(helper.fin_date(time)).to eq("07.03.2026")
    end

    # A table cell hands the nil on; the widget renders the empty cell.
    it "stays nil where there is no date" do
      expect(helper.fin_date(nil)).to be_nil
    end
  end

  describe "a date with its time" do
    it "appends hours and minutes to the date" do
      expect(helper.fin_date_time(time)).to eq("07.03.2026 09:05")
    end

    it "stays nil where there is no timestamp" do
      expect(helper.fin_date_time(nil)).to be_nil
    end
  end

  describe "the em-dash variants" do
    # Same string as the plain variant as long as there is a date ...
    it "renders a present date exactly like the plain variant" do
      expect(helper.fin_date_or_dash(date)).to eq(helper.fin_date(date))
      expect(helper.fin_date_time_or_dash(time)).to eq(helper.fin_date_time(time))
    end

    # ... and the em dash (not a hyphen) where there is none.
    it "writes the em dash where there is none" do
      expect(helper.fin_date_or_dash(nil)).to eq("—")
      expect(helper.fin_date_time_or_dash(nil)).to eq("—")
      expect(Fin::DateHelper::FIN_BLANK_DATE).to eq("—")
    end
  end

  # The format is a single constant; the timestamp format builds on it, so a
  # change to the date notation carries over to both.
  it "derives the timestamp format from the date format" do
    expect(Fin::DateHelper::FIN_DATE_FORMAT).to eq("%d.%m.%Y")
    expect(Fin::DateHelper::FIN_DATE_TIME_FORMAT)
      .to eq("#{Fin::DateHelper::FIN_DATE_FORMAT} %H:%M")
  end
end
