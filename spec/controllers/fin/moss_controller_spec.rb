# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Moss overview (default tab): key figures from Fin::MossOverview.
describe Fin::MossController do
  render_views

  let(:person) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

  before { sign_in(person) }

  it "renders the tiles on an empty database" do
    get :index
    expect(response).to be_successful
    expect(response.body).to include("Transaktionen gesamt").and include("Einzahlung")
  end

  it "links each kind tile to the kind's tab and the total tile to the transactions list" do
    get :index
    hrefs = Nokogiri::HTML(response.body).css("#main a").pluck("href")
    expect(hrefs).to include(moss_card_transactions_path, moss_invoices_path,
      moss_reimbursements_path, moss_top_ups_path, moss_transactions_path)
    expect(hrefs.grep(/\?f=/)).to be_empty
  end

  # One transaction of the kind with one expense and `bookings` bookings.
  def create_transaction(type, amount:, bookings: 1, **attrs)
    uuid = SecureRandom.uuid
    tx = MossTransaction.create!(type: type, moss_transaction_uuid: uuid, signed_total_base_amount: amount,
      currency: "EUR", payment_date: Date.new(2026, 3, 2), booking_date: Date.new(2026, 3, 6),
      **attrs)
    expense = MossExpense.create!(moss_transaction: tx, moss_expense_uuid: uuid,
      type: "#{type}Expense", expense_number: 1, signed_expense_base_amount: amount)
    bookings.times do |i|
      MossBooking.create!(moss_transaction: tx, moss_expense: expense,
        sub_row_number: i + 1, signed_base_amount: amount / bookings)
    end
    tx
  end

  # The cards: count, signed sum and average per kind and over all, the sign as
  # its own glyph -- a plus green, a minus muted.
  it "counts, sums and averages per kind, with the sign as a coloured glyph" do
    create_transaction("MossTopUp", amount: 500)
    create_transaction("MossInvoice", amount: -100)
    create_transaction("MossInvoice", amount: -50)

    get :index
    expect(response).to be_successful
    expect(response.body).to include("06.03.2026")
    cards = Nokogiri::HTML(response.body).css("#main a.border.rounded").map { |a| a.text.squish }
    expect(cards).to include("3 Transaktionen gesamt Σ +350,00 € Ø +116,67 €",
      "1 Einzahlung Σ +500,00 € Ø +500,00 €",
      "2 Rechnung Σ -150,00 € Ø -75,00 €",
      "0 Kartenzahlung Σ 0,00 € Ø 0,00 €")
    expect(response.body.squish).to include('<span class="text-success">+</span>500,00 €')
    expect(response.body.squish).to include('<span class="text-muted">-</span>150,00 €')
  end

  # The Datenstand table: one date per kind, the newest transaction of it --
  # dated by the day the movement was booked in the wallet. A kind without a
  # single transaction has no date at all.
  it "dates a kind by the booking date of its newest transaction" do
    create_transaction("MossInvoice", amount: -100)
    # The kinds whose export carries no payout day are dated like every other.
    create_transaction("MossReimbursement", amount: -60, payment_date: nil,
      booking_date: Date.new(2026, 4, 10))
    # A card payment paid days BEFORE it was booked: its payout day is not what
    # dates the kind.
    create_transaction("MossCardTransaction", amount: -20,
      payment_date: Date.new(2026, 4, 28), booking_date: Date.new(2026, 5, 2))

    get :index
    expect(response).to be_successful
    freshness = Nokogiri::HTML(response.body)
      .at_xpath("//h2[normalize-space()='Datenstand']/following-sibling::table[1]")
    expect(freshness.css("thead th").map { |th| th.text.squish })
      .to eq(["Art", "Letztes Buchungsdatum", "Export-Datei"])
    dates = freshness.css("tbody tr").to_h { |tr| tr.css("td").map { |td| td.text.squish }.first(2) }
    expect(dates[I18n.t("fin.moss.kinds.MossInvoice")]).to eq("06.03.2026")
    expect(dates[I18n.t("fin.moss.kinds.MossReimbursement")]).to eq("10.04.2026")
    expect(dates[I18n.t("fin.moss.kinds.MossCardTransaction")]).to eq("02.05.2026")
    expect(dates[I18n.t("fin.moss.kinds.MossTopUp")]).to eq("—")
  end

  # The Struktur block: the levels a kind adds appear under it, the shares are
  # relative to each level's total, and the foreign-currency tag links to the
  # kind's tab (or the Transaktionen tab) filtered to those transactions.
  it "renders the structure tree with shares and foreign-currency links" do
    create_transaction("MossTopUp", amount: 500)
    create_transaction("MossInvoice", amount: -100, bookings: 2, currency_original: "PLN")

    get :index
    expect(response).to be_successful
    doc = Nokogiri::HTML(response.body)
    rows = doc.css("table.moss-structure tr").map { |tr| tr.css("td").map { |td| td.text.squish } }
    expect(rows).to include(
      ["Transaktionen 1 in Fremdwährung", "2", "", "100 %"],
      ["Buchungen", "3", "", "100 % der Buchungen"],
      ["Einzahlungen", "1", "", "50 %"],
      ["Buchungen", "1", "", "33 % der Buchungen"],
      ["Rechnungen 1 in Fremdwährung", "1", "", "50 %"],
      ["Buchungen", "2", "", "67 % der Buchungen"]
    )
    # Every kind lists its bookings; expenses only where a kind bundles several
    # per transaction, which neither a top-up nor an invoice does.
    expect(rows.map(&:first)).not_to include("Ausgaben")

    # The filter travels in the listing's own Rison form: "Original-Währung
    # ist nicht EUR" (operator short form `ni`).
    links = doc.css("table.moss-structure a").map { |a| [a.text, CGI.unescape(a["href"])] }
    expect(links).to eq([
      ["1 in Fremdwährung", "#{moss_transactions_path}?f=!(!(!(cur,ni,'EUR')))"],
      ["1 in Fremdwährung", "#{moss_invoices_path}?f=!(!(!(cur,ni,'EUR')))"]
    ])
  end
end
