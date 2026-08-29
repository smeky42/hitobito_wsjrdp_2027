# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The model half of the Kreditoren detail (fin/personal_accounts/_detail): one
# formatter per field of a WsjrdpPersonalAccount that shows more than its stored
# value, found by the name rule of Fin::AttrFormatHelper
# (fin_format_wsjrdp_personal_account_<attr>), plus the raw helper for the DATEV
# code fields whose meaning is documented.
#
# The labels of the fields live in
# de.activerecord.attributes.wsjrdp_personal_account; a field without a formatter
# takes the finance type rules of Fin::AttrFormatHelper -- which is why the
# aliases (an array, joined) and the sphere number (a string, as stored) need
# none. A number => name map for the spheres, should one appear among the
# finance helpers, belongs here as
# fin_format_wsjrdp_personal_account_moss_default_sphere_number.
module Fin::PersonalAccountsHelper
  # DATEV "Adressattyp" (doc 1003221 field 7, there spelled "Adressatentyp") --
  # company vs. natural person, see doc/fin/personal_accounts.md.
  DATEV_ADDRESSEE_TYPES = {
    "0" => "keine Angabe",
    "1" => "natürliche Person",
    "2" => "Unternehmen"
  }.freeze

  # DATEV "Zahlungsträger" (field 136). A missing value means the same as "0",
  # but an entry the export left empty stays a blank raw entry.
  DATEV_PAYMENT_CARRIERS = {
    "0" => "per Stammdaten",
    "7" => "SEPA-Überweisung mit einer Rechnung",
    "8" => "SEPA-Überweisung mit mehreren Rechnungen",
    "9" => "keine Überweisungen, Schecks"
  }.freeze

  # The Moss status in words, as every other finance view spells it.
  def fin_format_wsjrdp_personal_account_moss_status(account)
    moss_status_cell(account.moss_status)
  end

  # The Rechnungsadresse on one line -- street, Adresszusatz, post code and city,
  # country. A part the record does not carry leaves no separator behind.
  def fin_format_wsjrdp_personal_account_address(account)
    [account.street, account.address_second_line,
      [account.post_code, account.city].compact_blank.join(" "),
      account.country].compact_blank.join(", ").presence
  end

  # Grouped in blocks of four, the way an IBAN is read and dictated. What is
  # stored stays untouched; only the reading aid is added here.
  def fin_format_wsjrdp_personal_account_iban(account)
    iban = account.iban.to_s.delete(" ")
    return nil if iban.blank?

    iban.scan(/.{1,4}/).join(" ")
  end

  # The person this Kreditor stands for: a link to them, with the new-tab
  # companion icon of the finance rows.
  def fin_format_wsjrdp_personal_account_represented_person(account)
    person = account.represented_person
    person && assoc_link_with_newtab(person)
  end

  # The two DATEV defaults Moss carries, as code plus name -- the cell the
  # Buchungen views use for an account and a cost center.
  def fin_format_wsjrdp_personal_account_moss_default_ledger_account_number(account)
    datev_code_cell(account.moss_default_ledger_account_number, datev_account_names)
  end

  def fin_format_wsjrdp_personal_account_moss_default_cost_center_number(account)
    datev_code_cell(account.moss_default_cost_center_number, datev_cost_center_names)
  end

  # The DATEV code fields of a Kreditor whose meaning is documented
  # (doc/fin/personal_accounts.md): the code, followed by what it stands for. A
  # code outside the table -- and every other raw entry, the Moss block
  # included -- keeps the default raw formatting.
  def fin_raw_format_other_wsjrdp_personal_account(account, key, ctx)
    return nil unless ctx.raw_source == :other_datev_columns

    case key
    when "Adressattyp" then datev_code_with_meaning(account, key, DATEV_ADDRESSEE_TYPES)
    when "Zahlungsträger" then datev_code_with_meaning(account, key, DATEV_PAYMENT_CARRIERS)
    end
  end

  private

  def datev_code_with_meaning(account, key, meanings)
    code = account.other_datev_columns[key].to_s
    meaning = meanings[code]
    meaning && "#{code} #{meaning}"
  end
end
