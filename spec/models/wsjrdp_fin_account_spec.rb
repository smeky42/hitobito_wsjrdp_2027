# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe WsjrdpFinAccount do
  def account(**attrs)
    described_class.new(short_name: "Konto", account_identification: "TEST-#{SecureRandom.hex(4)}",
      opening_balance_cents: 0, opening_balance_currency: "EUR", opening_balance_date: Date.new(2026, 1, 1), **attrs)
  end

  describe "IBAN and BIC" do
    it "are stored without spaces and in upper case" do
      acc = account(iban: " de02 1203 0000 0000 2020 51 ", top_up_iban: "de16 1001 0010 1111 1111 11",
        servicer_bic: "byla dem1 001", top_up_bic: "test deff xxx")

      expect(acc).to have_attributes(iban: "DE02120300000000202051", top_up_iban: "DE16100100101111111111",
        servicer_bic: "BYLADEM1001", top_up_bic: "TESTDEFFXXX")
      expect(acc).to be_valid
    end

    it "store a blank value as nil" do
      expect(account(iban: "  ", top_up_bic: "")).to have_attributes(iban: nil, top_up_bic: nil)
    end

    it "reject an IBAN with a wrong check digit, in either field" do
      acc = account(iban: "DE03120300000000202051", top_up_iban: "DE17100100101111111111")

      expect(acc).not_to be_valid
      expect(acc.errors.attribute_names).to contain_exactly(:iban, :top_up_iban)
    end
  end

  describe "#status_display" do
    it "translates the stored status and falls back to it" do
      expect(account(status: "active").status_display).to eq("aktiv")
      expect(account(status: "unknown_value").status_display).to eq("unknown_value")
    end
  end
end
