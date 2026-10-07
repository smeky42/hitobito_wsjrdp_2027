# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The bank days of SEPA: the days the Eurosystem's payment system TARGET
# settles. It is closed on Saturdays and Sundays and on six holidays a year --
# New Year's Day, Good Friday, Easter Monday, Labour Day (1 May), Christmas
# Day and 26 December. A direct debit is collected and a credit transfer
# arrives on bank days only, so a due date falls on one.
module Wsjrdp2027::Target2
  module_function

  # Easter Sunday of the Gregorian calendar (the algorithm of Meeus, Jones
  # and Butcher; spec/domain/wsjrdp_2027/target2_spec.rb checks it against
  # Gauss's).
  def easter_sunday(year)
    a = year % 19
    b, c = year.divmod(100)
    d, e = b.divmod(4)
    f = (b + 8) / 25
    g = (b - f + 1) / 3
    h = (19 * a + b - d - g + 15) % 30
    i, k = c.divmod(4)
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) / 451
    month, day = (h + l - 7 * m + 114).divmod(31)
    Date.new(year, month, day + 1)
  end

  # The six closing days of a year, in order.
  def closing_days(year)
    easter = easter_sunday(year)
    [Date.new(year, 1, 1), easter - 2, easter + 1, Date.new(year, 5, 1), Date.new(year, 12, 25), Date.new(year, 12, 26)]
  end

  def closing_day?(date) = date.saturday? || date.sunday? || closing_days(date.year).include?(date)

  def bank_day?(date) = !closing_day?(date)

  # The first bank day on or after the date.
  def bank_day_on_or_after(date)
    date += 1 until bank_day?(date)
    date
  end

  # The first bank day after the date.
  def bank_day_after(date) = bank_day_on_or_after(date + 1)

  # The n-th bank day of a month (1 for the first).
  def nth_bank_day_of_month(year, month, n)
    date = bank_day_on_or_after(Date.new(year, month, 1))
    (n - 1).times { date = bank_day_after(date) }
    date
  end
end
