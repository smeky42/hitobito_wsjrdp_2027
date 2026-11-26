# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "bigdecimal"

# An installment plan: a starting year, the amount of each month from its
# January (BigDecimal) and their currency, EUR unless given. Stored as cents in
# fee rules, and as raw euros [starting year, euros per month from January] in
# people and standard plans. Raw euros may hold a fraction of a cent; it is
# kept, not rounded. A missing amount or year raises ArgumentError.
#
# As text: "2026-12: 500; 100; 100". Elements are separated by ";".
# "YYYY: amount" or "YYYY-M: amount" sets the month, an amount alone takes the
# next month, an empty element is skipped.
class Wsjrdp2027::InstallmentPlan < Data.define(:starting_year, :amounts, :currency)
  # Made only through the from_* methods.
  private_class_method :new, :[], :allocate
  private :with

  # A text that is not a plan, with a message for the person typing.
  class Invalid < ArgumentError; end

  DEFAULT_CURRENCY = "EUR"
  DATE = /\A(\d{4})(?:-(\d{1,2}))?\z/
  AMOUNT = /\A\d+(?:[.,]\d+)?\z/
  # What the integer columns that store the cents can hold.
  MAX_CENTS = 2_147_483_647
  LAST_MONTH = 9999 * 12 + 11

  module Months
    module_function

    def text(index) = Kernel.format("%04d-%02d", index / 12, index % 12 + 1)
  end
  private_constant :Months

  # nil without a plan.
  def self.from_cents(starting_year, cents, currency: DEFAULT_CURRENCY)
    return nil if starting_year.nil? || cents.nil?

    new(starting_year: Integer(starting_year), currency: currency,
      amounts: cents.map { |value| BigDecimal(Integer(present!(value))) / 100 }.freeze)
  end

  # nil without a plan.
  def self.from_raw_eur(raw)
    return nil if Array(raw).empty?

    year, *euros = raw
    new(starting_year: BigDecimal(present!(year).to_s).to_i, currency: "EUR",
      amounts: euros.map { |eur| BigDecimal(present!(eur).to_s) }.freeze)
  end

  # From YearMonthCents; nil for none.
  def self.from_year_month_cents(installments, currency: DEFAULT_CURRENCY)
    return nil if Array(installments).empty?

    first = installments.map { |item| item.year * 12 + item.month - 1 }.min
    starting_year = first / 12
    cents = []
    installments.each { |item| cents[item.year * 12 + item.month - 1 - starting_year * 12] = item.cents }
    from_cents(starting_year, cents.map { |value| value || 0 }, currency: currency)
  end

  # Raises Invalid.
  def self.from_text(text, currency: DEFAULT_CURRENCY)
    # Also no-break spaces, as pasted from a PDF or a spreadsheet.
    text = text.to_s.gsub(/\p{Space}/, " ")
    raise Invalid, "Ratenplan muss ausgefüllt werden" if text.strip.empty?

    months = {}
    current = nil
    text.split(";").map(&:strip).reject(&:empty?).each do |element|
      date, amount = element.include?(":") ? element.split(":", 2).map(&:strip) : [nil, element]
      if date
        target = month_index(date)
        check_order(current, target, date) if current
        current = target
      else
        raise Invalid, "Ratenplan muss mit einem Datum beginnen, z. B. „2026-03: 500“" unless current

        current += 1
        raise Invalid, "Ratenplan reicht über 9999-12 hinaus" if current > LAST_MONTH
      end
      months[current] = typed_cents(amount, element)
    end
    raise Invalid, "Ratenplan muss ausgefüllt werden" if months.empty?

    from_months(months, currency)
  end

  def self.present!(value)
    raise ArgumentError, "installment plan with a missing value" if value.nil?

    value
  end

  def self.month_index(date)
    match = DATE.match(date) or raise Invalid, "„#{date}“ ist kein Datum, erwartet z. B. „2026“ oder „2026-03“"
    month = (match[2] || 1).to_i
    raise Invalid, "„#{date}“: Monat muss zwischen 1 und 12 liegen" unless (1..12).cover?(month)
    raise Invalid, "„#{date}“: Jahr muss zwischen 1000 und 9999 liegen" if match[1].to_i < 1000

    match[1].to_i * 12 + month - 1
  end

  def self.check_order(current, target, date)
    raise Invalid, "#{Months.text(target)} kommt doppelt vor" if target == current
    raise Invalid, "„#{date}“ liegt vor #{Months.text(current)}" if target < current
  end

  def self.typed_cents(amount, element)
    raise Invalid, "„#{element}“ hat keinen Betrag" if amount.empty?
    raise Invalid, "„#{amount}“ ist kein Betrag" unless AMOUNT.match?(amount)

    value = BigDecimal(amount.tr(",", ".")) * 100
    raise Invalid, "„#{amount}“ hat Bruchteile eines Cents" unless value == value.round
    raise Invalid, "„#{amount}“ ist zu groß" if value > MAX_CENTS

    value.to_i
  end

  def self.from_months(months, currency)
    starting_year = months.keys.min / 12
    list = Array.new(months.keys.max - starting_year * 12 + 1, 0)
    months.each { |index, value| list[index - starting_year * 12] = value }
    list.pop while list.last&.zero?
    from_cents(starting_year, list, currency: currency)
  end

  private_class_method :present!, :month_index, :check_order, :typed_cents, :from_months

  # Integers; a BigDecimal where a stored amount holds a fraction of a cent.
  def cents
    amounts.map do |amount|
      value = amount * 100
      (value == value.round) ? value.to_i : value
    end
  end

  def to_raw_eur = [BigDecimal(starting_year), *euro_amounts]

  # The months with an installment, as YearMonthEur.
  def yme_list
    euro_amounts.each_with_index.filter_map do |eur, offset|
      next if eur.zero?

      index = starting_year * 12 + offset
      Wsjrdp2027::YearMonthEur.new([index / 12, index % 12 + 1], eur)
    end
  end

  def sum_cents = cents.sum

  # The short text that parses back to the same installments: a date after a
  # gap of two months or more, a single empty month as "0".
  def text
    parts = []
    previous = nil
    amounts.each_with_index do |amount, offset|
      next if amount.zero?

      index = starting_year * 12 + offset
      parts << "0" if previous && index == previous + 2
      parts << ((previous && index <= previous + 2) ? amount_text(amount) : "#{Months.text(index)}: #{amount_text(amount)}")
      previous = index
    end
    parts.empty? ? "#{starting_year}: 0" : parts.join("; ")
  end

  private

  def euro_amounts
    raise ArgumentError, "installment plan in #{currency}, not EUR" unless currency == "EUR"

    amounts
  end

  # A fraction of a cent, as stored euros may hold, is written out unrounded.
  def amount_text(amount)
    sign = amount.negative? ? "-" : ""
    amount = amount.abs
    return "#{sign}#{amount.to_i}" if amount.frac.zero?

    whole, fraction = amount.to_s("F").split(".")
    "#{sign}#{whole},#{fraction.ljust(2, "0")}"
  end
end
