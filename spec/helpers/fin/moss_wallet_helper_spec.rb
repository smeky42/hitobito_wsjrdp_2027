# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The cells of ONE Moss wallet row (Fin::MossWalletHelper): the party of line 1,
# the status tags, the signed amount and the Buchungstext lines. Every method
# takes a booking or a transaction and nothing else, so the rows below are
# BUILT, not fixtures -- only the invoice's creditor is saved, because its
# standing-data row is reached through a generated column.
#
# All names, numbers and amounts here are invented.
describe Fin::MossWalletHelper do
  # A booking of `type` with the transaction attributes the cell under test
  # reads. `amount` is the split's signed EUR share, the transaction total the
  # same figure -- one split per payment is the shape of every kind but a
  # reimbursement.
  def booking(type, amount: -100, expense: nil, text: "", **attrs)
    transaction = type.constantize.new(moss_transaction_uuid: SecureRandom.uuid,
      signed_total_base_amount: amount, currency: "EUR", **attrs)
    MossBooking.new(moss_transaction: transaction, moss_expense: expense,
      signed_base_amount: amount, booking_posting_text: text)
  end

  def tags(booking) = helper.moss_wallet_tags(booking)

  def party(booking) = helper.moss_wallet_party(booking.moss_transaction)

  def text_lines(booking) = Nokogiri::HTML.fragment(helper.moss_wallet_text_lines(booking))

  describe "the foreign-currency tag" do
    # What Moss actually moved, in the currency it moved it in, plus the rate
    # the EUR figure was derived with.
    it "names the original amount and the rate" do
      row = booking("MossCardTransaction", currency_original: "PLN",
        signed_total_transaction_amount: 1234, exchange_rate: 4.25)
      expect(tags(row)).to eq(["1.234,00 PLN · Kurs 4,2500"])
    end

    it "omits the rate when the export carried none" do
      row = booking("MossCardTransaction", currency_original: "PLN",
        signed_total_transaction_amount: 1234, exchange_rate: nil)
      expect(tags(row)).to eq(["1.234,00 PLN"])
    end

    # The base currency needs no tag -- that is what the Betrag column shows.
    it "says nothing about a payment in EUR" do
      expect(tags(booking("MossCardTransaction", currency_original: "EUR",
        signed_total_transaction_amount: 100))).to eq([])
      expect(tags(booking("MossCardTransaction"))).to eq([])
    end
  end

  describe "the Gutschrift tag" do
    # A card payment is an outflow, so a positive split is money that came back.
    it "marks a card row whose money came back" do
      expect(tags(booking("MossCardTransaction", amount: 25))).to eq(["Gutschrift"])
    end

    it "leaves an ordinary card payment unmarked" do
      expect(tags(booking("MossCardTransaction", amount: -25))).to eq([])
    end

    # A top-up is positive BY DEFINITION; calling it a Gutschrift would mark
    # every single one of them.
    it "does not mark a positive top-up" do
      expect(tags(booking("MossTopUp", amount: 500))).to eq([])
    end
  end

  # Both exist for a future export; with today's data neither ever renders.
  describe "the deviating-status tags" do
    it "shows an invoice status other than Completed, on an invoice" do
      expect(tags(booking("MossInvoice", invoice_status: "Open"))).to eq(["Open"])
      expect(tags(booking("MossInvoice", invoice_status: "Completed"))).to eq([])
      expect(tags(booking("MossInvoice", invoice_status: nil))).to eq([])
      # The column is on the shared table, so a card row could carry one.
      expect(tags(booking("MossCardTransaction", invoice_status: "Open"))).to eq([])
    end

    it "shows a Moss state other than ACCEPTED, on any kind" do
      expect(tags(booking("MossTopUp", amount: 500, moss_transaction_state: "PENDING")))
        .to eq(["PENDING"])
      expect(tags(booking("MossTopUp", amount: 500, moss_transaction_state: "ACCEPTED"))).to eq([])
      expect(tags(booking("MossTopUp", amount: 500, moss_transaction_state: nil))).to eq([])
    end

    it "lists several tags in their display order" do
      row = booking("MossInvoice", amount: 60, currency_original: "PLN",
        signed_total_transaction_amount: 255, exchange_rate: 4.25,
        invoice_status: "Open", moss_transaction_state: "PENDING")
      expect(tags(row)).to eq(["255,00 PLN · Kurs 4,2500", "Open", "PENDING"])
    end
  end

  describe "the party of line 1" do
    it "names the card holder and their team, dropping a blank half" do
      expect(party(booking("MossCardTransaction", card_holder_name: "Vorname Nachname",
        card_holder_team_name: "Team Muster"))).to eq("Vorname Nachname · Team Muster")
      expect(party(booking("MossCardTransaction", card_holder_name: "Vorname Nachname")))
        .to eq("Vorname Nachname")
      expect(party(booking("MossCardTransaction", card_holder_team_name: "Team Muster")))
        .to eq("Team Muster")
      expect(party(booking("MossCardTransaction"))).to be_nil
    end

    # The creditor's name comes from the standing data, reached through the
    # GENERATED supplier_account_type -- so this one row has to be saved.
    it "names the invoice's creditor with its account number" do
      WsjrdpPersonalAccount.create!(number: "700027", name: "Beispiel GmbH",
        account_kind: "CREDITOR")
      transaction = MossInvoice.create!(moss_transaction_uuid: SecureRandom.uuid,
        signed_total_base_amount: -100, currency: "EUR",
        supplier_account_number: "700027", supplier_account_kind: "CREDITOR").reload
      expect(helper.moss_wallet_party(transaction)).to eq("Beispiel GmbH · Kreditor 700027")
      expect(helper.moss_wallet_supplier(transaction)).to eq("Beispiel GmbH · Kreditor 700027")
    end

    it "falls back to the creditor number alone when the standing data is missing" do
      expect(party(booking("MossInvoice", supplier_account_number: "700028")))
        .to eq("Kreditor 700028")
      expect(party(booking("MossInvoice"))).to be_nil
    end

    it "names the payee of a reimbursement and the sender of a top-up" do
      expect(party(booking("MossReimbursement", recipient_name: "Vorname Nachname")))
        .to eq("Vorname Nachname")
      expect(party(booking("MossTopUp", amount: 500, top_up_sender: "Vereinskonto")))
        .to eq("Vereinskonto")
      expect(party(booking("MossReimbursement"))).to be_nil
    end

    # Line 1 = name, party, tags -- composed here so the row's first line stays
    # readable when a part is missing.
    it "puts the payment's name in front of the party and the tags behind it" do
      row = booking("MossCardTransaction", amount: 25, merchant_name: "Muster Markt",
        card_holder_name: "Vorname Nachname")
      headline = Nokogiri::HTML.fragment(helper.moss_wallet_headline(row))
      expect(headline.at_css("span.mw-name").text).to eq("Muster Markt")
      expect(headline.css("span.moss-tag").map(&:text)).to eq(["Gutschrift"])
      expect(headline.text).to start_with("Muster Markt · Vorname Nachname")
    end
  end

  describe "the Betrag cell" do
    # The sign is the cue, the colour only reinforces it.
    it "gives money coming in a plus and the green class" do
      cell = Nokogiri::HTML.fragment(helper.moss_wallet_amount_cell(booking("MossTopUp", amount: 500)))
      expect(cell.at_css("span.moss-amount-in").text.squish).to eq("+500,00 €")
    end

    it "leaves a negative amount with its own sign and the default colour" do
      expect(helper.moss_wallet_amount_cell(booking("MossCardTransaction", amount: -23.35)).squish)
        .to eq("-23,35 €")
    end
  end

  describe "the Buchungstext lines" do
    # A top-up has no Buchungstext worth showing; what it says is where the
    # money came from, which is the fixed account chain.
    it "replaces a top-up's texts with the account chain" do
      row = booking("MossTopUp", amount: 500, top_up_sender: "Vereinskonto", text: "egal")
      expect(text_lines(row).text).to eq(I18n.t("fin.moss.top_up_line"))
    end

    # The transaction's NAME is line 1 already, so its line here shows the text
    # alone -- the prefix would repeat a label in every single row.
    it "drops the Transaktion prefix but keeps the levels below" do
      expense = MossReimbursementExpense.new(expense_name: "Bahnticket",
        expense_posting_text: "Hinfahrt")
      row = booking("MossReimbursement", expense: expense, text: "Anteil eins",
        transaction_name: "Fahrtkosten Vortreffen", transaction_posting_text: "Reisekosten")
      lines = text_lines(row)
      expect(lines.css("div").map { |div| div.text.strip })
        .to eq(["Reisekosten", "Ausgabe: Bahnticket – Hinfahrt", "Buchung: Anteil eins"])
      expect(lines.to_html).not_to include("Transaktion:")
      expect(lines.at_css("div span.fst-italic").text).to eq("Reisekosten")
    end

    it "renders no transaction line at all when the payment has no text" do
      row = booking("MossCardTransaction", merchant_name: "Muster Markt", text: "Split eins")
      expect(text_lines(row).css("div").map { |div| div.text.strip }).to eq(["Buchung: Split eins"])
    end

    # #moss_wallet_text_line is the per-line rule the levels above go through.
    it "keeps the shared rendering for the expense and booking levels" do
      expect(helper.moss_wallet_text_line(:expense, "Bahnticket", "Hinfahrt"))
        .to eq(helper.moss_text_line(:expense, "Bahnticket", "Hinfahrt"))
      expect(helper.moss_wallet_text_line(:transaction, "Name", nil)).to be_nil
    end
  end
end
