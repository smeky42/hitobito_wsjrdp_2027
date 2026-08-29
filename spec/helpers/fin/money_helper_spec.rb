# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# THE money format of the Finanzen lists (Fin::MoneyHelper): the symbol per
# currency and the one string every money column of a list renders. This is the
# spec that pins the non-breaking space between number and symbol; the specs of
# the lists themselves squish it away and read the plain space.
#
# All amounts here are invented.
describe Fin::MoneyHelper do
  describe "the symbol of a currency" do
    it "gives the euro and the złoty theirs" do
      expect(helper.fin_currency_symbol("EUR")).to eq("€")
      expect(helper.fin_currency_symbol("PLN")).to eq("zł")
    end

    # Three letters say more than a symbol nobody recognises.
    it "leaves a currency without a symbol at its code" do
      expect(helper.fin_currency_symbol("CHF")).to eq("CHF")
    end

    # ContractHelper#format_cents_de reads the same map from a model, where a
    # view helper is not available.
    it "answers as a module function too" do
      expect(Fin::MoneyHelper.currency_symbol("EUR")).to eq("€")
      expect(Fin::MoneyHelper.currency_symbol("CHF")).to eq("CHF")
    end
  end

  describe "an amount" do
    # Number and symbol belong together and must not be split across a line
    # break.
    it "joins the German number and the symbol with a non-breaking space" do
      expect(helper.fin_money(-1234.56)).to eq("-1.234,56\u00A0€")
    end

    it "keeps two decimals and the thousands separator" do
      expect(helper.fin_money(2700)).to eq("2.700,00\u00A0€")
      expect(helper.fin_money(0)).to eq("0,00\u00A0€")
    end

    it "wears the symbol of the currency it is given" do
      expect(helper.fin_money(2700, "PLN")).to eq("2.700,00\u00A0zł")
      expect(helper.fin_money(2700, "CHF")).to eq("2.700,00\u00A0CHF")
    end

    # The places whose column header already names the currency.
    it "shows the bare number without a currency" do
      expect(helper.fin_money(12.3, nil)).to eq("12,30")
    end

    it "has nothing to show for a blank amount" do
      expect(helper.fin_money(nil)).to be_nil
      expect(helper.fin_money("")).to be_nil
    end
  end
end
