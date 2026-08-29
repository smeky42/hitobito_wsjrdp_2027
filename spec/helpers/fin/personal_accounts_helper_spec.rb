# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The field formatters of the Kreditoren detail and its raw helper for the
# documented DATEV codes.
#
# The records here are unsaved wherever they can be, and every value is
# invented -- names, IBAN-like strings and numbers in this spec mean nothing.
describe Fin::PersonalAccountsHelper do
  let(:ctx) { Fin::AttrFormatContext.regular }

  def account(**attrs) = WsjrdpPersonalAccount.new(number: "700000", **attrs)

  # The tinted status word of the summary lists (Fin::BookkeepingHelper
  # #moss_status_cell): the word says it, the class tints it.
  describe "the Moss status" do
    def status_span(**attrs)
      html = helper.fin_format_wsjrdp_personal_account_moss_status(account(**attrs))
      Nokogiri::HTML.fragment(html).at_css("span.moss-status")
    end

    it "renders the tinted status word" do
      span = status_span(moss_status: "active")
      expect(span.text).to eq("aktiv")
      expect(span["class"].split).to contain_exactly("moss-status", "moss-status-active")
    end

    it "counts an account Moss does not know as inaktiv" do
      span = status_span
      expect(span.text).to eq("inaktiv")
      expect(span["class"].split).to contain_exactly("moss-status", "moss-status-inactive")
    end
  end

  describe "the address" do
    def address(**attrs) = helper.fin_format_wsjrdp_personal_account_address(account(**attrs))

    it "puts the whole Rechnungsadresse on one line" do
      expect(address(street: "Teststraße 1", address_second_line: "Hinterhaus",
        post_code: "12345", city: "Teststadt", country: "DE"))
        .to eq("Teststraße 1, Hinterhaus, 12345 Teststadt, DE")
    end

    it "leaves no separator behind for a part the record does not carry" do
      expect(address(street: "Teststraße 1", post_code: "12345", city: "Teststadt"))
        .to eq("Teststraße 1, 12345 Teststadt")
      expect(address(post_code: "12345", city: "Teststadt", country: "DE"))
        .to eq("12345 Teststadt, DE")
      expect(address(city: "Teststadt")).to eq("Teststadt")
      expect(address(post_code: "12345")).to eq("12345")
    end

    it "is blank without a single part" do
      expect(address).to be_nil
    end
  end

  describe "the IBAN" do
    def iban(value) = helper.fin_format_wsjrdp_personal_account_iban(account(iban: value))

    it "groups it in blocks of four" do
      expect(iban("XX11TEST0000000000")).to eq("XX11 TEST 0000 0000 00")
    end

    it "regroups a string that already carries spaces" do
      expect(iban("XX11 TEST00 0000000000")).to eq("XX11 TEST 0000 0000 0000")
    end

    it "stays blank without an IBAN" do
      expect(iban(nil)).to be_nil
      expect(iban("")).to be_nil
    end
  end

  describe "the represented person" do
    it "hands the person to the finance association link" do
      person = Person.new(first_name: "Test", last_name: "Person")
      record = account(represented_person: person)
      expect(helper).to receive(:assoc_link_with_newtab).with(person).and_return("LINK")

      expect(helper.fin_format_wsjrdp_personal_account_represented_person(record)).to eq("LINK")
    end

    it "is blank for an account that stands for nobody" do
      expect(helper.fin_format_wsjrdp_personal_account_represented_person(account)).to be_nil
    end
  end

  describe "the DATEV defaults" do
    before do
      WsjrdpLedgerAccount.create!(number: "66500", name: "Testaufwand")
      WsjrdpCostCenter.create!(number: "1000", name: "Testkostenstelle")
    end

    it "shows the standard ledger account as code and name" do
      value = helper.fin_format_wsjrdp_personal_account_moss_default_ledger_account_number(
        account(moss_default_ledger_account_number: "66500")
      )
      expect(Nokogiri::HTML.fragment(value).text).to eq("66500 Testaufwand")
    end

    it "shows the standard cost center as code and name" do
      value = helper.fin_format_wsjrdp_personal_account_moss_default_cost_center_number(
        account(moss_default_cost_center_number: "1000")
      )
      expect(Nokogiri::HTML.fragment(value).text).to eq("1000 Testkostenstelle")
    end

    it "keeps the bare code when no record carries that number" do
      expect(helper.fin_format_wsjrdp_personal_account_moss_default_cost_center_number(
        account(moss_default_cost_center_number: "9999")
      )).to eq("9999")
    end

    it "is blank without a default" do
      expect(helper.fin_format_wsjrdp_personal_account_moss_default_ledger_account_number(account))
        .to be_nil
      expect(helper.fin_format_wsjrdp_personal_account_moss_default_cost_center_number(account))
        .to be_nil
    end
  end

  # Two fields of the detail have no formatter of their own: the type rules of
  # Fin::AttrFormatHelper already answer for them. What the partial gets is
  # asserted through the lookup, not through a method of this module.
  describe "the fields the type rules answer for" do
    def value_of(attr, **attrs) = helper.fin_format_attr(account(**attrs), attr, ctx)

    it "lists the aliases one after the other" do
      expect(value_of(:aliases, aliases: ["Erster Alias", "Zweiter Alias"]).value)
        .to eq("Erster Alias, Zweiter Alias")
    end

    it "leaves an account without a single alias blank" do
      expect(value_of(:aliases, aliases: [])).to be_blank_value
      expect(value_of(:aliases, aliases: [""])).to be_blank_value
    end

    it "shows the sphere by its number" do
      expect(value_of(:moss_default_sphere_number, moss_default_sphere_number: "3").value)
        .to eq("3")
    end
  end

  describe "the raw DATEV codes" do
    let(:datev_ctx) { ctx.with_raw_source(:other_datev_columns) }
    let(:moss_ctx) { ctx.with_raw_source(:other_moss_columns) }

    let(:record) do
      account(other_datev_columns: {"Adressattyp" => "2", "Zahlungsträger" => "7",
                                    "Kurzbezeichnung" => "TESTKRED"},
        other_moss_columns: {"Adressattyp" => "2"})
    end

    def raw(key, context = datev_ctx)
      helper.fin_raw_format_other_wsjrdp_personal_account(record, key, context)
    end

    it "names the Adressattyp behind its code" do
      expect(raw("Adressattyp")).to eq("2 Unternehmen")
    end

    it "names the Zahlungsträger behind its code" do
      expect(raw("Zahlungsträger")).to eq("7 SEPA-Überweisung mit einer Rechnung")
    end

    it "leaves a code outside the table to the default formatting" do
      other = account(other_datev_columns: {"Adressattyp" => "5", "Zahlungsträger" => ""})
      expect(helper.fin_raw_format_other_wsjrdp_personal_account(other, "Adressattyp", datev_ctx))
        .to be_nil
      expect(helper.fin_raw_format_other_wsjrdp_personal_account(other, "Zahlungsträger",
        datev_ctx)).to be_nil
    end

    it "leaves every other DATEV key to the default formatting" do
      expect(raw("Kurzbezeichnung")).to be_nil
    end

    it "does not answer for the Moss block, nor for an also: column" do
      expect(raw("Adressattyp", moss_ctx)).to be_nil
      expect(raw("Adressattyp", ctx)).to be_nil
    end
  end
end
