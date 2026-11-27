# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# "Buchungen", the Moss tab of every MossBooking (Fin::MossBookingsController
# #index): the rows, the kind choice of the "Schnellauswahl" and the detail's
# header line of links (the booking's own page, the transaction in Moss). The
# booking's own page and its linking actions are specced in
# moss_bookings_controller_spec.rb. All names, numbers and amounts are invented.
describe Fin::MossBookingsController do
  before_all(setup_fixtures: true) {}

  let_it_be(:person, refind: true) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

  let_it_be(:wallet) do
    WsjrdpFinAccount.create!(short_name: "Moss-Wallet", account_identification: "MOSS-WALLET-TEST",
      transaction_type: "MossBalanceMovement", opening_balance_cents: 100_000,
      opening_balance_currency: "EUR", opening_balance_date: Date.new(2026, 1, 1))
  end

  # One transaction of `type` on the wallet, with its (shell) expense and
  # exactly one booking -- the row the list shows. `date` is the day the
  # movement was booked in the wallet, which is what the list is dated by.
  def self.create_booking(wallet, type, amount:, date:, text:, **attrs)
    uuid = SecureRandom.uuid
    transaction = MossTransaction.create!(type: type, moss_transaction_uuid: uuid,
      fin_account: wallet, signed_total_base_amount: amount, currency: "EUR",
      booking_date: date, **attrs)
    expense = MossExpense.create!(moss_transaction: transaction, moss_expense_uuid: uuid,
      type: "#{type}Expense", expense_number: 1, signed_expense_base_amount: amount)
    MossBooking.create!(moss_transaction: transaction, moss_expense: expense,
      sub_row_number: 1, signed_base_amount: amount, booking_posting_text: text)
  end

  delegate :create_booking, to: :class

  # One booking per kind, ordered by Buchungsdatum so the default sort (desc) is
  # top-up, invoice, reimbursement, card.
  let_it_be(:card) do
    create_booking(wallet, "MossCardTransaction", amount: -25, date: Date.new(2026, 5, 3),
      text: "Split eins", merchant_name: "Muster Markt", card_holder_name: "Vorname Nachname",
      transaction_posting_text: "Verpflegung Vortreffen")
  end

  let_it_be(:reimbursement) do
    create_booking(wallet, "MossReimbursement", amount: -60, date: Date.new(2026, 6, 1),
      text: "Anteil eins", transaction_name: "Fahrtkosten Vortreffen", recipient_name: "Vorname Nachname")
  end

  let_it_be(:invoice) do
    create_booking(wallet, "MossInvoice", amount: -100, date: Date.new(2026, 7, 15),
      text: "Zeile eins", invoice_number: "RE-2026-1", supplier_account_number: "700027",
      currency_original: "PLN", signed_total_transaction_amount: -425, exchange_rate: 4.25)
  end

  let_it_be(:top_up) do
    create_booking(wallet, "MossTopUp", amount: 500, date: Date.new(2027, 1, 20),
      text: "Aufladung", top_up_sender: "Vereinskonto")
  end

  before { sign_in(person) }

  def rows = controller.bookings.page.to_a

  describe "GET index" do
    it "lists one row per booking, newest first" do
      get :index

      aggregate_failures do
        expect(response).to be_successful
        expect(rows).to eq([top_up, invoice, reimbursement, card])
        expect(controller.bookings.total_count).to eq(4)
      end
    end

    # A card payment whose payout day falls days before the day it was booked:
    # the list places and shows it by the booking day.
    it "dates a row by its booking date, in the cell and in the sort" do
      booked_later = create_booking(wallet, "MossCardTransaction", amount: -40,
        date: Date.new(2026, 6, 15), text: "Anteil zwei", payment_date: Date.new(2026, 6, 9))
      get :index

      aggregate_failures do
        expect(rows).to eq([top_up, invoice, booked_later, reimbursement, card])
        expect(controller.view_context.moss_bookings_cell(rows[2], "booking_date")).to eq("15.06.2026")
      end
    end

    it "shows the booking's Kostenstelle and Sachkonto by default, with their names" do
      WsjrdpCostCenter.create!(number: "4711", name: "Vortreffen") unless WsjrdpCostCenter.exists?(number: "4711")
      card.update!(cost_center_number: "4711")
      get :index

      aggregate_failures do
        expect(controller.bookings_table_state.visible_column_keys).to include("cost_center_number", "account_number")
        expect(Nokogiri::HTML.fragment(controller.view_context.moss_bookings_cell(card.reload, "cost_center_number"))
          .text.squish).to eq("4711 Vortreffen")
      end
    end
  end

  # The kinds are a fixed group of several answers (Fin::MossKinds.fixed_group),
  # every kind chosen by default, the choice carried by the lifts param `u`.
  describe "GET index with a kind choice" do
    it "shows only the chosen kinds" do
      get :index, params: {u: "kind.card_transaction+reimbursement"}
      expect(rows).to eq([reimbursement, card])
    end

    it "shows nothing when no kind is chosen" do
      get :index, params: {u: "kind.-"}
      expect(controller.bookings.total_count).to eq(0)
    end
  end

  # A row has no detail of its own -- it shows everything the booking's page
  # would repeat -- so opening it reveals the header line: "In Moss" left of
  # "Detailseite", each a double link. A top-up has no record page in Moss, so
  # its line is "Detailseite" alone.
  describe "the rows' header lines" do
    render_views

    def doc = Nokogiri::HTML(response.body)

    def link_groups(index) = doc.css(".exp-detail-links").map { |line| line.css(".btn-group").map { |g| g.css("a")[index] } }

    it "lead to the booking's page and to its transaction in Moss, and load the detail lazily" do
      get :index

      moss_urls = [invoice, reimbursement, card].map { |b| b.moss_transaction.moss_record_url }
      pages = [top_up, invoice, reimbursement, card].map { |b| moss_booking_path(b) }
      same_tab = link_groups(0)
      new_tab = link_groups(1)
      frame = doc.at_css("turbo-frame[data-record='moss_booking_#{card.id}']")

      aggregate_failures do
        expect(same_tab.map { |group| group.map { |a| a.text.squish } })
          .to eq([["Detailseite"]] + [["In Moss", "Detailseite"]] * 3)
        expect(same_tab.map(&:last).pluck("href")).to eq(pages)
        expect(new_tab.map(&:last).pluck("href", "target")).to eq(pages.map { |page| [page, "_blank"] })
        expect(same_tab.drop(1).map(&:first).pluck("href")).to eq(moss_urls)
        expect(new_tab.drop(1).map(&:first).pluck("target")).to eq(["_blank"] * 3)
        expect(frame["src"]).to start_with(moss_booking_path(card))
        expect(frame["loading"]).to eq "lazy"
      end
    end
  end

  describe "POST apply" do
    it "encodes the posted tree and redirects (PRG) back to the list" do
      post :apply, params: {filter_json: [[["kind", "in", "MossTopUp"]]].to_json}
      expect(response).to have_http_status(:see_other)
      expect(CGI.unescape(response.location))
        .to end_with("/fin/moss/bookings?f=!(!(!(k,in,'MossTopUp')))")
    end

    # An emptied filter must redirect to an explicitly BLANK param: an absent
    # one would fall through to the remembered filter and bring it straight back.
    it "emits a blank filter param when every condition was removed" do
      post :apply, params: {filter_json: "[]"}
      expect(response).to have_http_status(:see_other)
      expect(response.location).to end_with("/fin/moss/bookings?f=")
    end
  end
end
