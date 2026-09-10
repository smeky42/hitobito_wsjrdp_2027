# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Moss "Transaktionen" tab: the expandable table over all kinds, the CNF
# filter (Fin::MossTransactionsFilterSchema) in the URL, the PRG apply and the detail.
#
# The table state (doc/plans/2026-09_expandable-table-state.md) is exercised
# through its one-letter params: ?s= sort, ?c= columns, ?f= filter, ?z= page
# size, ?p= page, ?r=1 reset -- plus what this page REMEMBERS in the session.
describe Fin::MossTransactionsController do
  render_views

  let(:person) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

  # One transaction with one expense and one booking (the uniform shape).
  def create_transaction(type, amount:, **attrs)
    uuid = SecureRandom.uuid
    tx = MossTransaction.create!(type: type, moss_transaction_uuid: uuid,
      signed_total_base_amount: amount, currency: "EUR",
      payment_date: Date.new(2026, 5, 3), transaction_posting_text: "Verpflegung Vortreffen", **attrs)
    expense = MossExpense.create!(moss_transaction: tx, moss_expense_uuid: uuid,
      type: "#{type}Expense", expense_number: 1, signed_expense_base_amount: amount)
    MossBooking.create!(moss_transaction: tx, moss_expense: expense,
      sub_row_number: 1, signed_base_amount: amount,
      account_number: "66500", account_kind: "EXPENSE", cost_center_number: "3100",
      booking_posting_text: "Split eins")
    tx
  end

  let!(:card) { create_transaction("MossCardTransaction", amount: -23.35, merchant_name: "Supermarkt Muster") }
  let!(:top_up) { create_transaction("MossTopUp", amount: 500, top_up_sender: "Vereinskonto") }

  before { sign_in(person) }

  # Which of the two transactions the rendered table shows first. Both are
  # identified by text of the (default-visible) description column.
  def first_row
    card_at = response.body.index("Supermarkt Muster")
    top_up_at = response.body.index("Vereinskonto")
    raise "expected both transactions in the body" if card_at.nil? || top_up_at.nil?
    (card_at < top_up_at) ? :card : :top_up
  end

  describe "GET index" do
    it "lists every kind through the expandable table" do
      get :index
      expect(response).to be_successful
      expect(response.body).to include("Supermarkt Muster").and include("Einzahlung")
      expect(response.body).to include("2 Transaktionen")
    end

    it "applies a Rison ?f= filter on the kind" do
      get :index, params: {f: "!(!(!(k,in,MossTopUp)))"}
      expect(response).to be_successful
      expect(response.body).to include("Vereinskonto")
      expect(response.body).not_to include("Supermarkt Muster")
      expect(response.body).to include("1 Transaktionen")
    end

    it "filters on booking-level attributes without duplicating transactions" do
      get :index, params: {f: "!(!(!(acc,in,'66500')))"}
      expect(response).to be_successful
      expect(response.body).to include("2 Transaktionen")
    end

    # Both transactions share a payment_date, so the policy default
    # (payment_date desc) leaves them in id order -- the amount sort is what
    # visibly reorders them.
    it "sorts by the ?s= column and direction" do
      get :index
      expect(first_row).to eq :card

      get :index, params: {s: "amt~"}
      expect(response).to be_successful
      expect(first_row).to eq :top_up

      get :index, params: {s: "amt"}
      expect(first_row).to eq :card
    end

    # Every row's detail is rendered (collapsed) with the page, so the merchant
    # name is in the body either way -- the per-column CSS class is what tells
    # visible columns apart.
    it "shows exactly the ?c= columns" do
      get :index
      expect(response.body).to include("mtcol-description")
      expect(response.body).not_to include("mtcol-party")

      get :index, params: {c: "pty"}
      expect(response).to be_successful
      expect(response.body).to include("mtcol-party")
      expect(response.body).not_to include("mtcol-description")
    end

    # Buchungen holds a one- or two-digit count and is therefore the narrowest
    # column of the table -- with a header short enough to fit into it.
    it "gives the Buchungen column a short header and a narrow width" do
      get :index, params: {c: "dsc,nb"}
      expect(response).to be_successful
      header = Nokogiri::HTML(response.body).at_css("thead th[data-colkey='bookings_count']")
      expect(header.text.squish).to eq("Bu.")
      expect(header["style"]).to eq("width: 3rem")
    end

    it "restores the remembered sort on a bare revisit" do
      get :index, params: {s: "amt~"}
      expect(first_row).to eq :top_up

      get :index
      expect(response).to be_successful
      expect(first_row).to eq :top_up
    end

    it "remembers the filter, an explicitly blank ?f= clears it again" do
      get :index, params: {f: "!(!(!(k,in,MossTopUp)))"}
      expect(response.body).to include("1 Transaktionen")

      get :index
      expect(response.body).to include("1 Transaktionen")

      # A present-but-blank param is the explicit "empty" that beats the store.
      # The non-default sort rides along on purpose: Wsjrdp::TableState::Resolver
      # only touches the store when at least one remembered field differs from
      # its default, so an all-default request would leave the stale entry --
      # ?r=1 (below) is what clears the state wholesale today.
      get :index, params: {f: "", s: "amt~"}
      expect(response.body).to include("2 Transaktionen")

      get :index
      expect(response.body).to include("2 Transaktionen")
    end

    it "offers a 'Filter zurücksetzen' that clears only the filter" do
      get :index, params: {s: "amt~", z: "25", f: "!(!(!(k,in,MossTopUp)))"}
      reset = response.body[/href="([^"]*)"[^>]*>Filter zurücksetzen/, 1]
      # Blank filter param (no default declared; present, so it beats the
      # remembered value), sort and page size kept, this table's page and open
      # rows dropped (D4).
      expect(reset).to eq("/fin/moss/transactions?f=&amp;s=amt~&amp;z=25")

      get :index, params: {f: "", s: "amt~", z: "25"}
      expect(response.body).to include("2 Transaktionen")
      expect(first_row).to eq :top_up # the remembered sort is still in force
    end

    it "forgets everything it remembered on ?r=1" do
      get :index, params: {s: "amt~", f: "!(!(!(k,in,MossTopUp)))"}
      expect(response.body).to include("1 Transaktionen")

      get :index, params: {r: "1"}
      expect(response).to have_http_status(:redirect)
      expect(response.location).to end_with("/fin/moss/transactions")

      get :index
      expect(response).to be_successful
      expect(response.body).to include("2 Transaktionen")
      expect(first_row).to eq :card
    end

    it "falls back to page 1 when the page is beyond the last one" do
      get :index, params: {z: "1", p: "5"}
      expect(response).to be_successful
      expect(response.body).to include("2 Transaktionen")
      expect(response.body).to include("Supermarkt Muster")
      expect(response.body).not_to include("Vereinskonto")
    end

    # The jump field next to the page links: the current page, bounded by the
    # page count, and a URL template for this table's page param (open rows
    # dropped, the page size carried).
    it "renders the page jump field with the current page and the page count" do
      get :index, params: {z: "1", p: "2"}
      expect(response).to be_successful
      input = Nokogiri::HTML(response.body).css("input.bk-page-input").first
      expect(input).to be_present
      expect(input["value"]).to eq("2")
      expect(input["max"]).to eq("2")
      expect(input["data-max"]).to eq("2")
      expect(CGI.unescape(input["data-url-template"])).to eq("/fin/moss/transactions?p=__PAGE__&z=1")
      expect(response.body).to include("von 2")
    end
  end

  # The two amounts of this page -- the transaction total and the "alle Ebenen"
  # search over transaction, expense and booking -- are one picker entry each,
  # with a sign toggle between the signed member and its ABS() twin. The
  # dataset has no schema spec of its own, so the compiled SQL is asserted here
  # next to the rendered result.
  describe "the amounts and their sign pairs" do
    let(:schema) { Fin::MossTransactionsFilterSchema.bound }

    def compile(tree)
      Wsjrdp::Filtering::Compiler.new(schema)
        .apply(Wsjrdp::Filtering::Query.parse(tree)).to_sql
    end

    def catalog_attributes
      JSON.parse(Nokogiri::HTML(response.body).at_css(".flt-root")["data-catalog"])["attributes"]
    end

    # Money leaving the wallet is negative, so only the magnitude sees both
    # directions at once.
    it "finds either direction through |Betrag (Transaktion)|" do
      get :index, params: {f: "!(!(!(amta,ge,100)))"}
      expect(response).to be_successful
      expect(response.body).to include("1 Transaktionen").and include("Vereinskonto")
      expect(response.body).not_to include("Supermarkt Muster")

      get :index, params: {f: "!(!(!(amta,bt,20,30)))"}
      expect(response.body).to include("1 Transaktionen").and include("Supermarkt Muster")
      expect(response.body).not_to include("Vereinskonto")
    end

    it "matches any of the three levels through |Betrag (alle Ebenen)|" do
      get :index, params: {f: "!(!(!(amaa,bt,20,30)))"}
      expect(response).to be_successful
      expect(response.body).to include("1 Transaktionen").and include("Supermarkt Muster")
    end

    it "wraps the transaction column, and all three levels, in ABS()" do
      expect(compile([[["amount_abs", "gte", 100]]]))
        .to include(%(ABS("moss_transactions"."signed_total_base_amount") >= 100))
      sql = compile([[["amount_any_abs", "gte", 100]]])
      expect(sql).to include(%(ABS("moss_transactions"."signed_total_base_amount") >= 100))
        .and include(%(ABS("moss_expenses"."signed_expense_base_amount") >= 100))
        .and include(%(ABS("moss_bookings"."signed_base_amount") >= 100))
      expect(sql.scan("ABS(").size).to eq(3)
      expect(sql).to include(" OR ")
    end

    it "offers the same operator list on all four, the range first" do
      %i[amount amount_abs amount_any amount_any_abs].each do |key|
        expect(schema.find(key).operators.map(&:key)).to eq(%i[between lte gte lt gt eq])
        expect(schema.find(key).pickable_operators.map(&:key)).to eq(%i[between lte gte lt gt eq])
        expect(schema.find(key).operators.map(&:label))
          .to eq(["im Bereich", "≤", "≥", "<", ">", "="])
      end
      expect(schema.attributes.values.map(&:short_key)).to include(:amt, :amta, :ama, :amaa)
    end

    # The sign metadata reaches the builder through the catalog -- that is what
    # turns a group's sub-variant dropdown into the ± / |x| toggle.
    it "renders both pairs in the builder's catalog" do
      get :index
      amounts = catalog_attributes.select { |a| a["variant_group"].to_s.start_with?("Betrag") }
      expect(amounts.map { |a| [a["key"], a["variant_group"], a["sign"]] }).to eq(
        [["amount", "Betrag (Transaktion)", "signed"],
          ["amount_abs", "Betrag (Transaktion)", "absolute"],
          ["amount_any", "Betrag (alle Ebenen)", "signed"],
          ["amount_any_abs", "Betrag (alle Ebenen)", "absolute"]]
      )
      expect(amounts.pluck("operand_min")).to eq([nil, 0, nil, 0])
      expect(amounts.first["operators"].pluck("key")).to eq(%w[between lte gte lt gt eq])
    end
  end

  # The kind tabs: the same index, pinned to one kind by the route default
  # (config/routes.rb). The controller test routes the `kind` param through the
  # kind route, so it arrives as a path parameter -- as in a real request.
  describe "GET index on a kind tab" do
    it "has a route and a tab label for every kind" do
      Fin::MossTransactionsController::KIND_TABS.each_value do |slug|
        expect(Rails.application.routes.url_helpers).to respond_to("moss_#{slug}_path")
        expect(I18n.t("fin.tabs.#{slug}", default: "")).to be_present
      end
      expect(Fin::MossTransactionsController::KIND_TABS.keys).to eq(Fin::MossTransactionsFilterSchema::KINDS)
    end

    it "shows only its kind, titled by the tab, without offering the Art attribute" do
      get :index, params: {kind: "MossTopUp"}
      expect(response).to be_successful
      expect(request.path).to eq("/fin/moss/top_ups")
      expect(response.body).to include("<h1>Einzahlungen</h1>")
      expect(response.body).to include("Vereinskonto")
      expect(response.body).not_to include("Supermarkt Muster")
      expect(response.body).to include("1 Transaktionen")
      # The pinned kind is a hidden slot: "Art" is neither a filter attribute of
      # the builder's catalog (a JSON data attribute, HTML-escaped) nor a column
      # of the picker here.
      expect(response.body).not_to include("&quot;key&quot;:&quot;kind&quot;")
      expect(response.body).not_to include("mtcol-kind")
      expect(response.body).not_to include("chk-kind")
    end

    it "keeps the Art attribute and column on the general tab" do
      get :index
      expect(response.body).to include("&quot;key&quot;:&quot;kind&quot;")
      expect(response.body).to include("chk-kind")
    end

    it "shows the kind's own default columns" do
      get :index, params: {kind: "MossCardTransaction"}
      expect(response).to be_successful
      expect(response.body).to include("mtcol-card_holder_name")
      expect(response.body).not_to include("mtcol-kind")

      get :index, params: {kind: "MossInvoice"}
      expect(response.body).to include("mtcol-invoice_number").and include("mtcol-supplier_account_number")

      get :index, params: {kind: "MossReimbursement"}
      expect(response.body).to include("mtcol-recipient_name").and include("mtcol-bookings_count")

      get :index, params: {kind: "MossTopUp"}
      expect(response.body).not_to include("mtcol-cost_centers")
    end

    it "remembers each tab's state apart from the others" do
      get :index, params: {kind: "MossCardTransaction", c: "inv"}
      expect(response.body).to include("mtcol-invoice_number")

      get :index
      expect(response.body).not_to include("mtcol-invoice_number")

      get :index, params: {kind: "MossCardTransaction"}
      expect(response.body).to include("mtcol-invoice_number")
    end

    it "ignores a ?kind= query param on the general tab" do
      get :index, params: {kind: "Bogus"}
      expect(response).to be_successful
      expect(request.path).to eq("/fin/moss/transactions")
      expect(response.body).to include("2 Transaktionen")
    end
  end

  # A reimbursement pays out several Ausgaben (MossExpense, level 2), each of
  # which carries its own Buchungen (MossBooking, level 3). From two Ausgaben on,
  # the list shows one row per Ausgabe below the transaction's head row -- inside
  # the same row group and through the table's own columns
  # (Fin::MossExpenseRowsHelper says which rows those are and what their cells
  # show, shared/wsjrdp/_expandable_table renders them). Every name, code and
  # amount below is invented.
  describe "expense rows" do
    def doc = Nokogiri::HTML(response.body)

    # The row group of one transaction -- head row, expense rows and detail row
    # in one <tbody class="exp-group"> -- found by the key its detail carries.
    def group(transaction)
      doc.css("tbody.exp-group")
        .find { |tbody| tbody.at_css(".exp-detail[data-exp-key='#{transaction.id}']") }
    end

    def sub_rows(transaction) = group(transaction).css("tr.exp-sub-row")

    def cell(row, key) = row.at_css("td[data-colkey='#{key}']")

    def cell_texts(rows, key) = rows.map { |row| cell(row, key).text.squish }

    # What each row of a group is, in document order.
    def row_kinds(transaction) = group(transaction).element_children.map { |row| row_kind(row) }

    def row_kind(row)
      classes = row["class"].to_s.split
      return :head if classes.include?("exp-row")
      return :detail if classes.include?("exp-detail-row")
      return :rest if classes.include?("moss-expense-rest")
      return :collapse if classes.include?("moss-expense-collapse")
      classes.include?("moss-expense-extra") ? :hidden_expense : :expense
    end

    # A transaction with one Ausgabe per entry, each Ausgabe with ONE Buchung:
    # an entry names the Ausgabe's amount, its words and its two codes. The
    # transaction total is the sum of its Ausgaben, so the head row and the rows
    # of its group show the same money.
    def create_grouped(type, *entries, **attrs)
      uuid = SecureRandom.uuid
      tx = MossTransaction.create!(type: type, moss_transaction_uuid: uuid, currency: "EUR",
        payment_date: Date.new(2026, 5, 3),
        signed_total_base_amount: entries.sum { |entry| entry.fetch(:amount) }, **attrs)
      entries.each_with_index { |entry, index| grouped_expense(tx, index + 1, **entry) }
      tx.reload
    end

    def grouped_expense(tx, number, amount:, name: nil, text: nil,
      account: "66910", cost_center: "2300")
      expense = MossExpense.create!(moss_transaction: tx, type: "#{tx.type}Expense",
        moss_expense_uuid: SecureRandom.uuid, expense_number: number,
        signed_expense_base_amount: amount, expense_name: name, expense_posting_text: text)
      MossBooking.create!(moss_transaction: tx, moss_expense: expense, account_kind: "EXPENSE",
        signed_base_amount: amount, sub_row_number: 1,
        account_number: account, cost_center_number: cost_center)
    end

    def reimbursement_with(*entries, **attrs)
      create_grouped("MossReimbursement", *entries, **attrs)
    end

    # The two-Ausgaben reimbursement of this block. The second Ausgabe's
    # Buchungstext only repeats its name, so its row shows the name alone; the
    # first one's says something else and goes in italics behind a dash.
    let!(:reimbursement) do
      reimbursement_with(
        {amount: -45.5, name: "Bahnfahrt Vortreffen", text: "Hin- und Rückfahrt"},
        {amount: -30.25, name: "Verpflegung Samstag", text: "Verpflegung Samstag",
         account: "68000", cost_center: "2500"},
        transaction_name: "Vortreffen Nordlicht", recipient_name: "Musterperson"
      )
    end

    # The general tab's default columns plus Buchungen, which only the
    # Erstattungen tab shows by itself (KIND_COLUMNS).
    let(:group_columns) { {c: "pdt,amt,dsc,acc,cc,nb"} }

    it "puts one expense row per Ausgabe between the head row and the detail row" do
      get :index
      expect(response).to be_successful
      expect(row_kinds(reimbursement)).to eq(%i[head expense expense detail])
      expect(group(reimbursement).css("tr.exp-sub-row.moss-expense-row").size).to eq(2)
      expect(group(reimbursement).element_children.last["class"]).to eq("exp-detail-row")
      # Datum and Art stay empty on an expense row -- the head row above says
      # both for the whole group.
      expect(cell_texts(sub_rows(reimbursement), "payment_date")).to eq(["", ""])
      expect(cell_texts(sub_rows(reimbursement), "kind")).to eq(["", ""])
    end

    it "shows the transaction total in the head row and each Ausgabe's amount below it" do
      get :index
      head = group(reimbursement).at_css("tr.exp-row")
      expect(cell(head, "signed_total_base_amount").text.squish).to eq("-75,75 €")

      amounts = sub_rows(reimbursement)
        .map { |row| cell(row, "signed_total_base_amount").at_css("span") }
      expect(amounts.pluck("class")).to eq(["moss-expense-amount text-muted"] * 2)
      expect(amounts.map { |span| span.text.squish }).to eq(["-45,50 €", "-30,25 €"])
    end

    it "writes the ordinal, the name and -- when it differs -- the Buchungstext" do
      get :index
      cells = sub_rows(reimbursement).map { |row| cell(row, "description") }
      expect(cells.map { |desc| desc.at_css("span.moss-expense-ordinal").text }).to eq(%w[1 2])
      expect(cells.first.at_css("i").text).to eq("Hin- und Rückfahrt")
      expect(cells.first.text.squish).to eq("1Bahnfahrt Vortreffen – Hin- und Rückfahrt")
      expect(cells.last.at_css("i")).to be_nil
      expect(cells.last.text.squish).to eq("2Verpflegung Samstag")
    end

    it "shows each Ausgabe's Sachkonto, Kostenstelle and Buchungen count" do
      get :index, params: group_columns
      rows = sub_rows(reimbursement)
      expect(cell_texts(rows, "account_numbers")).to eq(%w[66910 68000])
      expect(cell_texts(rows, "cost_centers")).to eq(%w[2300 2500])
      expect(cell_texts(rows, "bookings_count")).to eq(%w[1 1])
      # The head row keeps aggregating over the whole transaction: both codes
      # (each on its own line, hence the <br>) and both Buchungen.
      head = group(reimbursement).at_css("tr.exp-row")
      expect(cell(head, "account_numbers").css("br").size).to eq(1)
      expect(cell(head, "bookings_count").text.squish).to eq("2")
    end

    # An expense row is content, not a control: the head row alone opens the
    # transaction's detail.
    it "lets an expense row toggle its group's detail, without a detail of its own" do
      get :index
      head = group(reimbursement).at_css("tr.exp-row")
      expect(head["role"]).to eq("button")
      expect(head["data-bs-toggle"]).to eq("collapse")

      sub_rows(reimbursement).each do |row|
        expect(row["role"]).to eq("button")
        expect(row["data-bs-toggle"]).to eq("collapse")
        expect(row["data-bs-target"]).to eq(head["data-bs-target"])
        expect(row["aria-expanded"]).to eq(head["aria-expanded"])
        expect(row.css(".collapse, i.fa-eye")).to be_empty
      end
    end

    it "leaves a reimbursement with one Ausgabe, and a card payment, single rows" do
      single = reimbursement_with({amount: -12.4, name: "Portokosten"},
        transaction_name: "Nachversand")
      # Two Ausgaben -- but a card payment has no real middle level, so it keeps
      # its single row whatever its expenses look like.
      card_with_two = create_grouped("MossCardTransaction",
        {amount: -8.5, name: "Position eins"}, {amount: -4.2, name: "Position zwei"},
        merchant_name: "Musterkiosk")

      get :index
      expect(response).to be_successful
      expect(row_kinds(single)).to eq(%i[head detail])
      expect(sub_rows(single)).to be_empty
      expect(sub_rows(card_with_two)).to be_empty
      expect(sub_rows(card)).to be_empty
    end

    it "caps a group at four expense rows, behind a rest row that reveals the fifth" do
      entries = [-10, -20, -30, -40, -9].each_with_index
        .map { |amount, index| {amount: amount, name: "Position #{index + 1}"} }
      many = reimbursement_with(*entries, transaction_name: "Sammelerstattung")

      get :index, params: group_columns
      expect(row_kinds(many))
        .to eq(%i[head expense expense expense expense hidden_expense rest collapse detail])
      expect(group(many).css("tr.moss-expense-extra.d-none").size).to eq(1)
      expect(group(many).css("tr.moss-expense-collapse.d-none").size).to eq(1)

      rest = group(many).at_css("tr.moss-expense-rest")
      expect(cell(rest, "description").text.squish).to eq("▸ 1 weitere Ausgabe anzeigen")
      expect(cell(rest, "description").at_css("a")["data-moss-expense-toggle"]).to eq("expand")
      # Betrag stays additive: the four rows above plus the rest row are the head
      # row's amount.
      expect(cell(rest, "signed_total_base_amount").text.squish).to eq("-9,00 €")
      expect(cell(rest, "bookings_count").text.squish).to eq("1")

      collapse = group(many).at_css("tr.moss-expense-collapse")
      expect(cell(collapse, "description").text.squish).to eq("▴ einklappen")
      expect(cell(collapse, "description").at_css("a")["data-moss-expense-toggle"])
        .to eq("collapse")
      expect(cell(collapse, "signed_total_base_amount").text).to eq("")
    end

    it "hides a column in the whole group, head row and expense rows alike" do
      # The default columns without Sachkonten, plus Buchungen.
      get :index, params: {c: "pdt,amt,dsc,cc,nb"}
      expect(response).to be_successful
      visible = %w[payment_date signed_total_base_amount description cost_centers bookings_count]
      expect(doc.css("thead th.exp-col").pluck("data-colkey")).to eq(visible)
      expect(group(reimbursement).at_css("tr.exp-row").css("td").pluck("data-colkey")).to eq(visible)
      expect(sub_rows(reimbursement).map { |row| row.css("td").pluck("data-colkey") })
        .to eq([visible, visible])
      expect(doc.css("tr.exp-sub-row td[data-colkey='account_numbers']")).to be_empty
    end

    # Nothing about the expense rows reaches the sort, the paging or the count:
    # a group travels with its head row and is counted as the one transaction it
    # belongs to.
    it "counts and pages transactions only, each group travelling with its head row" do
      get :index, params: {s: "amt", z: "1", p: "1"}
      expect(response).to be_successful
      expect(response.body).to include("3 Transaktionen").and include("von 3")
      # Ascending by Betrag, the reimbursement (-75,75) is the smallest of the
      # three -- and brings its two expense rows onto its page.
      expect(doc.css("tbody.exp-group").size).to eq(1)
      expect(group(reimbursement)).to be_present
      expect(sub_rows(reimbursement).size).to eq(2)

      get :index, params: {s: "amt", z: "1", p: "2"}
      expect(response.body).to include("3 Transaktionen")
      expect(doc.css("tbody.exp-group").size).to eq(1)
      expect(group(card)).to be_present
      expect(doc.css("tr.exp-sub-row")).to be_empty
    end

    it "shows the same group on the Erstattungen tab, whose columns include Buchungen" do
      get :index, params: {kind: "MossReimbursement"}
      expect(response).to be_successful
      expect(request.path).to eq("/fin/moss/reimbursements")
      expect(response.body).to include("1 Transaktionen")
      expect(row_kinds(reimbursement)).to eq(%i[head expense expense detail])

      rows = sub_rows(reimbursement)
      expect(rows.first.css("td").pluck("data-colkey")).to eq(
        %w[payment_date signed_total_base_amount description recipient_name bookings_count
          cost_centers account_numbers]
      )
      expect(cell_texts(rows, "bookings_count")).to eq(%w[1 1])
      expect(cell_texts(rows, "account_numbers")).to eq(%w[66910 68000])
      # Empfänger, like every other column an expense row does not fill, is
      # rendered and shows nothing; the head row above says it for the group.
      expect(cell_texts(rows, "recipient_name")).to eq(["", ""])
      head = group(reimbursement).at_css("tr.exp-row")
      expect(cell(head, "payment_date").text.squish).to eq("03.05.2026")
      expect(cell(head, "recipient_name").text.squish).to eq("Musterperson")
    end
  end

  # Every detail row opens with the header line of double links: "In Moss"
  # (the transaction's record in Moss) left of the primary "Detailseite". Each
  # double link is a button group whose left half stays in this tab and whose
  # right half opens the same URL in a new one; the summary row carries none.
  # A top-up is the kind Moss has no record page for, so its line carries the
  # primary link alone.
  describe "the detail's header line" do
    def doc = Nokogiri::HTML(response.body)

    # [same-tab anchor, new-tab anchor] per double link, of the first row's line.
    def link_groups
      doc.css(".exp-detail-links").first.css(".btn-group").map { |group| group.css("a").to_a }
    end

    # The label of every double link, one array per row, in rendered order.
    def labels_per_row
      doc.css(".exp-detail-links")
        .map { |line| line.css(".btn-group").map { |group| group.css("a").first.text.squish } }
    end

    before { get :index, params: {s: "amt"} }

    it "shows In Moss left of Detailseite, and no icon in the summary row" do
      expect(doc.css("tr.exp-row i.fa-eye")).to be_empty
      expect(link_groups.map { |same, _| same.text.squish }).to eq(["In Moss", "Detailseite"])
      expect(link_groups.map { |same, _| same.at_css("i")["class"] })
        .to eq(["fas fa-wallet", "fas fa-eye"])
    end

    it "links the transaction's Moss record and its own page, each also in a new tab" do
      # Ascending by amount, so the card transaction (negative) comes first.
      expect(link_groups.map { |same, _| same["href"] })
        .to eq([card.moss_record_url, moss_transaction_path(card)])
      expect(link_groups.map { |_, new_tab| new_tab["href"] })
        .to eq([card.moss_record_url, moss_transaction_path(card)])
      expect(link_groups.map { |_, new_tab| new_tab["target"] }).to eq(%w[_blank _blank])
      expect(link_groups.map { |_, new_tab| new_tab["rel"] }).to eq(%w[noopener noopener])
      expect(link_groups.map { |_, new_tab| new_tab["title"] })
        .to eq(["Transaktion in Moss in neuem Tab öffnen", "Detailseite in neuem Tab öffnen"])
    end

    # Ascending by amount: the reimbursement (most negative) first, then the
    # card payment, then the top-up. Only the top-up loses its "In Moss" group.
    it "drops the In-Moss group on a top-up and keeps it on a reimbursement" do
      payout = create_transaction("MossReimbursement", amount: -60,
        moss_reimbursement_uuid: SecureRandom.uuid, transaction_name: "Fahrtkosten Vortreffen")

      get :index, params: {s: "amt"}

      expect(labels_per_row)
        .to eq([["In Moss", "Detailseite"], ["In Moss", "Detailseite"], ["Detailseite"]])
      hrefs = doc.css(".exp-detail-links").map { |line| line.css("a").first["href"] }
      expect(hrefs)
        .to eq([payout.moss_record_url, card.moss_record_url, moss_transaction_path(top_up)])
      expect(hrefs.last).not_to include("getmoss.com")
    end
  end

  # The filter LINE above the table (doc/wsjrdp/expandable_table.md): on the
  # general tab the four kind buttons of the "Schnellauswahl"
  # (Fin::MossKinds.preset_group, the same group the wallet statement shows) and
  # the applied filter's chips, on a kind tab neither -- the tab pins its kind
  # itself.
  describe "the filter line" do
    def doc = Nokogiri::HTML(response.body)

    def line = doc.at_css(".flt-line")

    def chip_texts = doc.css(".flt-applied .flt-chip").map { |chip| chip.text.strip }

    def preset_links = doc.css("a.flt-preset")

    # The decoded `f` value a preset button points at ("" when it clears the
    # filter).
    def preset_filter(link)
      CGI.unescape(CGI.unescapeHTML(link["href"].to_s)[/[?&]f=([^&]*)/, 1].to_s)
    end

    let(:kinds) { Fin::MossTransactionsFilterSchema::KINDS }

    # The four are the members of ONE group and therefore render as four plain
    # buttons in the kinds' own order, worded and marked like the "Art" cells of
    # the rows.
    it "offers one Schnellauswahl button per kind on the general tab" do
      get :index

      expect(line).to be_present
      expect(preset_links.size).to eq(4)
      expect(preset_links.map { |a| a.text.strip })
        .to eq(kinds.map { |kind| I18n.t("fin.moss.kind_chips.#{kind}") })
      expect(preset_links.map { |a| a.xpath("./i").first["class"] })
        .to eq(kinds.map { |kind| "fas fa-#{Fin::MossKinds.icon(kind)}" })
      expect(preset_links.map { |a| a["class"].split.last })
        .to eq(kinds.map { |kind| Fin::MossKinds.css_class(kind) })

      toggle = line.element_children.last
      expect(toggle["class"].split).to include("pane-toggle")
      expect(toggle["data-pane-target"]).to eq(doc.at_css(".wsjrdp-pane.flt-pane")["id"])
    end

    # Each button points at its OWN kind alone; two pressed ones share the one
    # `kind in (…)` slot the group stands for.
    it "points every button at its kind and presses the one the filter names" do
      get :index

      expect(preset_links.map { |a| preset_filter(a) })
        .to eq(kinds.map { |kind| "!(!(!(k,in,'#{kind}')))" })
      expect(preset_links.pluck("aria-pressed")).to eq(%w[false false false false])
      # A bar of buttons IS the line's left half: "Kein Filter aktiv" would only
      # repeat what four unpressed buttons already say.
      expect(doc.css(".flt-nofilter")).to be_empty
      expect(doc.css(".flt-applied")).to be_empty

      get :index, params: {f: "!(!(!(k,in,MossTopUp)))"}
      expect(response.body).to include("1 Transaktionen")
      expect(preset_links.pluck("aria-pressed")).to eq(%w[false false false true])
    end

    # The tab pins its kind as a HIDDEN fixed slot: a button offering another
    # kind would promise a list the pin cannot give. The table IS filtered, so
    # "Kein Filter aktiv" would be wrong -- and a pin the user cannot remove is
    # no chip either.
    it "shows neither buttons nor chips nor 'Kein Filter aktiv' on a kind tab" do
      get :index, params: {kind: "MossTopUp"}

      expect(line).to be_present
      expect(preset_links).to be_empty
      expect(doc.css(".flt-nofilter")).to be_empty
      expect(doc.css(".flt-applied")).to be_empty
    end

    # The kind slot is the one the Schnellauswahl group stands for: it shows as
    # the PRESSED button, so chipping it as well would say the same thing twice
    # (doc/wsjrdp/expandable_table.md, "Presets"). Every other slot is chipped.
    it "chips the user's own slots, leaving the one a pressed button says" do
      get :index, params: {f: "!(!(!(k,in,MossTopUp)),!(!(amt,ge,100)))"}

      expect(preset_links.pluck("aria-pressed")).to eq(%w[false false false true])
      expect(chip_texts).to eq(["Betrag (Transaktion) ≥ 100"])
      expect(doc.css(".flt-applied .flt-and")).to be_empty
      expect(doc.css(".flt-nofilter")).to be_empty
    end

    it "chips a slot on an attribute the buttons do not cover, joined by 'und'" do
      get :index, params: {f: "!(!(!(acc,in,'66500')),!(!(amt,ge,100)))"}

      expect(chip_texts).to eq(["Sachkonto (Buchung) ist 66500", "Betrag (Transaktion) ≥ 100"])
      expect(doc.css(".flt-applied .flt-and").map { |node| node.text.strip }).to eq(["und"])
    end

    # On a kind tab only the user's slot is chipped; the pinned kind stays out.
    it "chips a user slot next to the tab's pinned kind" do
      get :index, params: {kind: "MossTopUp", f: "!(!(!(amt,ge,100)))"}

      expect(chip_texts).to eq(["Betrag (Transaktion) ≥ 100"])
      expect(doc.css(".flt-nofilter")).to be_empty
    end
  end

  describe "POST apply" do
    it "redirects to the kind tab it was posted from" do
      post :apply, params: {kind: "MossTopUp", filter_json: "[]"}
      expect(response).to have_http_status(:see_other)
      expect(response.location).to end_with("/fin/moss/top_ups?f=")
    end

    it "redirects (PRG) to the canonical Rison filter URL" do
      post :apply, params: {filter_json: [[["kind", "in", "MossTopUp"]]].to_json}
      expect(response).to have_http_status(:see_other)
      # Rison quotes string operands; the codec's decoder accepts both spellings.
      expect(response.location).to end_with("/fin/moss/transactions?f=!(!(!(k,in,'MossTopUp')))")
    end

    # An emptied filter must redirect to an explicitly BLANK param: an absent
    # one would fall through to the remembered filter and bring it straight back.
    it "redirects to a blank filter param when every condition was removed" do
      post :apply, params: {filter_json: "[]"}
      expect(response).to have_http_status(:see_other)
      expect(response.location).to end_with("/fin/moss/transactions?f=")
    end
  end

  describe "GET show" do
    it "renders the transaction's own fields, without the expense / booking levels" do
      get :show, params: {id: card.id}
      expect(response).to be_successful
      expect(response.body).to include("Kartenzahlung").and include("Supermarkt Muster").and include("In Moss öffnen")
      expect(response.body).not_to include("Split eins")
    end

    # Moss has no record page for a top-up, so the "Moss" cell of the
    # Verknüpfungen grid stays empty -- no anchor, and no empty one either.
    it "renders no Moss link on a top-up" do
      get :show, params: {id: top_up.id}
      expect(response).to be_successful
      expect(response.body).to include("Einzahlung").and include("Vereinskonto")
      expect(response.body).not_to include("In Moss öffnen")
      expect(response.body).not_to include("getmoss.com")
    end
  end
end
