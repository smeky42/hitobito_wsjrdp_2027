# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Wsjrdp::CountryLookup do
  it "finds a country by our table first, then by any name of the gem, then by its code" do
    expect(described_class.find_country_by_any_name("Deutsch")).to eq("DE")
    expect(described_class.find_country_by_any_name(" us-amerikanisch ")).to eq("US")
    expect(described_class.find_country_by_any_name("Deutschland")).to eq("DE")
    expect(described_class.find_country_by_any_name("Czech Republic")).to eq("CZ")
    expect(described_class.find_country_by_any_name("at")).to eq("AT")
    expect(described_class.find_country_by_any_name("Elbisch")).to be_nil
    expect(described_class.find_country_by_any_name("")).to be_nil
  end

  it "turns the known entries of a list into codes and keeps the others" do
    expect(described_class.codes_of("Deutsch, Britisch, Deutschland, Elbisch")).to eq("DE, GB, Elbisch")
    expect(described_class.codes_of(" , ")).to be_nil
    expect(described_class.german_name("GB")).to eq("Vereinigtes Königreich")
    expect(described_class.german_name("Elbisch")).to eq("Elbisch")
  end

  it "gives the aliases a country is searched by" do
    expect(described_class.search_aliases("NL")).to include("holland", "niederländisch", "Netherlands", "NLD")
    expect(described_class.search_aliases("US")).to include("amerika", "USA")
    expect(described_class.search_aliases("Elbisch")).to eq("")
  end
end
