# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The German amount of a money input, both ways: the text an input shows
# (`.format`, "1.234,56") and the decimal a typed text stands for
# (`.normalize`). The detail kit's amount input (Fin::DetailHelper) shows
# `.format`; the budget writers (WsjrdpBudgetable) read `.normalize`.
#
# Rails casts a decimal from text with String#to_d, which stops at the first
# character it cannot read: "1.234,56" would become 1.234. `.normalize` turns
# German text into a plain decimal first, and only text it reads unambiguously:
#
#   "1.234,56"  "1234,56"  "1.500"  -> "1234.56"  "1234.56"  "1500"
#   "1234.5"    "1234.56"           -> unchanged (a point before one or two
#                                      digits cannot group thousands)
#   " 1.234,56 €"                   -> "1234.56" (spaces and a trailing € go)
#   ""                              -> "" (blank)
#
# Anything else -- "1,234.56", "1.2345", "12.34", "abc" -- comes back unchanged,
# so the model's numericality validation reports it instead of a guess being
# stored. At most three decimals, the scale of the money columns.
module Fin::MoneyInput
  GROUPED = /\A([+-]?)(\d{1,3}(?:\.\d{3})+)(?:,(\d{1,3}))?\z/
  DECIMAL_COMMA = /\A([+-]?)(\d+)(?:,(\d{1,3}))?\z/
  DECIMAL_POINT = /\A([+-]?)(\d+)\.(\d{1,2})\z/

  module_function

  # The plain decimal text ("1234.56") of a German amount; "" for a blank text.
  # Anything that is not a String -- a number, nil -- passes through.
  def normalize(value)
    return value unless value.is_a?(String)

    text = value.delete("  ").delete_suffix("€")
    return "" if text.empty?

    match = GROUPED.match(text) || DECIMAL_COMMA.match(text) || DECIMAL_POINT.match(text)
    return value unless match

    sign, int, frac = match.captures
    frac ? "#{sign}#{int.delete(".")}.#{frac}" : "#{sign}#{int.delete(".")}"
  end

  # The amount as a money input shows it, in the number format of #fin_money
  # (Fin::MoneyHelper) without the symbol: thousands points and two decimals
  # ("1.234,50"), three where the third is not zero, so saving the form again
  # never rounds a stored value. nil for nil.
  def format(amount)
    return nil if amount.nil?

    decimal = amount.to_d
    precision = (decimal * 100).frac.zero? ? 2 : 3
    ActiveSupport::NumberHelper.number_to_currency(decimal, format: "%n", separator: ",",
      delimiter: ".", precision: precision)
  end
end
