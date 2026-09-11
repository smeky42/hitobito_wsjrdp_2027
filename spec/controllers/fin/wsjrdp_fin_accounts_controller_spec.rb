# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The statement of ONE finance account (/fin/acc/:id). The page serves TWO kinds
# of account and branches on the one marker WsjrdpFinAccount#transactions
# branches on:
#
#   * the MOSS WALLET (transaction_type "MossBalanceMovement") -> the expandable
#     table with the kind chips, the coloured rails, the four kind buttons of the
#     "Schnellauswahl" and the detail's header line of links (the booking's own
#     page, the transaction in Moss);
#   * every BANK account -> the plain camt statement it has always been.
#
# Both branches are exercised here; all names, numbers and amounts are invented.
describe Fin::WsjrdpFinAccountsController do
  render_views

  let(:person) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

  let!(:wallet) do
    WsjrdpFinAccount.create!(short_name: "Moss-Wallet", account_identification: "MOSS-WALLET-TEST",
      transaction_type: "MossBalanceMovement", opening_balance_cents: 100_000,
      opening_balance_currency: "EUR", opening_balance_date: Date.new(2026, 1, 1))
  end

  # One transaction of `type` on the wallet, with its (shell) expense and
  # exactly one booking -- the row the statement shows. `date` is the day the
  # movement was booked in the wallet, which is what the statement is dated by.
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

  # The word a kind's button carries -- the chip word of the rows.
  def kind_word(kind) = I18n.t("fin.moss.kind_chips.#{kind}")

  # {button word => "true"/"false"} and {button word => the `f` its toggle leads
  # to}, both in the bar's order.
  def pressed_by_word = preset_links.to_h { |a| [a.text.strip, a["aria-pressed"]] }

  def toggle_by_word = preset_links.to_h { |a| [a.text.strip, preset_filter(a)] }

  # The applied filter's chips, as the line words them.
  def chip_texts = doc.css(".flt-applied .flt-chip").map { |chip| chip.text.strip }

  # The double links of every detail row's header line, in rendered order (extra
  # links first, "Detailseite" last). `part` picks the left (same tab) or the
  # right (new tab) button of each group.
  def detail_link_groups(part)
    index = (part == :new_tab) ? 1 : 0
    doc.css(".exp-detail-links").map { |line| line.css(".btn-group").map { |g| g.css("a")[index] } }
  end

  # The decoded `f` value a preset link points at ("" when it clears the filter).
  def preset_filter(link)
    CGI.unescape(CGI.unescapeHTML(link["href"].to_s)[/[?&]f=([^&]*)/, 1].to_s)
  end

  # The four kinds in their own order, and the marking each one carries.
  let(:kinds) { Fin::MossTransactionsFilterSchema::KINDS }

  describe "GET show of the Moss wallet" do
    before { get :show, params: {id: wallet.id} }

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

    # The four are the members of ONE quick-select group and therefore render as
    # four plain buttons in declaration order -- no title, no segment.
    it "offers one Schnellauswahl button per kind, in the kinds' order" do
      expect(preset_links.size).to eq(4)
      expect(preset_links.map { |a| a["class"].split })
        .to eq(kinds.map { |kind| ["btn", "btn-sm", "btn-outline-secondary", "flt-preset", Fin::MossKinds.css_class(kind)] })
      expect(preset_links.map { |a| a.text.strip }).to eq(kinds.map { |kind| kind_word(kind) })
      expect(preset_links.map { |a| a.xpath("./i").first["class"] })
        .to eq(kinds.map { |kind| "fas fa-#{Fin::MossKinds.icon(kind)}" })
    end

    it "points every button at its own kind alone, none of them pressed" do
      expect(preset_links.map { |a| preset_filter(a) })
        .to eq(kinds.map { |kind| "!(!(!(k,in,'#{kind}')))" })
      expect(preset_links.pluck("aria-pressed")).to eq(%w[false false false false])
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

    # A top-up has no record page in Moss, so its bar carries the primary link
    # only -- and no anchor of the page points into Moss for it.
    it "leaves the top-up row's header line with Detailseite alone" do
      top_up_line = detail_link_groups(:same_tab).first
      expect(top_up_line.map { |a| a.text.squish }).to eq(["Detailseite"])
      expect(top_up_line.first["href"]).to eq(moss_booking_path(top_up))
      expect(top_up.moss_transaction.moss_record_url).to be_nil
    end

    # Balances are not bookings, so they sit outside the table -- and in the
    # reading order of a statement.
    it "keeps both balance lines outside the table" do
      balances = doc.css(".mw-balance").map { |div| div.text.squish }
      expect(balances.size).to eq(2)
      expect(balances.first).to start_with("Aktuelles Saldo")
      expect(balances.last).to start_with("Eröffnungs-Saldo")
      # Both read in the money format of the lists (Fin::MoneyHelper).
      expect(balances).to all(end_with(" €"))
      expect(doc.css("table .mw-balance")).to be_empty
    end

    it "keeps the account's own form below the statement" do
      expect(response.body).to include("Moss-Wallet")
      expect(doc.at_css("form input[name='wsjrdp_fin_account[short_name]']")).to be_present
    end
  end

  # A card payment whose payout day falls days before the day it was booked:
  # the statement places and shows it by the booking day, in the cell and in the
  # sort alike -- the raw payout day is not a column of the wallet at all.
  describe "GET show of a payment booked after its payout day" do
    let!(:booked_later) do
      create_booking("MossCardTransaction", amount: -40, date: Date.new(2026, 6, 15),
        text: "Anteil zwei", payment_date: Date.new(2026, 6, 9),
        merchant_name: "Musterkiosk", transaction_posting_text: "Materialkosten Vortreffen")
    end

    before { get :show, params: {id: wallet.id} }

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

  # The four kinds are alternatives of one question, so their buttons share ONE
  # slot `kind in (…)`: a value per pressed button, and the statement widens
  # instead of narrowing to nothing (doc/wsjrdp/expandable_table.md, "Presets").
  describe "GET show with a kind filter" do
    it "shows only that kind and marks its button pressed" do
      get :show, params: {id: wallet.id, f: "!(!(!(k,in,'MossInvoice')))"}
      expect(response).to be_successful
      expect(rendered_kinds).to eq([Fin::MossKinds.css_class("MossInvoice")])
      expect(response.body).to include("1 Buchungen")
      expect(pressed_by_word)
        .to eq(kinds.to_h { |kind| [kind_word(kind), (kind == "MossInvoice").to_s] })
    end

    # Pressed again, the button takes its value out of the shared slot; the slot
    # was carrying nothing else, so the whole filter goes.
    it "lets the pressed button switch its own kind off again" do
      get :show, params: {id: wallet.id, f: "!(!(!(k,in,'MossInvoice')))"}
      invoice_link = preset_links.find { |a| a["aria-pressed"] == "true" }
      expect(preset_filter(invoice_link)).to eq("")
    end

    it "presses every button whose value the shared slot carries" do
      get :show, params: {id: wallet.id, f: "!(!(!(k,in,'MossCardTransaction','MossReimbursement')))"}
      expect(response).to be_successful
      expect(rendered_kinds).to eq(%w[MossReimbursement MossCardTransaction]
        .map { |kind| Fin::MossKinds.css_class(kind) })
      expect(pressed_by_word).to eq(kinds.to_h do |kind|
        [kind_word(kind), %w[MossCardTransaction MossReimbursement].include?(kind).to_s]
      end)
    end

    # Selecting adds to the slot that is already there, deselecting takes the one
    # value out of it -- the other values stay either way.
    it "adds to and removes from the shared slot, one value at a time" do
      get :show, params: {id: wallet.id, f: "!(!(!(k,in,'MossCardTransaction','MossReimbursement')))"}
      toggles = toggle_by_word
      expect(toggles[kind_word("MossCardTransaction")]).to eq("!(!(!(k,in,'MossReimbursement')))")
      expect(toggles[kind_word("MossReimbursement")])
        .to eq("!(!(!(k,in,'MossCardTransaction')))")
      expect(toggles[kind_word("MossInvoice")])
        .to eq("!(!(!(k,in,'MossCardTransaction','MossReimbursement','MossInvoice')))")
    end

    # Every value of the slot is a button's, so the buttons say it in full.
    it "leaves a slot of nothing but kinds unchipped" do
      get :show, params: {id: wallet.id, f: "!(!(!(k,in,'MossCardTransaction','MossReimbursement')))"}
      expect(doc.css(".flt-applied")).to be_empty
    end

    # A second OR condition asks a wider question: the slot is not the group's,
    # so no button reads it, none touches it, and the chip stays to show it.
    it "ignores a kind condition that shares its slot with another one" do
      get :show, params: {id: wallet.id, f: "!(!(!(k,in,'MossCardTransaction'),!(bd,ge,'2026-05-01')))"}
      expect(response).to be_successful
      expect(response.body).to include("4 Buchungen")
      expect(preset_links.pluck("aria-pressed")).to eq(%w[false false false false])
      expect(chip_texts).to eq(["Art ist #{I18n.t("fin.moss.kinds.MossCardTransaction")} " \
                                "oder Buchungsdatum ab 01.05.2026"])
      expect(toggle_by_word[kind_word("MossCardTransaction")])
        .to eq("!(!(!(k,in,'MossCardTransaction'),!(bd,ge,'2026-05-01')),!(!(k,in,'MossCardTransaction')))")
    end
  end

  # Betrag is one picker entry with a sign toggle: the split's signed share or
  # its magnitude. A payment out of the wallet is negative, so only |Betrag|
  # finds the big rows on either side.
  describe "GET show with an amount filter" do
    def catalog_attributes
      JSON.parse(doc.at_css(".flt-root")["data-catalog"])["attributes"]
    end

    it "filters the statement on the magnitude" do
      get :show, params: {id: wallet.id, f: "!(!(!(amta,ge,100)))"}
      expect(response).to be_successful
      expect(rendered_kinds).to eq(%w[MossTopUp MossInvoice].map { |k| Fin::MossKinds.css_class(k) })
      expect(response.body).to include("2 Buchungen")

      get :show, params: {id: wallet.id, f: "!(!(!(amt,ge,100)))"}
      expect(rendered_kinds).to eq([Fin::MossKinds.css_class("MossTopUp")])
    end

    # The sign metadata reaches the builder through the catalog -- that is what
    # turns the group's sub-variant dropdown into the ± / |x| toggle.
    it "ships the sign pair in the builder's catalog" do
      get :show, params: {id: wallet.id}
      amounts = catalog_attributes.select { |a| a["variant_group"] == "Betrag" }
      expect(amounts.map { |a| [a["key"], a["label"], a["sign"]] }).to eq(
        [["amount", "Betrag", "signed"], ["amount_abs", "|Betrag|", "absolute"]]
      )
      expect(amounts.pluck("operand_min")).to eq([nil, 0])
      expect(amounts.first["operators"].pluck("key")).to eq(%w[between lte gte lt gt eq])
    end
  end

  # The filter LINE above the statement (doc/wsjrdp/expandable_table.md): the
  # four kind buttons and the applied filter's chips on its left, the pane's
  # toggle -- with the count of applied conditions -- at its right end.
  describe "the filter line" do
    def line = doc.at_css(".flt-line")

    def pane = doc.at_css(".wsjrdp-pane.flt-pane")

    def state = controller.wallet_table_state

    # The count of applied conditions next to the word "Filter"; the warning
    # pill beside it is the builder's "nicht angewendet" and carries no number.
    def condition_badge = line.at_css("button.pane-toggle .badge.bg-secondary")&.text&.strip

    it "carries the four kind buttons, with their icons and colours, and the toggle" do
      get :show, params: {id: wallet.id}

      expect(line).to be_present
      expect(line["data-pane-line"]).to eq(controller.helpers.et_pane_id(state))
      expect(pane["id"]).to eq(controller.helpers.et_pane_id(state))

      bar = line.at_css(".flt-line-left .flt-presets")
      expect(bar["id"]).to eq(controller.helpers.et_filter_presets_id(state))
      expect(bar.css("a.flt-preset").map { |a| a["class"].split.last })
        .to eq(kinds.map { |kind| Fin::MossKinds.css_class(kind) })
      expect(bar.css("a.flt-preset").map { |a| a.xpath("./i").first["class"] })
        .to eq(kinds.map { |kind| "fas fa-#{Fin::MossKinds.icon(kind)}" })

      toggle = line.element_children.last
      expect(toggle.name).to eq("button")
      expect(toggle["class"].split).to include("pane-toggle")
      expect(toggle["data-pane-target"]).to eq(pane["id"])
    end

    it "chips a Buchungsdatum filter, and an amount filter, in the builder's words" do
      get :show, params: {id: wallet.id, f: "!(!(!(bd,ge,'2026-07-01')))"}
      expect(rendered_kinds.size).to eq(2)
      expect(chip_texts).to eq(["Buchungsdatum ab 01.07.2026"])

      get :show, params: {id: wallet.id, f: "!(!(!(amt,ge,100)))"}
      expect(rendered_kinds).to eq([Fin::MossKinds.css_class("MossTopUp")])
      expect(chip_texts).to eq(["Betrag ≥ 100"])
      expect(doc.css(".flt-applied .flt-chip").pluck("class")).to all(eq("flt-chip pane-opener"))
    end

    # The pressed button already shows that slot, so the kind gets no chip --
    # the second slot still does.
    it "leaves the kind slot of a PRESSED button unchipped" do
      get :show, params: {id: wallet.id, f: "!(!(!(k,in,'MossInvoice')))"}
      expect(preset_links.find { |a| a["aria-pressed"] == "true" }.text.strip)
        .to eq(I18n.t("fin.moss.kind_chips.MossInvoice"))
      expect(doc.css(".flt-applied")).to be_empty

      get :show, params: {id: wallet.id,
                          f: "!(!(!(k,in,'MossInvoice')),!(!(bd,ge,'2026-01-01')))"}
      expect(chip_texts).to eq(["Buchungsdatum ab 01.01.2026"])
    end

    # The badge counts the APPLIED conditions of the user filter -- the kinds'
    # own slot included, unlike the chips.
    it "counts the applied conditions in the toggle's badge" do
      get :show, params: {id: wallet.id}
      expect(condition_badge).to be_nil

      get :show, params: {id: wallet.id, f: "!(!(!(bd,ge,'2026-01-01')))"}
      expect(condition_badge).to eq("1")

      get :show, params: {id: wallet.id,
                          f: "!(!(!(k,in,'MossInvoice')),!(!(bd,ge,'2026-01-01')))"}
      expect(condition_badge).to eq("2")
      expect(chip_texts.size).to eq(1)
    end
  end

  describe "POST apply" do
    it "encodes the posted tree and redirects (PRG) back to this account" do
      post :apply, params: {id: wallet.id, filter_json: [[["kind", "in", "MossTopUp"]]].to_json}
      expect(response).to have_http_status(:see_other)
      expect(CGI.unescape(response.location))
        .to end_with("/fin/acc/#{wallet.id}?f=!(!(!(k,in,'MossTopUp')))")
    end

    it "emits a blank filter param when every condition was removed" do
      post :apply, params: {id: wallet.id, filter_json: "[]"}
      expect(response).to have_http_status(:see_other)
      expect(response.location).to end_with("/fin/acc/#{wallet.id}?f=")
    end
  end

  # The other branch of the same template: a bank account keeps the plain camt
  # table, unchanged -- no filter, no presets, no kind marking, and the info
  # icon it has always had.
  describe "GET show of a bank account" do
    let!(:bank) do
      WsjrdpFinAccount.create!(short_name: "Vereinskonto", account_identification: "BANK-TEST",
        opening_balance_cents: 0, opening_balance_currency: "EUR",
        opening_balance_date: Date.new(2026, 1, 1))
    end

    let!(:camt) do
      WsjrdpCamtTransaction.create!(fin_account: bank, camt_type: "CAMT053",
        account_identification: bank.account_identification, account_servicer_reference: "REF-1",
        credit_debit_indication: "DBIT", signed_base_amount: -12.34, base_currency: "EUR",
        value_date: Date.new(2026, 4, 2), description: "Beispielbuchung")
    end

    it "renders the unchanged camt statement" do
      get :show, params: {id: bank.id}
      expect(response).to be_successful
      expect(response.body).to include("Beispielbuchung")
        .and include("Aktuelles Saldo").and include("Eröffnungs-Saldo")
      expect(doc.css("a[href='#{wsjrdp_camt_transaction_path(camt)}'] span.fa-info-circle")).to be_present
      expect(response.body).not_to include("flt-preset")
      expect(response.body).not_to include("moss-kind")
      expect(doc.css("tr.exp-row")).to be_empty
    end
  end
end
