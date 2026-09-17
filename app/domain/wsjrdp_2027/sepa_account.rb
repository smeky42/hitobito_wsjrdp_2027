# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # How a person's bank account is written where it is read off a page and
  # typed into online banking or Moss: the IBAN the way the SEPA exports write
  # it, without the grouping spaces, the holder as stored, and the one-line
  # address that was given with the bank details, taken apart.
  #
  # Shared by the refund receipt and the creditor section of the Abmeldung
  # page, so the two cannot drift apart.
  module SepaAccount
    module_function

    def iban(person) = person.sepa_iban.to_s.gsub(/\s+/, "").upcase

    def account_holder(person) = person.sepa_name.to_s.strip

    def bic(person) = person.sepa_bic.to_s.gsub(/\s+/, "").upcase

    # The country the account is held in: the first two letters of the IBAN.
    # Empty where there is no IBAN.
    def bank_country_code(person) = iban(person)[0, 2].to_s

    # What a zip code and a town look like at the end of the line: four or five
    # digits, then the rest -- with the old-style country prefix in front of
    # the digits where somebody still writes one ("A-1010 Wien").
    ADDRESS_TAIL = /\A(?:(?<prefix>[A-Za-z]{1,2})-)?(?<zip>\d{4,5})(?:\s+(?<town>.*))?\z/

    # What an address line can say about its country: the names people write
    # there, the bare ISO codes, and the letter codes of a zip prefix. Keys are
    # lowercase; a word that is not in here says nothing about the country.
    COUNTRIES = {
      "deutschland" => "DE", "germany" => "DE", "d" => "DE", "de" => "DE",
      "österreich" => "AT", "oesterreich" => "AT", "austria" => "AT",
      "a" => "AT", "at" => "AT",
      "schweiz" => "CH", "switzerland" => "CH", "suisse" => "CH",
      "svizzera" => "CH", "ch" => "CH",
      "niederlande" => "NL", "netherlands" => "NL", "nederland" => "NL",
      "holland" => "NL", "nl" => "NL",
      "luxemburg" => "LU", "luxembourg" => "LU", "l" => "LU", "lu" => "LU",
      "belgien" => "BE", "belgium" => "BE", "belgique" => "BE",
      "b" => "BE", "be" => "BE",
      "frankreich" => "FR", "france" => "FR", "f" => "FR", "fr" => "FR",
      "dänemark" => "DK", "daenemark" => "DK", "denmark" => "DK",
      "danmark" => "DK", "dk" => "DK",
      "polen" => "PL", "poland" => "PL", "polska" => "PL", "pl" => "PL",
      "italien" => "IT", "italy" => "IT", "italia" => "IT", "i" => "IT", "it" => "IT"
    }.freeze

    # A line that never got a comma: street, zip and town run into each other
    # ("Musterweg 12 12345 Musterstadt"). The first zip-looking number is what
    # separates them.
    ADDRESS_WITHOUT_COMMA =
      /\A(?<street>.+?)\s(?:(?<prefix>[A-Za-z]{1,2})-)?(?<zip>\d{4,5})\s+(?<town>.+)\z/

    # The address that was given with the bank details is one line, almost
    # always "<Strasse Nr>, <PLZ> <Ort>" -- but it was typed by hand, and the
    # odd forms are read as well: a semicolon instead of a comma, no comma at
    # all, and a part behind the zip and town ("..., 12345 Ort, Ortsteil").
    #
    # A country is named only where it is not the usual one, in one of three
    # ways: as the part behind the last comma, which is then no part of the
    # address any more; as the prefix of the zip code; or, for a four-digit zip
    # code alone, by an IBAN that is not a German one.
    #
    # Answers [street, zip, town, country code or nil, notes], where notes
    # lists the heuristics that had to fire -- an address with notes is worth
    # a second look.
    def parsed_address(person)
      notes = []
      line = person.sepa_address.to_s.squish
      return ["", "", "", nil, notes] if line.empty?

      if line.include?(";")
        notes << :semicolon
        line = line.tr(";", ",").squish
      end

      line, country = take_country(line)
      street, zip, town, prefix = split_address(line, notes)
      country ||= prefix || foreign_iban_country(person, zip, notes)
      notes << :incomplete if zip.empty? || town.empty?
      [street, zip, town, country, notes]
    end

    def address_parts(person) = parsed_address(person).first(3)

    def address_country_code(person) = parsed_address(person)[3]

    def address_notes(person) = parsed_address(person)[4]

    def street_and_number(person) = address_parts(person)[0]

    def zip_code(person) = address_parts(person)[1]

    def town(person) = address_parts(person)[2]

    # Which of the comma-separated parts carries the zip code: the LAST one
    # that starts with it, so a street number cannot be mistaken for it and a
    # part behind the town ("..., Ortsteil") stays with the town. Without such
    # a part the last comma separates street from town, as before.
    def split_address(line, notes)
      parts = line.split(",").map(&:squish).reject(&:empty?)
      return split_without_comma(line, notes) if parts.size <= 1

      index = parts.rindex { |part| ADDRESS_TAIL.match?(part) }
      return [parts[0..-2].join(", "), "", parts.last, nil] if index.nil?

      match = ADDRESS_TAIL.match(parts[index])
      trailing = parts[(index + 1)..]
      notes << :extra_parts_after_zip if trailing.any?
      town = [match[:town].to_s.squish, *trailing].reject(&:empty?).join(", ")
      [parts[0...index].join(", "), match[:zip], town, prefix_country(match[:prefix])]
    end

    def split_without_comma(line, notes)
      match = ADDRESS_WITHOUT_COMMA.match(line)
      return [line, "", "", nil] unless match

      notes << :split_without_comma
      [match[:street].squish, match[:zip], match[:town].squish, prefix_country(match[:prefix])]
    end

    def prefix_country(prefix) = prefix && COUNTRIES[prefix.downcase]

    # A four-digit zip code says nothing on its own -- German ones used to be
    # four digits too. Together with an account held abroad it does.
    def foreign_iban_country(person, zip, notes)
      return nil unless zip.length == 4

      code = bank_country_code(person)
      return nil if code.empty? || code == "DE"

      notes << :country_from_iban
      code
    end

    # The line with its trailing country taken off, and that country. A single
    # letter is no country here -- only a name or a bare ISO code is, while the
    # zip prefix accepts the letter codes too.
    def take_country(line)
      head, comma, tail = line.rpartition(",")
      return [line, nil] if comma.empty?

      token = tail.squish.downcase
      code = (token.length >= 2) ? COUNTRIES[token] : nil
      code ? [head.squish, code] : [line, nil]
    end
  end
end
