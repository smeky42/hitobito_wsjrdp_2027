# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The fields of a booking's detail and its Unit-Budget cell. The Konto 1200
# says yes to the Unit-Budget, the Gegenkonto 66500 says no, so an untouched
# booking reads "nein, Gegenkonto 66500". Invented numbers and amounts.
describe Fin::BookingsHelper do
  before_all(setup_fixtures: true) {}

  before_all do
    WsjrdpLedgerAccount.create!(number: "1200", name: "Testbank")
    WsjrdpLedgerAccount.create!(number: "66500", name: "Testaufwand", is_unit_budget: false)
  end

  def build_booking(**attrs)
    DatevBooking.new(account_number: "1200", account_kind: "BANK",
      offsetting_account_number: "66500", offsetting_account_kind: "EXPENSE",
      base_amount: 100, transaction_amount: 100, debit_credit: "D", base_currency: "EUR",
      transaction_currency: "EUR", **attrs)
  end

  def text(html) = Nokogiri::HTML.fragment(html.to_s).text.strip

  let(:nbsp) { Fin::MoneyHelper::NBSP }

  describe "the amounts" do
    let(:foreign) do
      build_booking(base_amount: 230, transaction_amount: 1000, transaction_currency: "PLN", exchange_rate: 4.3478)
    end

    it "writes the Soll/Haben of the Betrag out" do
      aggregate_failures do
        expect(text(helper.fin_format_datev_booking_base_amount(build_booking))).to eq("100,00#{nbsp}€Soll")
        expect(text(helper.fin_format_datev_booking_base_amount(build_booking(debit_credit: "C"))))
          .to end_with("Haben")
      end
    end

    it "shows the original amount and the rate of a foreign-currency booking only" do
      aggregate_failures do
        expect(helper.fin_format_datev_booking_transaction_amount(foreign)).to eq("1.000,00#{nbsp}zł")
        expect(helper.fin_format_datev_booking_exchange_rate(foreign)).to eq("4,3478")
        expect(helper.fin_format_datev_booking_transaction_amount(build_booking)).to be_nil
        expect(helper.fin_format_datev_booking_exchange_rate(build_booking(exchange_rate: 4.3478))).to be_nil
      end
    end
  end

  # The write tier holds :log, so the helpdesk's ticket keys are links for it; a
  # unit leader reads them as text.
  describe "the Notizen" do
    let(:booking) { build_booking(user_comment: "siehe FIN-123 und https://example.org/x") }

    def links = Nokogiri::HTML.fragment(helper.fin_format_datev_booking_user_comment(booking)).css("a")
      .to_h { |a| [a.text, a["href"]] }

    it "links the tickets for a viewer with :log" do
      allow(helper).to receive(:can?).with(:log, booking).and_return(true)

      expect(links).to eq("FIN-123" => "https://helpdesk.worldscoutjamboree.de/browse/FIN-123",
        "https://example.org/x" => "https://example.org/x")
    end

    it "links URLs only for a viewer without :log" do
      allow(helper).to receive(:can?).with(:log, booking).and_return(false)

      expect(links).to eq("https://example.org/x" => "https://example.org/x")
    end
  end

  # The resolved answer and where it came from: the booking's own flag, else
  # its two accounts, else the default.
  describe "the Unit-Budget" do
    def resolved(**attrs)
      booking = build_booking(buchungs_guid: SecureRandom.uuid, booking_date: Date.new(2026, 2, 1), **attrs)
      booking.save!
      DatevBooking.with_unit_budget.find(booking.id)
    end

    let(:agreeing) { {offsetting_account_number: "1200", offsetting_account_kind: "BANK"} }

    it "names the account that decided, in the field and in the cell" do
      booking = resolved

      aggregate_failures do
        expect(helper.fin_format_datev_booking_is_unit_budget(booking)).to eq("nein (automatisch, Gegenkonto 66500)")
        expect(text(helper.booking_unit_budget_cell(booking))).to eq("nein Gegenkonto 66500")
        expect(helper.booking_unit_budget_cell(booking, condensed: true)).to eq("nein")
      end
    end

    it "names no source where both accounts agree" do
      booking = resolved(**agreeing)

      aggregate_failures do
        expect(helper.fin_format_datev_booking_is_unit_budget(booking)).to eq("ja (automatisch)")
        expect(helper.booking_unit_budget_cell(booking)).to eq("ja")
      end
    end

    it "names the booking itself where it carries the flag" do
      booking = resolved(is_unit_budget: true)

      aggregate_failures do
        expect(helper.fin_format_datev_booking_is_unit_budget(booking)).to eq("ja (Buchung)")
        expect(text(helper.booking_unit_budget_cell(booking))).to eq("ja Buchung")
      end
    end

    # The first option leaves the booking's own flag unset, so it names the
    # answer the accounts give.
    it "names the automatic answer in the edit select" do
      expect(helper.fin_unit_budget_select_options(build_booking(is_unit_budget: true)))
        .to eq([["automatisch (nein)", ""], ["ja", "true"], ["nein", "false"]])
    end
  end
end
