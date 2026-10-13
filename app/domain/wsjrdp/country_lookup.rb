# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Country names and nationalities to ISO 3166 codes (alpha-2), e.g. for the
# nationalities people typed in themselves (Person#passport_nationality):
# first our own table NAMES, which knows the German nationality adjectives the
# countries gem does not ("Deutsch", "US-Amerikanisch"), then the gem's
# ISO3166::Country.find_country_by_any_name (country names in every language
# it knows, "Deutschland", "Germany", "Allemagne"), then a code itself
# ("DE"). Case does not matter.
module Wsjrdp::CountryLookup
  extend self

  # Lower-case name => ISO code; looked up before the gem, and searched by the
  # country choice (search_aliases). Add an alias here to make it known.
  NAMES = {
    "amerika" => "US",
    "england" => "GB",
    "holland" => "NL",
    "afghanisch" => "AF",
    "ägyptisch" => "EG",
    "albanisch" => "AL",
    "algerisch" => "DZ",
    "amerikanisch" => "US",
    "argentinisch" => "AR",
    "armenisch" => "AM",
    "aserbaidschanisch" => "AZ",
    "äthiopisch" => "ET",
    "australisch" => "AU",
    "belgisch" => "BE",
    "bolivianisch" => "BO",
    "bosnisch" => "BA",
    "brasilianisch" => "BR",
    "britisch" => "GB",
    "bulgarisch" => "BG",
    "chilenisch" => "CL",
    "chinesisch" => "CN",
    "costa-ricanisch" => "CR",
    "dänisch" => "DK",
    "deutsch" => "DE",
    "dominikanisch" => "DO",
    "ecuadorianisch" => "EC",
    "englisch" => "GB",
    "estnisch" => "EE",
    "finnisch" => "FI",
    "französisch" => "FR",
    "georgisch" => "GE",
    "ghanaisch" => "GH",
    "griechisch" => "GR",
    "guatemaltekisch" => "GT",
    "honduranisch" => "HN",
    "indisch" => "IN",
    "indonesisch" => "ID",
    "irakisch" => "IQ",
    "iranisch" => "IR",
    "irisch" => "IE",
    "isländisch" => "IS",
    "israelisch" => "IL",
    "italienisch" => "IT",
    "japanisch" => "JP",
    "kanadisch" => "CA",
    "kasachisch" => "KZ",
    "kenianisch" => "KE",
    "kolumbianisch" => "CO",
    "kosovarisch" => "XK",
    "kroatisch" => "HR",
    "kubanisch" => "CU",
    "lettisch" => "LV",
    "libanesisch" => "LB",
    "liechtensteinisch" => "LI",
    "litauisch" => "LT",
    "luxemburgisch" => "LU",
    "malaysisch" => "MY",
    "maltesisch" => "MT",
    "marokkanisch" => "MA",
    "mexikanisch" => "MX",
    "moldauisch" => "MD",
    "montenegrinisch" => "ME",
    "neuseeländisch" => "NZ",
    "nicaraguanisch" => "NI",
    "niederländisch" => "NL",
    "nigerianisch" => "NG",
    "nordmazedonisch" => "MK",
    "norwegisch" => "NO",
    "österreich" => "AT",
    "österreichisch" => "AT",
    "pakistanisch" => "PK",
    "paraguayisch" => "PY",
    "peruanisch" => "PE",
    "philippinisch" => "PH",
    "polnisch" => "PL",
    "portugiesisch" => "PT",
    "rumänisch" => "RO",
    "russisch" => "RU",
    "schwedisch" => "SE",
    "schweizer" => "CH",
    "schweizerisch" => "CH",
    "serbisch" => "RS",
    "singapurisch" => "SG",
    "slowakisch" => "SK",
    "slowenisch" => "SI",
    "spanisch" => "ES",
    "südafrikanisch" => "ZA",
    "südkoreanisch" => "KR",
    "syrisch" => "SY",
    "thailändisch" => "TH",
    "tschechisch" => "CZ",
    "tunesisch" => "TN",
    "türkisch" => "TR",
    "ukrainisch" => "UA",
    "ungarisch" => "HU",
    "uruguayisch" => "UY",
    "us-amerikanisch" => "US",
    "venezolanisch" => "VE",
    "vietnamesisch" => "VN",
    "weißrussisch" => "BY",
    "belarussisch" => "BY",
    "zyprisch" => "CY",
    "dutch" => "NL"
  }.freeze

  # The countries named most often, first in the country choice, in this order.
  FREQUENT_CODES = %w[DE AT IT CH FR NL US GB].freeze

  # The ISO code of a country name, nationality or code; nil for none.
  def find_country_by_any_name(name)
    key = name.to_s.squish
    return nil if key.empty?

    NAMES[key.downcase] ||
      ISO3166::Country.find_country_by_any_name(key)&.alpha2 ||
      ISO3166::Country[key.upcase]&.alpha2
  end

  # The entries of a comma-separated list, without blanks.
  def split(list) = list.to_s.split(",").map(&:squish).reject(&:empty?)

  # The list with every entry the lookup knows as its code, the others as
  # they are, each once: "Deutsch, Elbisch" => "DE, Elbisch".
  def codes_of(list)
    split(list).map { |entry| find_country_by_any_name(entry) || entry }.uniq.join(", ").presence
  end

  # The other names a country is found by in the country choice: ours (NAMES),
  # the gem's (other languages, "USA"), its English name and alpha-3 code,
  # joined by " | " (a name may hold a space).
  def search_aliases(code)
    country = ISO3166::Country[code]
    return "" unless country

    (NAMES.select { |_name, value| value == code }.keys + Array(country.unofficial_names) +
      [country.iso_short_name, country.alpha3]).compact.uniq.join(" | ")
  end

  # Whether an entry is an ISO code (as stored after the lookup).
  def code?(entry) = entry.to_s.match?(/\A[A-Z]{2}\z/) && ISO3166::Country[entry].present?

  # The German name of a code, the entry itself for anything else.
  def german_name(entry) = code?(entry) ? ::Country.new(entry).name(:de) : entry
end
