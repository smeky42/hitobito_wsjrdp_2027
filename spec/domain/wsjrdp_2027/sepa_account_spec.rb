# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# How the bank details read where they are typed into a bank form or into
# Moss. The address they were given with is one line and has to be taken
# apart; everything else is stored ready to use.
describe Wsjrdp2027::SepaAccount do
  let(:person) { people(:yp_a_1) }

  describe "the account" do
    it "writes the IBAN without its grouping spaces" do
      person.sepa_iban = "de02 1203 0000 0000 2020 51"

      expect(described_class.iban(person)).to eq("DE02120300000000202051")
      expect(described_class.bank_country_code(person)).to eq("DE")
    end

    it "answers empty where nothing is stored" do
      expect(described_class.iban(person)).to eq("")
      expect(described_class.bank_country_code(person)).to eq("")
      expect(described_class.account_holder(person)).to eq("")
      expect(described_class.bic(person)).to eq("")
    end

    it "writes the BIC in one piece and in capitals" do
      person.sepa_bic = " genode61 abc "

      expect(described_class.bic(person)).to eq("GENODE61ABC")
    end
  end

  def parts_of(line)
    person.sepa_address = line
    [described_class.street_and_number(person),
      described_class.zip_code(person),
      described_class.town(person)]
  end

  def notes_of(line)
    person.sepa_address = line
    described_class.address_notes(person)
  end

  def country_of(line)
    person.sepa_address = line
    described_class.address_country_code(person)
  end

  describe "the address line" do
    it "splits street, zip code and town at the comma" do
      expect(parts_of("Musterweg 1a, 12345 Musterstadt"))
        .to eq(["Musterweg 1a", "12345", "Musterstadt"])
    end

    it "takes a four-digit zip code as well" do
      expect(parts_of("Musterweg 1a, 1234 Musterstadt"))
        .to eq(["Musterweg 1a", "1234", "Musterstadt"])
    end

    # A street may carry a comma, a zip code and a town may not -- so the LAST
    # comma is the one that separates the two halves.
    it "splits at the last comma" do
      expect(parts_of("Musterweg 1a, Hinterhaus, 12345 Musterstadt"))
        .to eq(["Musterweg 1a, Hinterhaus", "12345", "Musterstadt"])
    end

    it "reads a line without a comma as the street alone" do
      expect(parts_of("Musterweg 1a")).to eq(["Musterweg 1a", "", ""])
    end

    it "leaves the zip code empty where the second half starts with no digits" do
      expect(parts_of("Musterweg 1a, Musterstadt"))
        .to eq(["Musterweg 1a", "", "Musterstadt"])
    end

    it "squishes what it finds" do
      expect(parts_of("  Musterweg   1a ,  12345   Muster   stadt  "))
        .to eq(["Musterweg 1a", "12345", "Muster stadt"])
    end

    it "answers empty for a missing line" do
      expect(parts_of(nil)).to eq(["", "", ""])
      expect(parts_of("   ")).to eq(["", "", ""])
    end
  end

  # These addresses name a country only where it is not the usual one: behind
  # the last comma, or as the prefix of the zip code.
  describe "the country of the address" do
    it "says nothing about a plain German address" do
      expect(country_of("Musterweg 1a, 12345 Musterstadt")).to be_nil
    end

    it "reads the country named behind the last comma, and drops it from the address" do
      expect(country_of("Musterweg 1, 8000 Musterort, Schweiz")).to eq("CH")
      expect(parts_of("Musterweg 1, 8000 Musterort, Schweiz"))
        .to eq(["Musterweg 1", "8000", "Musterort"])
    end

    it "takes a bare ISO code there as well" do
      expect(country_of("Musterweg 1, 1234 Musterort, LU")).to eq("LU")
      expect(parts_of("Musterweg 1, 1234 Musterort, LU"))
        .to eq(["Musterweg 1", "1234", "Musterort"])
    end

    it "keeps a leading name part where the country is named" do
      expect(country_of("Name, Musterweg 9, 12345 Musterstadt, Germany")).to eq("DE")
      expect(parts_of("Name, Musterweg 9, 12345 Musterstadt, Germany"))
        .to eq(["Name, Musterweg 9", "12345", "Musterstadt"])
    end

    it "reads the old-style prefix of the zip code, and strips it" do
      expect(country_of("Musterweg 1, A-1010 Musterort")).to eq("AT")
      expect(parts_of("Musterweg 1, A-1010 Musterort"))
        .to eq(["Musterweg 1", "1010", "Musterort"])
      expect(country_of("Musterweg 1, AT-1010 Musterort")).to eq("AT")
      expect(country_of("Musterweg 1, D-12345 Musterstadt")).to eq("DE")
    end

    # A short zip code says nothing -- German ones used to be four digits too.
    it "is no indicator on its own that the zip code is four digits" do
      expect(country_of("Musterweg 1, 1234 Musterort")).to be_nil
    end

    it "says nothing for a word it does not know" do
      expect(country_of("Musterweg 1, 12345 Musterstadt, Atlantis")).to be_nil
    end

    # An unknown last part is not taken off -- it stays with the town, behind
    # the part that carries the zip code.
    it "leaves an unknown last part with the town" do
      expect(parts_of("Musterweg 1, 12345 Musterstadt, Atlantis"))
        .to eq(["Musterweg 1", "12345", "Musterstadt, Atlantis"])
    end

    it "says nothing without an address" do
      expect(country_of(nil)).to be_nil
    end

    # A four-digit zip code says nothing on its own, but an account held
    # abroad together with one does.
    it "takes the country from a foreign IBAN where the zip is four digits" do
      person.sepa_iban = "AT483200000012345864"

      expect(country_of("Musterweg 1, 1234 Musterort")).to eq("AT")
      expect(notes_of("Musterweg 1, 1234 Musterort")).to eq([:country_from_iban])
    end

    it "leaves it alone with a German IBAN" do
      person.sepa_iban = "DE02120300000000202051"

      expect(country_of("Musterweg 1, 1234 Musterort")).to be_nil
      expect(notes_of("Musterweg 1, 1234 Musterort")).to eq([])
    end

    it "leaves a five-digit zip alone whatever the IBAN says" do
      person.sepa_iban = "AT483200000012345864"

      expect(country_of("Musterweg 1, 12345 Musterort")).to be_nil
    end
  end

  # What the line needed to be read. Anything in here is a reason to look at
  # the address itself before the money goes out.
  describe "the notes" do
    it "is empty for the plain form" do
      expect(notes_of("Musterweg 1a, 12345 Musterstadt")).to eq([])
      expect(parts_of("Musterweg 1a, 12345 Musterstadt"))
        .to eq(["Musterweg 1a", "12345", "Musterstadt"])
    end

    it "splits a line that never got a comma" do
      expect(parts_of("Musterweg 12 12345 Musterstadt"))
        .to eq(["Musterweg 12", "12345", "Musterstadt"])
      expect(notes_of("Musterweg 12 12345 Musterstadt")).to eq([:split_without_comma])
    end

    it "keeps a house number out of that split" do
      expect(parts_of("Musterweg 12a 12345 Musterstadt"))
        .to eq(["Musterweg 12a", "12345", "Musterstadt"])
    end

    it "keeps a part behind the town with the town" do
      expect(parts_of("Musterweg 9, 12345 Musterstadt, Musterteil"))
        .to eq(["Musterweg 9", "12345", "Musterstadt, Musterteil"])
      expect(notes_of("Musterweg 9, 12345 Musterstadt, Musterteil"))
        .to eq([:extra_parts_after_zip])
    end

    it "reads a part that is the zip code alone" do
      expect(parts_of("Musterweg 9, 12345, Musterteil"))
        .to eq(["Musterweg 9", "12345", "Musterteil"])
      expect(notes_of("Musterweg 9, 12345, Musterteil")).to eq([:extra_parts_after_zip])
    end

    it "reads a semicolon as the comma it stands for" do
      expect(parts_of("Musterweg 9; 12345 Musterstadt, Deutschland"))
        .to eq(["Musterweg 9", "12345", "Musterstadt"])
      expect(country_of("Musterweg 9; 12345 Musterstadt, Deutschland")).to eq("DE")
      expect(notes_of("Musterweg 9; 12345 Musterstadt, Deutschland")).to include(:semicolon)
    end

    it "says so where zip or town are missing" do
      expect(notes_of("Musterweg 12")).to eq([:incomplete])
      expect(notes_of("Musterweg 1, Musterstadt")).to eq([:incomplete])
    end

    it "says nothing without an address" do
      expect(notes_of(nil)).to eq([])
    end
  end
end
