# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# THE money format of the Finanzen lists: the German-formatted number and the
# symbol of its currency, joined by a non-breaking space -- "-1.234,56 €",
# "2.700,00 zł". Every money column of a list goes through #fin_money (the
# Summe / Saldo cells and footers of the Buchhaltung summaries, the Betrag of
# the Buchungen, of the Moss transactions with their expense rows, and of the
# Moss wallet), so no column can drift into a format of its own.
#
# A currency without a symbol keeps its ISO code: three letters say more than a
# symbol nobody recognises.
module Fin::MoneyHelper
  # Symbol per ISO 4217 code -- the currencies that appear in our data.
  CURRENCY_SYMBOLS = {"EUR" => "€", "PLN" => "zł"}.freeze

  # Number and symbol belong together and must not be split across a line
  # break, so what joins them is a non-breaking space.
  NBSP = "\u00A0"

  # The symbol of a currency code, the code itself when there is none. A module
  # function as well, because ContractHelper#format_cents_de reads the same map
  # and is included in models, where a view helper is not available.
  def self.currency_symbol(code) = CURRENCY_SYMBOLS.fetch(code, code)

  def fin_currency_symbol(code) = Fin::MoneyHelper.currency_symbol(code)

  # "1.234,56 €" -- nil for a blank amount, and the bare number for a blank
  # currency (the places that show what the column header already names).
  def fin_money(amount, currency = "EUR")
    return nil if amount.blank?

    number = number_to_currency(amount, separator: ",", delimiter: ".", format: "%n")
    symbol = fin_currency_symbol(currency)
    symbol.present? ? "#{number}#{NBSP}#{symbol}" : number
  end
end
