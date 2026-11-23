# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# "Buchungen", the Moss tab of every MossBooking (Fin::MossBookingsController
# #index): the expandable table with the kind chips, the coloured rails, the
# kind segment of the "Schnellauswahl" and the detail's header line of links
# (the booking's own page, the transaction in Moss). The booking's own page and
# its linking actions are specced in moss_bookings_controller_spec.rb. All
# names, numbers and amounts are invented.
describe Fin::MossBookingsController do
  render_views

  let(:person) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

  let!(:wallet) do
    WsjrdpFinAccount.create!(short_name: "Moss-Wallet", account_identification: "MOSS-WALLET-TEST",
      transaction_type: "MossBalanceMovement", opening_balance_cents: 100_000,
      opening_balance_currency: "EUR", opening_balance_date: Date.new(2026, 1, 1))
  end

  # One transaction of `type` on the wallet, with its (shell) expense and
  # exactly one booking -- the row the list shows. `date` is the day the
  # movement was booked in the wallet, which is what the list is dated by.
  def create_booking(type, amount:, date:, text:, **attrs)
    uuid = SecureRandom.uuid
    transaction = MossTransaction.create!(type: type, moss_transaction_uuid: uuid,
      fin_account: wallet, signed_total_base_amount: amount, currency: "EUR",
      booking_date: date, **attrs)
    expense = MossExpense.create!(moss_transaction: transaction, moss_expense_uuid: uuid,
      type: "#{type}Expense", expense_number: 1, signed_expense_base_amount: amount)
    MossBooking.create!(moss_transaction: transaction, moss_expense: expense,
      sub_row_number: 1, signed_base_amount: amount, booking_posting_text: text)
  end

  # One booking per kind, ordered by Buchungsdatum so the default sort (desc) is
  # top-up, invoice, reimbursement, card. The invoice is the foreign-currency
  # row, the top-up the one with money coming IN.
  let!(:card) do
    create_booking("MossCardTransaction", amount: -25, date: Date.new(2026, 5, 3),
      text: "Split eins", merchant_name: "Muster Markt", card_holder_name: "Vorname Nachname",
      transaction_posting_text: "Verpflegung Vortreffen")
  end

  let!(:reimbursement) do
    create_booking("MossReimbursement", amount: -60, date: Date.new(2026, 6, 1),
      text: "Anteil eins", transaction_name: "Fahrtkosten Vortreffen",
      recipient_name: "Vorname Nachname")
  end

  let!(:invoice) do
    create_booking("MossInvoice", amount: -100, date: Date.new(2026, 7, 15),
      text: "Zeile eins", invoice_number: "RE-2026-1", supplier_account_number: "700027",
      currency_original: "PLN", signed_total_transaction_amount: -425, exchange_rate: 4.25)
  end

  let!(:top_up) do
    create_booking("MossTopUp", amount: 500, date: Date.new(2027, 1, 20),
      text: "Aufladung", top_up_sender: "Vereinskonto")
  end

  before { sign_in(person) }

  def doc = Nokogiri::HTML(response.body)

  # The kind class of every rendered row, top to bottom -- the coloured rail.
  def rendered_kinds
    doc.css("tr.exp-row").map { |tr| tr["class"].to_s.split.grep(/\Amoss-kind-/).first }
  end

  # [kind class, chip word] per row, from the "Art" cell.
  def rendered_chips
    doc.css("tr.exp-row span.moss-kind").map { |span| [span["class"].split.last, span.text.strip] }
  end

  def preset_links = doc.css("a.flt-preset")

  # The applied filter's chips, as the line words them.
  def chip_texts = doc.css(".flt-applied .flt-chip").map { |chip| chip.text.strip }

  # The double links of every detail row's header line, in rendered order (extra
  # links first, "Detailseite" last). `part` picks the left (same tab) or the
  # right (new tab) button of each group.
  def detail_link_groups(part)
    index = (part == :new_tab) ? 1 : 0
    doc.css(".exp-detail-links").map { |line| line.css(".btn-group").map { |g| g.css("a")[index] } }
  end

  # The lifts param (`u`) a segment button points at.
  def preset_lifts(link)
    CGI.unescape(CGI.unescapeHTML(link["href"].to_s)[/[?&]u=([^&]*)/, 1].to_s)
  end

  # The four kinds in their own order, and the marking each one carries.
  let(:kinds) { Fin::MossTransactionsFilterSchema::KINDS }

  describe "GET index" do
    before { get :index }

    it "renders one row per booking, newest first, each with its kind's rail" do
      expect(response).to be_successful
      expect(rendered_kinds).to eq(%w[MossTopUp MossInvoice MossReimbursement MossCardTransaction]
        .map { |kind| Fin::MossKinds.css_class(kind) })
      expect(response.body).to include("4 Buchungen")
    end

    # Icon and word, never colour alone.
    it "marks every row with the kind's chip" do
      expect(rendered_chips).to eq(%w[MossTopUp MossInvoice MossReimbursement MossCardTransaction]
        .map { |kind| [Fin::MossKinds.css_class(kind), I18n.t("fin.moss.kind_chips.#{kind}")] })
      expect(doc.css("tr.exp-row span.moss-kind i").pluck("class"))
        .to eq(%w[MossTopUp MossInvoice MossReimbursement MossCardTransaction]
          .map { |kind| "fas fa-#{Fin::MossKinds.icon(kind)}" })
    end

    # The sign is the cue, the colour reinforces it.
    it "gives the top-up row a plus and the green class" do
      row = doc.css("tr.exp-row").first
      expect(row.at_css("span.moss-amount-in").text.squish).to eq("+500,00 €")
      expect(doc.css("span.moss-amount-in").size).to eq(1)
    end

    it "tags the foreign-currency row with its original amount and rate" do
      row = doc.css("tr.exp-row")[1]
      expect(row.css("span.moss-tag").map(&:text)).to eq(["-425,00 PLN · Kurs 4,2500"])
      expect(doc.css("span.moss-tag").size).to eq(1)
    end

    # A row has no detail of its own -- it shows everything the booking's page
    # would repeat -- so opening it reveals nothing but the header line: two
    # double links per row, "In Moss" left of "Detailseite". The top-up row is
    # the exception: Moss has no record page for a top-up, so its line is
    # "Detailseite" alone. The summary row itself carries no link icon at all.
    it "gives every row a header line of double links, and no row icon" do
      expect(doc.css("tr.exp-row i.fa-eye")).to be_empty
      expect(response.body).not_to include("fa-info-circle")
      expect(detail_link_groups(:same_tab).map { |group| group.map { |a| a.text.squish } })
        .to eq([["Detailseite"]] + [["In Moss", "Detailseite"]] * 3)
    end

    it "opens the booking's own page from the primary link, in this tab and in a new one" do
      hrefs = [top_up, invoice, reimbursement, card].map { |b| moss_booking_path(b) }
      same = detail_link_groups(:same_tab).map(&:last)
      new_tab = detail_link_groups(:new_tab).map(&:last)
      expect(same.pluck("href")).to eq(hrefs)
      expect(same.pluck("target")).to eq([nil] * 4)
      expect(same.pluck("title")).to eq(["Detailseite öffnen"] * 4)
      expect(new_tab.pluck("href")).to eq(hrefs)
      expect(new_tab.pluck("target")).to eq(["_blank"] * 4)
      expect(new_tab.pluck("rel")).to eq(["noopener"] * 4)
      expect(new_tab.pluck("title")).to eq(["Detailseite in neuem Tab öffnen"] * 4)
    end

    it "points the In-Moss link at the booking's own transaction in Moss" do
      # Rows in Buchungsdatum order: the top-up first, then the three kinds with a
      # record page in Moss.
      urls = [invoice, reimbursement, card].map { |b| b.moss_transaction.moss_record_url }
      expect(urls).to all(start_with("https://getmoss.com/app/"))
      expect(detail_link_groups(:same_tab).drop(1).map(&:first).pluck("href")).to eq(urls)
      new_tab = detail_link_groups(:new_tab).drop(1).map(&:first)
      expect(new_tab.pluck("href")).to eq(urls)
      expect(new_tab.pluck("target")).to eq(["_blank"] * 3)
      expect(new_tab.pluck("title")).to eq(["Transaktion in Moss in neuem Tab öffnen"] * 3)
    end

    # The booking's detail loads lazily into the row, from its reading page.
    it "loads the booking's detail lazily, its frame marked with the booking" do
      frame = doc.at_css("turbo-frame[data-record='moss_booking_#{card.id}']")
      expect(frame["src"]).to start_with(moss_booking_path(card))
      expect(frame["loading"]).to eq "lazy"
    end

    # The buttons stand beside the detail, the detail kit's "Bearbeiten" with
    # them (t.detail_links_aside); the CSS shows it once the detail has loaded.
    it "puts the buttons, Bearbeiten included, in a column beside the detail" do
      bar = doc.css(".exp-detail-linkbar").first
      expect(bar["class"].split).to include("exp-detail-linkbar-aside")
      expect(bar.at_css("button.exp-edit-toggle").text.strip).to eq "Bearbeiten"
    end

    # A top-up has no record page in Moss, so its bar carries the primary link
    # only -- and no anchor of the page points into Moss for it.
    it "leaves the top-up row's header line with Detailseite alone" do
      top_up_line = detail_link_groups(:same_tab).first
      expect(top_up_line.map { |a| a.text.squish }).to eq(["Detailseite"])
      expect(top_up_line.first["href"]).to eq(moss_booking_path(top_up))
      expect(top_up.moss_transaction.moss_record_url).to be_nil
    end
  end

  # The booking's own Kostenstelle and Sachkonto are default columns, number
  # plus name; the date header falls back to "Datum" when it is too narrow.
  describe "GET index with the booking's accounting" do
    before do
      WsjrdpCostCenter.create!(number: "4711", name: "Vortreffen") unless WsjrdpCostCenter.exists?(number: "4711")
      card.update!(cost_center_number: "4711", account_number: "36100")
      get :index
    end

    def cell(key) = doc.css("tr.exp-row").last.at_css("td[data-colkey='#{key}']").text.squish

    it "shows Kostenstelle and Sachkonto by default, with their names" do
      headers = doc.css("thead th").map { |th| th.text.squish.delete("⇅") }
      expect(headers).to include("Kostenstelle", "Sachkonto")
      expect(cell("cost_center_number")).to eq("4711 Vortreffen")
      expect(cell("account_number")).to start_with("36100")
    end

    it "gives the date header a short label" do
      header = doc.at_css("thead th[data-colkey='booking_date']") ||
        doc.css("thead th").find { |th| th.text.include?("Buchungsdatum") }
      expect(header.at_css(".exp-label-full").text).to eq("Buchungsdatum")
      expect(header.at_css(".exp-label-short").text).to eq("Datum")
    end
  end

  # A card payment whose payout day falls days before the day it was booked:
  # the list places and shows it by the booking day, in the cell and in the
  # sort alike -- the raw payout day is not a column of the list at all.
  describe "GET index with a payment booked after its payout day" do
    let!(:booked_later) do
      create_booking("MossCardTransaction", amount: -40, date: Date.new(2026, 6, 15),
        text: "Anteil zwei", payment_date: Date.new(2026, 6, 9),
        merchant_name: "Musterkiosk", transaction_posting_text: "Materialkosten Vortreffen")
    end

    before { get :index }

    # The Buchungsdatum cells of the rows, top to bottom.
    def rendered_dates = doc.css("tr.exp-row td[data-colkey='booking_date']").map { |td| td.text.strip }

    it "dates the row by its booking date, in the cell and in the sort" do
      expect(response).to be_successful
      expect(response.body).to include("5 Buchungen")
      expect(rendered_dates)
        .to eq(%w[20.01.2027 15.07.2026 15.06.2026 01.06.2026 03.05.2026])
      expect(response.body).not_to include("09.06.2026")
    end
  end

  # The kinds are a fixed group of several answers (Fin::MossKinds.fixed_group),
  # as on the transactions list: one segment behind an "all" asterisk, every
  # kind chosen by default, the choice carried by the lifts param `u`.
  describe "GET index with a kind choice" do
    it "offers the kinds as one segment, all chosen" do
      get :index
      expect(doc.css(".flt-segment").size).to eq(1)
      expect(preset_links.size).to eq(5)
      expect(preset_links.first["class"].split).to include("flt-preset-icon-only")
      expect(preset_links.drop(1).map { |a| a.text.strip })
        .to eq(kinds.map { |kind| I18n.t("fin.moss.kind_chips.#{kind}") })
      expect(preset_links.drop(1).map { |a| a["class"].split.last })
        .to eq(kinds.map { |kind| Fin::MossKinds.css_class(kind) })
      expect(preset_links.pluck("aria-pressed")).to eq(%w[true true true true true])
      expect(preset_lifts(preset_links.first)).to eq("kind.-")
    end

    it "shows only the chosen kinds" do
      get :index, params: {u: "kind.card_transaction+reimbursement"}
      expect(response).to be_successful
      expect(rendered_kinds).to eq(%w[MossReimbursement MossCardTransaction]
        .map { |kind| Fin::MossKinds.css_class(kind) })
      expect(preset_links.pluck("aria-pressed")).to eq(%w[false true true false false])
    end

    it "shows nothing when no kind is chosen, and says so" do
      get :index, params: {u: "kind.-"}
      expect(rendered_kinds).to be_empty
      expect(response.body).to include("0 Buchungen")
      expect(doc.css(".flt-applied .flt-chip-locked").map { |chip| chip.text.squish }).to eq(["Art: keine gewählt"])
    end
  end

  # Betrag is one picker entry with a sign toggle: the split's signed share or
  # its magnitude. A payment out of the wallet is negative, so only |Betrag|
  # finds the big rows on either side.
  describe "GET index with an amount filter" do
    def catalog_attributes
      JSON.parse(doc.at_css(".flt-root")["data-catalog"])["attributes"]
    end

    it "filters the list on the magnitude" do
      get :index, params: {f: "!(!(!(amta,ge,100)))"}
      expect(response).to be_successful
      expect(rendered_kinds).to eq(%w[MossTopUp MossInvoice].map { |k| Fin::MossKinds.css_class(k) })
      expect(response.body).to include("2 Buchungen")

      get :index, params: {f: "!(!(!(amt,ge,100)))"}
      expect(rendered_kinds).to eq([Fin::MossKinds.css_class("MossTopUp")])
    end

    # The sign metadata reaches the builder through the catalog -- that is what
    # turns the group's sub-variant dropdown into the ± / |x| toggle.
    it "ships the sign pair in the builder's catalog" do
      get :index
      amounts = catalog_attributes.select { |a| a["variant_group"] == "Betrag" }
      expect(amounts.map { |a| [a["key"], a["label"], a["sign"]] }).to eq(
        [["amount", "Betrag", "signed"], ["amount_abs", "|Betrag|", "absolute"]]
      )
      expect(amounts.pluck("operand_min")).to eq([nil, 0])
      expect(amounts.first["operators"].pluck("key")).to eq(%w[between lte gte lt gt eq])
    end
  end

  # The filter LINE above the list (doc/wsjrdp/expandable_table.md): the kind
  # segment and the applied filter's chips on its left, the pane's toggle --
  # with the count of applied conditions -- at its right end.
  describe "the filter line" do
    def line = doc.at_css(".flt-line")

    def pane = doc.at_css(".wsjrdp-pane.flt-pane")

    def state = controller.bookings_table_state

    # The count of applied conditions next to the word "Filter"; the warning
    # pill beside it is the builder's "nicht angewendet" and carries no number.
    def condition_badge = line.at_css("button.pane-toggle .badge.bg-secondary")&.text&.strip

    it "carries the kind segment, with its icons and colours, and the toggle" do
      get :index

      expect(line).to be_present
      expect(line["data-pane-line"]).to eq(controller.helpers.et_pane_id(state))
      expect(pane["id"]).to eq(controller.helpers.et_pane_id(state))

      bar = line.at_css(".flt-line-left .flt-presets")
      expect(bar["id"]).to eq(controller.helpers.et_filter_presets_id(state))
      kind_links = bar.css("a.flt-preset").drop(1)
      expect(kind_links.map { |a| a["class"].split.last })
        .to eq(kinds.map { |kind| Fin::MossKinds.css_class(kind) })
      expect(kind_links.map { |a| a.xpath("./i").first["class"] })
        .to eq(kinds.map { |kind| "fas fa-#{Fin::MossKinds.icon(kind)}" })

      toggle = line.element_children.last
      expect(toggle.name).to eq("button")
      expect(toggle["class"].split).to include("pane-toggle")
      expect(toggle["data-pane-target"]).to eq(pane["id"])
    end

    it "chips a Buchungsdatum filter, and an amount filter, in the builder's words" do
      get :index, params: {f: "!(!(!(bd,ge,'2026-07-01')))"}
      expect(rendered_kinds.size).to eq(2)
      expect(chip_texts).to eq(["Buchungsdatum ab 01.07.2026"])

      get :index, params: {f: "!(!(!(amt,ge,100)))"}
      expect(rendered_kinds).to eq([Fin::MossKinds.css_class("MossTopUp")])
      expect(chip_texts).to eq(["Betrag ≥ 100"])
      expect(doc.css(".flt-applied .flt-chip").pluck("class")).to all(eq("flt-chip pane-opener wsjrdp-html-tip"))
    end

    # The badge counts the APPLIED conditions of the user filter -- a kind
    # condition of the user's own included; the kind segment is no condition.
    it "counts the applied conditions in the toggle's badge" do
      get :index
      expect(condition_badge).to be_nil

      get :index, params: {f: "!(!(!(bd,ge,'2026-01-01')))"}
      expect(condition_badge).to eq("1")

      get :index, params: {f: "!(!(!(k,in,'MossInvoice')),!(!(bd,ge,'2026-01-01')))"}
      expect(condition_badge).to eq("2")
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
