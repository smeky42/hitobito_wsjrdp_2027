# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # The creditor a refund is paid to, as Moss wants it typed in: the person's
  # bank account and address, plus the master data every refund creditor gets.
  #
  # Those defaults are fixed on purpose -- they are what the finance team
  # enters for each of these creditors, so the page states them rather than
  # leaving them to be looked up.
  class RefundCreditor
    # The participant fees account, which a refund goes back out of.
    LEDGER_ACCOUNT = "41030 Teilnehmendenbeiträge"
    # Refunds after a deregistration have a cost center of their own; a plain
    # refund (an overpayment, say) belongs on the other one.
    COST_CENTER = "8010 Rückzahlung Abmeldung"
    COST_CENTER_ALTERNATIVE = "8000 Rückzahlung"
    SPHERE = "3 Zweckbetrieb"
    TEAM = "Finance"
    PAYMENT_METHOD = "Banküberweisung"
    # What the creditor is called in Moss: "TN" and the registration id.
    NAME_PREFIX = "TN"
    # Where these creditors are kept.
    MOSS_SUPPLIERS_URL = "https://getmoss.com/app/accounting/suppliers"
    # What a SEPA address means where it names no country at all.
    DEFAULT_COUNTRY = "DE"

    attr_reader :person

    def initialize(person)
      @person = person
    end

    def name = "#{NAME_PREFIX} #{person.id}"

    def ledger_account = LEDGER_ACCOUNT

    def cost_center = COST_CENTER

    def cost_center_alternative = COST_CENTER_ALTERNATIVE

    def sphere = SPHERE

    def team = TEAM

    def payment_method = PAYMENT_METHOD

    def moss_suppliers_url = MOSS_SUPPLIERS_URL

    def iban = SepaAccount.iban(person)

    def account_holder = SepaAccount.account_holder(person)

    def bic = SepaAccount.bic(person)

    # The country the account is held in, read off the IBAN and written the way
    # the address is -- "Deutschland", not "DE".
    def bank_country = country_label(SepaAccount.bank_country_code(person))

    # Where the money goes: what the SEPA address says, and Germany where it
    # says nothing -- these addresses name a country only when it is not the
    # usual one.
    def country = country_label(SepaAccount.address_country_code(person) || DEFAULT_COUNTRY)

    # The address the bank details were given with, not the person's own: that
    # is the address the money is paid to.
    def street_and_number = SepaAccount.street_and_number(person)

    def zip_code = SepaAccount.zip_code(person)

    def town = SepaAccount.town(person)

    # The line as it was typed -- what the warning shows, so the reader can
    # check the parse against it.
    def raw_address = person.sepa_address.to_s

    # Which heuristics the address needed. Any of them is a reason to look at
    # the line itself before the money goes out.
    def address_notes = SepaAccount.address_notes(person)

    def address_uncertain? = address_notes.any?

    private

    def country_label(code)
      return "" if code.blank?

      Countries.label(code).to_s
    end
  end
end
