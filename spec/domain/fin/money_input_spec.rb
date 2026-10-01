# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The German amount of a money input: the text it shows and the decimal a typed
# text stands for. Invented amounts.
describe Fin::MoneyInput do
  describe ".normalize" do
    it "reads German amounts, with and without thousands points" do
      expect(described_class.normalize("1.234,56")).to eq("1234.56")
      expect(described_class.normalize("2.653.000,00")).to eq("2653000.00")
      expect(described_class.normalize("1234,5")).to eq("1234.5")
      expect(described_class.normalize("1234")).to eq("1234")
      expect(described_class.normalize("-1.234,56")).to eq("-1234.56")
      expect(described_class.normalize("100,125")).to eq("100.125")
    end

    it "reads a point between groups of three digits as thousands points" do
      expect(described_class.normalize("1.500")).to eq("1500")
      expect(described_class.normalize("12.345.678")).to eq("12345678")
    end

    it "keeps a decimal point before one or two digits, which cannot group thousands" do
      expect(described_class.normalize("1234.5")).to eq("1234.5")
      expect(described_class.normalize("1234.56")).to eq("1234.56")
    end

    it "drops spaces and a trailing euro sign" do
      expect(described_class.normalize(" 1.234,56 € ")).to eq("1234.56")
      expect(described_class.normalize("1.234,56 €")).to eq("1234.56")
    end

    it "makes a blank text blank" do
      expect(described_class.normalize("")).to eq("")
      expect(described_class.normalize("   ")).to eq("")
    end

    it "returns what it cannot read unambiguously as typed" do
      ["1,234.56", "1.2345", "12.34.567", "1234.567", "1,2345", "1.2.3", "abc", "12 €x"].each do |text|
        expect(described_class.normalize(text)).to eq(text), text
      end
    end

    it "passes anything but a String through" do
      expect(described_class.normalize(nil)).to be_nil
      expect(described_class.normalize(BigDecimal("12.5"))).to eq(BigDecimal("12.5"))
      expect(described_class.normalize(7)).to eq(7)
    end
  end

  describe ".format" do
    it "shows thousands points and two decimals" do
      expect(described_class.format(BigDecimal(19173))).to eq("19.173,00")
      expect(described_class.format(BigDecimal("454380.24"))).to eq("454.380,24")
      expect(described_class.format(BigDecimal("6887.7"))).to eq("6.887,70")
      expect(described_class.format(BigDecimal("-1234.5"))).to eq("-1.234,50")
      expect(described_class.format(250)).to eq("250,00")
    end

    it "shows a third decimal that is not zero, so saving never rounds" do
      expect(described_class.format(BigDecimal("100.125"))).to eq("100,125")
      expect(described_class.format(BigDecimal("100.120"))).to eq("100,12")
    end

    it "shows nothing for nil" do
      expect(described_class.format(nil)).to be_nil
    end

    it "gives back what .normalize reads as the same amount" do
      ["19173", "454380.24", "100.125", "-1234.5"].each do |amount|
        decimal = BigDecimal(amount)
        expect(BigDecimal(described_class.normalize(described_class.format(decimal)))).to eq(decimal)
      end
    end
  end
end
