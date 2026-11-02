# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The meaning of the codes a bank transaction carries (doc/fin/payments.md):
#
# - the ISO 20022 Bank Transaction Code "<Domain>+<Family>+<SubFamily>"
#   (bank_transaction_code), each part with a German label and the English
#   name of the ISO external code list;
# - the code of the German banks "<SWIFT code>+<GVC>[+<Primanota>
#   [+<Textschlüsselergänzung>]]" (bank_transaction_code_dk, DFÜ-Abkommen
#   Anlage 3, chapter 7.1.8.5.2): the SWIFT transaction type of MT940 and the
#   GVC (Geschäftsvorfallcode) with its German and English name after Anhang 1
#   of Anlage 3. The Primanota, a batch number of the bank, has no meaning of
#   its own.
#
# A curated selection: the codes of payments in euro, of the returns of any
# kind and of the bank's own postings. A code not listed shows as it is.
module Fin::BankTransactionCodes
  DOMAINS = {
    "ACMT" => ["Kontoführung", "Account Management"],
    "CAMT" => ["Cash-Management", "Cash Management"],
    "FORX" => ["Devisen", "Foreign Exchange"],
    "LDAS" => ["Kredite und Einlagen", "Loans, Deposits & Syndications"],
    "PMNT" => ["Zahlungsverkehr", "Payments"],
    "SECU" => ["Wertpapiere", "Securities"],
    "TRAD" => ["Handelsfinanzierung", "Trade Services"],
    "XTND" => ["Erweitert", "Extended Domain"]
  }.freeze

  FAMILIES = {
    "ACOP" => ["Weitere sonstige Gutschriften", "Additional Miscellaneous Credit Operations"],
    "ADOP" => ["Weitere sonstige Belastungen", "Additional Miscellaneous Debit Operations"],
    "CCRD" => ["Kartenzahlung", "Customer Card Transactions"],
    "ICDT" => ["Ausgehende Überweisung", "Issued Credit Transfers"],
    "ICHQ" => ["Ausgestellter Scheck", "Issued Cheques"],
    "IDDT" => ["Eingereichte Lastschrift", "Issued Direct Debits"],
    "IRCT" => ["Ausgehende Echtzeitüberweisung", "Issued Real-Time Credit Transfers"],
    "MCOP" => ["Sonstige Gutschrift", "Miscellaneous Credit Operations"],
    "MCRD" => ["Kartenumsätze als Händler", "Merchant Card Transactions"],
    "MDOP" => ["Sonstige Belastung", "Miscellaneous Debit Operations"],
    "NTAV" => ["Nicht angegeben", "Not Available"],
    "OPCL" => ["Kontoeröffnung und -abschluss", "Opening & Closing"],
    "OTHR" => ["Sonstiges", "Other"],
    "RCDT" => ["Eingehende Überweisung", "Received Credit Transfers"],
    "RCHQ" => ["Eingereichter Scheck", "Received Cheques"],
    "RDDT" => ["Belastende Lastschrift", "Received Direct Debits"],
    "RRCT" => ["Eingehende Echtzeitüberweisung", "Received Real-Time Credit Transfers"]
  }.freeze

  SUB_FAMILIES = {
    "ACCC" => ["Rechnungsabschluss", "Account Closing"],
    "ADJT" => ["Korrektur", "Adjustments (Generic)"],
    "BBDD" => ["SEPA-Firmenlastschrift", "SEPA B2B Direct Debit"],
    "BOOK" => ["Interne Umbuchung", "Internal Book Transfer"],
    "CHRG" => ["Gebühren", "Charges (Generic)"],
    "COMM" => ["Provision", "Commission (Generic)"],
    "ESCT" => ["SEPA-Überweisung", "SEPA Credit Transfer"],
    "ESDD" => ["SEPA-Basislastschrift", "SEPA Core Direct Debit"],
    "INTR" => ["Zinsen", "Interests (Generic)"],
    "NTAV" => ["Nicht angegeben", "Not Available"],
    "OTHR" => ["Sonstiges", "Other"],
    "PRDD" => ["Rückbuchung wegen Storno", "Reversal Due To Payment Reversal"],
    "PSTE" => ["Storno einer Fehlbuchung", "Posting Error"],
    "RCDD" => ["Rückbuchung auf Rückrufantrag", "Reversal Due To Payment Cancellation Request"],
    "RRTN" => ["Rückbuchung wegen Rückgabe", "Reversal Due To Payment Return"],
    "SALA" => ["Lohn und Gehalt", "Payroll/Salary Payment"],
    "SDVA" => ["Eilüberweisung", "Same Day Value Credit Transfer"],
    "STDO" => ["Dauerauftrag", "Standing Order"],
    "TAXE" => ["Steuern", "Taxes (Generic)"],
    "UPCQ" => ["Scheckrückgabe", "Unpaid Cheque"],
    "UPCT" => ["Rückbelastung Kartenzahlung", "Unpaid Card Transaction"],
    "UPDD" => ["Rücklastschrift", "Reversal Due To Return/Unpaid Direct Debit"],
    "XBCT" => ["Auslandsüberweisung", "Cross-Border Credit Transfer"],
    "XBDD" => ["Auslandslastschrift", "Cross-Border Direct Debit"],
    "XBST" => ["Auslandsdauerauftrag", "Cross-Border Standing Order"],
    "XRTN" => ["Rückbuchung wegen Rückgabe (Ausland)", "Cross Border Reversal Due to Payment Return"]
  }.freeze

  # The SWIFT transaction types (MT940 field 61) that lead the code of the
  # German banks.
  SWIFT_CODES = {
    "NCHG" => ["Gebühren", "Charges"],
    "NCHK" => ["Scheck", "Cheque"],
    "NCMI" => ["Cash-Management", "Cash management item"],
    "NCOL" => ["Lastschrifteinzug", "Collection"],
    "NDDT" => ["Lastschrift", "Direct debit"],
    "NINT" => ["Zinsen", "Interest"],
    "NMSC" => ["Sonstiges", "Miscellaneous"],
    "NRTI" => ["Rückgabe", "Returned item"],
    "NSTO" => ["Dauerauftrag", "Standing order"],
    "NTRF" => ["Überweisung", "Transfer"]
  }.freeze

  GVCS = {
    "104" => ["SEPA-Firmenlastschrift (Einzelbuchung-Soll)", "SEPA Direct Debit (single entry – debit, B2B)"],
    "105" => ["SEPA-Basislastschrift (Einzelbuchung-Soll)", "SEPA Direct Debit (single entry – debit, Core)"],
    "108" => ["SEPA-Firmenlastschrift (Rückbelastung)", "SEPA Direct Debit (debit; reversal debit, B2B)"],
    "109" => ["SEPA-Basislastschrift (Rückbelastung)", "SEPA Direct Debit (debit; reversal debit, Core)"],
    "110" => ["SEPA-Kartenzahlung (Rückbelastung)", "SEPA Card Clearing (debit; reversal debit)"],
    "111" => ["Rückrechnung von Schecks", "Return account of cheques"],
    "116" => ["SEPA-Überweisung (Einzelbuchung-Soll)", "SEPA Credit Transfer (single entry – debit)"],
    "117" => ["SEPA-Dauerauftrag (Soll)", "SEPA Credit Transfer (recurring instalment payment – debit)"],
    "118" => ["SEPA-Echtzeitüberweisung (Einzelbuchung-Soll)", "SEPA Instant Credit Transfer (single entry – debit)"],
    "119" => ["SEPA-Überweisung (Einzelbuchung-Soll, Spende)", "SEPA Credit Transfer (single entry – debit, charity payment)"],
    "152" => ["SEPA-Dauerauftragsgutschrift", "SEPA Credit Transfer (credit, recurring instalment payment)"],
    "153" => ["SEPA-Überweisung (Haben, Lohn, Gehalt, Rente)", "SEPA Credit Transfer (single entry – credit, wages, salaries, pension)"],
    "159" => ["SEPA-Überweisung Rückbuchung (unanbringlich oder Rückruf)", "SEPA Credit Transfer back posting (cannot be credited or recall)"],
    "160" => ["SEPA-Echtzeitüberweisung Rückbuchung (unanbringlich oder Rückruf)", "SEPA Instant Credit Transfer back posting (cannot be credited or recall)"],
    "165" => ["SEPA-Echtzeitüberweisung (Einzelbuchung-Haben, Spende)", "SEPA Instant Credit Transfer (single entry – credit, charity payment)"],
    "166" => ["SEPA-Überweisung (Einzelbuchung-Haben)", "SEPA Credit Transfer (single entry – credit)"],
    "167" => ["SEPA-Überweisung (Einzelbuchung-Haben, RF-Referenz)", "SEPA Credit Transfer (single entry – credit, RF reference)"],
    "168" => ["SEPA-Echtzeitüberweisung (Einzelbuchung-Haben)", "SEPA Instant Credit Transfer (single entry – credit)"],
    "169" => ["SEPA-Überweisung (Einzelbuchung-Haben, Spende)", "SEPA Credit Transfer (single entry – credit, charity payment)"],
    "171" => ["SEPA-Basislastschrift Einreichung (Einzelbuchung-Haben)", "SEPA Direct Debit submission (single entry – credit, Core)"],
    "174" => ["SEPA-Firmenlastschrift (Einzelbuchung-Haben)", "SEPA Direct Debit (single entry – credit, B2B)"],
    "177" => ["SEPA-Überweisung Online (Einzelbuchung-Soll)", "SEPA Credit Transfer Online (single entry – debit)"],
    "181" => ["SEPA-Basislastschrift (Wiedergutschrift)", "SEPA Direct Debit (credit; recredit, Core)"],
    "183" => ["Scheckrückgabe (Haben)", "Return of cheque"],
    "184" => ["SEPA-Firmenlastschrift (Wiedergutschrift)", "SEPA Direct Debit (credit; recredit, B2B)"],
    "189" => ["SEPA-Echtzeitüberweisung (Sammler-Haben)", "SEPA Instant Credit Transfer (bulk posting credit)"],
    "191" => ["SEPA-Überweisung (Sammler-Soll)", "SEPA Credit Transfer (bulk posting debit)"],
    "192" => ["SEPA-Basislastschrift (Sammler-Haben)", "SEPA Direct Debit (bulk posting credit, Core)"],
    "193" => ["SEPA-Lastschrift (Soll, Reversal)", "SEPA Direct Debit (debit, reversal)"],
    "194" => ["SEPA-Überweisung (Sammler-Haben)", "SEPA Credit Transfer (bulk posting credit)"],
    "195" => ["SEPA-Basislastschrift (Sammler-Soll)", "SEPA Direct Debit (bulk posting debit, Core)"],
    "196" => ["SEPA-Firmenlastschrift (Sammler-Haben)", "SEPA Direct Debit (bulk posting credit, B2B)"],
    "197" => ["SEPA-Firmenlastschrift (Sammler-Soll)", "SEPA Direct Debit (bulk posting debit, B2B)"],
    "201" => ["Auslandszahlungsauftrag", "Payment order"],
    "202" => ["Zahlungseingang Ausland", "Cross-border payment (credit)"],
    "206" => ["Auslandsüberweisung (Haben)", "Cross-border remittance"],
    "210" => ["Zahlung über elektronische Medien", "Electronic payment"],
    "212" => ["Dauerauftrag Ausland", "Standing order"],
    "213" => ["Lastschrifteinzug aus dem Ausland", "Cross-border direct debit"],
    "399" => ["Storno", "Reversal"],
    "805" => ["Abschluss", "Account closing"],
    "806" => ["Porto, Zustellgebühren", "Postage and handling"],
    "807" => ["Preise, Spesen", "Fees and expenses"],
    "808" => ["Gebühren", "Charges"],
    "809" => ["Provisionen", "Brokerage"],
    "810" => ["Mahngebühren", "Reminder charges"],
    "814" => ["Zinsen", "Interest"],
    "820" => ["Übertrag", "Carry-over"],
    "835" => ["Sonstige nicht definierte Geschäftsvorfälle", "Other non-defined transaction types"],
    "836" => ["Reklamationsbuchung", "Complaint posting"],
    "837" => ["Umsatzsteuer", "Value added tax"],
    "899" => ["Storno", "Reversal"]
  }.freeze

  Part = Data.define(:code, :label, :name) do
    def known? = !label.nil?
  end

  module_function

  # The parts of the ISO code: Domain, Family, SubFamily -- each a Part with
  # its German label and English name, nil where the list does not know it.
  def iso_parts(code)
    domain, family, sub_family = code.to_s.split("+").map(&:strip)
    [[domain, DOMAINS], [family, FAMILIES], [sub_family, SUB_FAMILIES]].filter_map do |value, list|
      part(value, list) if value.present?
    end
  end

  # The meaningful parts of the code of the German banks, each a Part or nil:
  # {swift:, gvc:, text_key:} -- the Textschlüsselergänzung follows the
  # Primanota, which is left out.
  def dk_parts(code)
    swift, gvc, _primanota, text_key = code.to_s.split("+").map(&:strip)
    {swift: (part(swift, SWIFT_CODES) if swift.present?), gvc: (part(gvc, GVCS) if gvc.present?),
     text_key: (Part.new(code: text_key, label: nil, name: nil) if text_key.present?)}
  end

  def part(value, list)
    label, name = list[value.upcase]
    Part.new(code: value, label: label, name: name)
  end
end
