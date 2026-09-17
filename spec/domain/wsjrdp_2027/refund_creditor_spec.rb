# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The creditor a refund is paid to, as Moss wants it typed in: the person's
# account and address, plus the master data every refund creditor gets.
describe Wsjrdp2027::RefundCreditor do
  let(:person) { people(:yp_a_1) }
  let(:creditor) { described_class.new(person.reload) }

  # Writing an address geocodes it, and a spec has no business on the network.
  before { allow(Geocoder).to receive(:search).and_return([]) }

  before do
    person.update!(sepa_name: "Kim Alex Muster-Beispiel",
      sepa_iban: "DE02 1203 0000 0000 2020 51",
      sepa_address: "Musterweg 1a, 12345 Musterstadt",
      country: "DE")
  end

  it "calls the creditor after the registration id" do
    expect(creditor.name).to eq("TN #{person.id}")
  end

  it "states the master data every refund creditor gets" do
    expect(creditor.ledger_account).to eq("41030 Teilnehmendenbeiträge")
    expect(creditor.cost_center).to eq("8010 Rückzahlung Abmeldung")
    expect(creditor.cost_center_alternative).to eq("8000 Rückzahlung")
    expect(creditor.sphere).to eq("3 Zweckbetrieb")
    expect(creditor.team).to eq("Finance")
    expect(creditor.payment_method).to eq("Banküberweisung")
    expect(creditor.moss_suppliers_url).to eq("https://getmoss.com/app/accounting/suppliers")
  end

  # The same normalization the receipt uses -- both read Wsjrdp2027::SepaAccount.
  it "writes the account the way the receipt does" do
    expect(creditor.iban).to eq("DE02120300000000202051")
    expect(creditor.account_holder).to eq("Kim Alex Muster-Beispiel")
    expect(creditor.iban).to eq(Wsjrdp2027::RefundReceipt.new(person).iban)
  end

  it "carries the BIC where one is stored" do
    expect(creditor.bic).to eq("")

    person.update!(sepa_bic: "genode61abc")

    expect(described_class.new(person.reload).bic).to eq("GENODE61ABC")
  end

  it "reads the bank's country off the IBAN and writes it out" do
    expect(creditor.bank_country).to eq("Deutschland")
  end

  it "leaves the bank's country empty without an IBAN" do
    person.update!(sepa_iban: nil)

    expect(creditor.iban).to eq("")
    expect(creditor.bank_country).to eq("")
  end

  # The country the money goes to is what the SEPA address says, and Germany
  # where it says nothing -- not the person's own country, and not the bank's.
  it "reads the country off the SEPA address, Germany by default" do
    person.update!(country: "AT")

    expect(creditor.country).to eq("Deutschland")
  end

  it "names the country the SEPA address carries" do
    person.update!(sepa_address: "Musterweg 1, 8000 Musterort, Schweiz")

    expect(creditor.country).to eq("Schweiz")
    expect(creditor.street_and_number).to eq("Musterweg 1")
    expect(creditor.zip_code).to eq("8000")
    expect(creditor.town).to eq("Musterort")
  end

  it "reads the old-style zip prefix as the country too" do
    person.update!(sepa_address: "Musterweg 1, A-1010 Musterort")

    expect(creditor.country).to eq("Österreich")
    expect(creditor.zip_code).to eq("1010")
  end

  it "stays with Germany for a four-digit zip code alone" do
    person.update!(sepa_address: "Musterweg 1, 1234 Musterort")

    expect(creditor.country).to eq("Deutschland")
  end

  it "stays with Germany without any address" do
    person.update!(sepa_address: nil)

    expect(creditor.country).to eq("Deutschland")
  end

  it "takes the country from a foreign IBAN where the zip is four digits" do
    person.update!(sepa_address: "Musterweg 1, 1234 Musterort",
      sepa_iban: "AT483200000012345864")

    expect(creditor.country).to eq("Österreich")
    expect(creditor.address_notes).to eq([:country_from_iban])
  end

  # An address the parser had to guess at is flagged on the page, with the
  # line as it was typed to check it against.
  describe "an address that needed a heuristic" do
    it "is not flagged in its plain form" do
      expect(creditor).not_to be_address_uncertain
      expect(creditor.address_notes).to eq([])
      expect(creditor.raw_address).to eq("Musterweg 1a, 12345 Musterstadt")
    end

    it "is flagged where it had to be split without a comma" do
      person.update!(sepa_address: "Musterweg 12 12345 Musterstadt")

      expect(creditor).to be_address_uncertain
      expect(creditor.address_notes).to eq([:split_without_comma])
      expect(creditor.street_and_number).to eq("Musterweg 12")
      expect(creditor.town).to eq("Musterstadt")
    end

    it "is flagged where a part hangs behind the town" do
      person.update!(sepa_address: "Musterweg 9, 12345 Musterstadt, Musterteil")

      expect(creditor.address_notes).to eq([:extra_parts_after_zip])
      expect(creditor.town).to eq("Musterstadt, Musterteil")
    end

    it "is flagged where zip and town are missing altogether" do
      person.update!(sepa_address: "Musterweg 12")

      expect(creditor.address_notes).to eq([:incomplete])
      expect(creditor.raw_address).to eq("Musterweg 12")
    end
  end

  # The address the bank details were given with, not the person's own.
  it "takes the address apart the SEPA data carries" do
    expect(creditor.street_and_number).to eq("Musterweg 1a")
    expect(creditor.zip_code).to eq("12345")
    expect(creditor.town).to eq("Musterstadt")
  end

  it "reads a line without a comma as the street alone" do
    person.update!(sepa_address: "Musterweg 1a")

    expect(creditor.street_and_number).to eq("Musterweg 1a")
    expect(creditor.zip_code).to eq("")
    expect(creditor.town).to eq("")
  end

  it "answers empty without a SEPA address" do
    person.update!(sepa_address: nil)

    expect(creditor.street_and_number).to eq("")
    expect(creditor.zip_code).to eq("")
    expect(creditor.town).to eq("")
  end
end
