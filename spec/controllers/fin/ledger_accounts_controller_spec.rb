# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Sachkonten summary, as the representative of the three Buchhaltung summary
# pages (they share Fin::BookkeepingSummaries): the relation-backed list
# (WsjrdpLedgerAccount.with_booking_summary) with its generic CNF filter
# (Fin::LedgerAccountsFilterSchema) and its footer totals over the filtered set,
# the expandable table driven by the controller-resolved Wsjrdp::TableState
# (doc/plans/2026-09_expandable-table-state.md) and the bookings table embedded
# in an account's detail.
describe Fin::LedgerAccountsController do
  render_views

  let(:person) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

  # The href of the detail's "In Buchungen-Ansicht öffnen" button, with the HTML
  # escaping of the Rison's quotes undone.
  def open_in_bookings_href
    CGI.unescapeHTML(
      response.body[%r{<a[^>]*href="([^"]*)"[^>]*>In Buchungen-Ansicht öffnen</a>}, 1].to_s
    )
  end

  # Invented numbers and names. `visibility: "visible"` keeps the fabricated
  # accounts out of the page's own visibility rule -- that rule has its own
  # describe block below.
  def create_account(number, name, kind, short_name: nil, moss_status: nil,
    visibility: "visible")
    WsjrdpLedgerAccount.create!(number: number, name: name, short_name: short_name,
      account_kind: kind, moss_status: moss_status, visibility: visibility)
  end

  def create_booking(account, kind, offsetting, offsetting_kind, amount, debit_credit)
    DatevBooking.create!(buchungs_guid: SecureRandom.uuid,
      account_number: account, account_kind: kind,
      offsetting_account_number: offsetting, offsetting_account_kind: offsetting_kind,
      base_amount: amount, transaction_amount: amount, debit_credit: debit_credit,
      booking_date: Date.new(2026, 3, 1), posting_text: "Testbuchung #{account}")
  end

  # Three accounts whose order by number and order by sum deliberately differ, so
  # a sort assertion cannot pass by accident. Two bookings, each counting on BOTH
  # its sides: 1200 sees two of them, 4000 and 66500 one each. The three Moss
  # states are all present -- 66500 is the one Moss does not know at all (NULL).
  before do
    create_account("1200", "Testbank", "BANK", short_name: "Bankkonto",
      moss_status: "active")
    create_account("4000", "Testerloese", "INCOME", moss_status: "deactivated")
    create_account("66500", "Testaufwand", "EXPENSE", short_name: "Kostenkurz")
    create_booking("1200", "BANK", "66500", "EXPENSE", 100, "D")
    create_booking("1200", "BANK", "4000", "INCOME", 300, "C")
    sign_in(person)
  end

  # The row keys of the rendered page, in order (the widget puts them into the
  # lazy detail frame's DOM id).
  def rendered_numbers
    response.body.scan(/bkframe-account-([0-9A-Za-z]+)/).flatten
  end

  # The visible columns, in order, read off the table's header row.
  def rendered_column_keys
    response.body[%r{<thead>.*?</thead>}m].to_s.scan(/colkey='(\w+)'/).flatten
  end

  def body_rows = response.body[%r{<tbody[^>]*>.*</tbody>}m].to_s

  # One cell of the rendered table body, per row, as its inner markup.
  def cells(key)
    body_rows.scan(/colkey='#{key}'>(.*?)<\/td>/m).flatten
  end

  describe "GET index" do
    it "lists the visible accounts in their natural order, by number" do
      get :index
      expect(response).to be_successful
      expect(rendered_numbers).to eq(%w[1200 4000 66500])
      expect(response.body).to include("Testbank").and include("Testaufwand")
    end

    it "shows the Kontoart as its German label" do
      get :index
      expect(rendered_column_keys)
        .to eq(%w[number name short_name account_kind moss_status booking_sum booking_count])
      expect(cells("account_kind").map { |cell| cell.gsub(/<[^>]+>/, "").strip })
        .to eq(["Bank", "Ertrag", "Aufwand"])
    end

    it "shows the Kurzbezeichnung right after the Bezeichnung" do
      get :index
      expect(response.body).to include("Kurzbezeichnung")
      expect(cells("short_name").map { |cell| cell.gsub(/<[^>]+>/, "").strip })
        .to eq(["Bankkonto", "—", "Kostenkurz"])
    end

    it "shows the Moss status as a tinted aktiv / inaktiv, a NULL status as inaktiv" do
      get :index
      expect(cells("moss_status").map { |cell| cell[/moss-status-(\w+)/, 1] })
        .to eq(%w[active inactive inactive])
      expect(cells("moss_status").map { |cell| cell.gsub(/<[^>]+>/, "").strip })
        .to eq(%w[aktiv inaktiv inaktiv])
      expect(response.body).to include(".moss-status-active")
    end

    it "counts the shown Sachkonten, their bookings and their sum in the footer" do
      get :index
      expect(response.body.squish).to include("3 Sachkonten angezeigt · 4 Buchungen · Summe -400,00 €")
    end

    it "sorts by the state's ?s= param, using the column's wire token" do
      get :index, params: {s: "sum~"}
      expect(rendered_numbers).to eq(%w[66500 1200 4000])
    end

    it "sorts on the Kurzbezeichnung and on the Moss status" do
      # NULLS LAST puts the account without a Kurzbezeichnung last.
      get :index, params: {s: "kbz"}
      expect(rendered_numbers).to eq(%w[1200 66500 4000])

      # aktiv before inaktiv, the NULL status counting as inaktiv.
      get :index, params: {s: "ms,nr"}
      expect(rendered_numbers).to eq(%w[1200 4000 66500])
    end

    it "remembers the sort and lets a blank ?s= clear it again" do
      get :index, params: {s: "sum~"}
      get :index
      expect(rendered_numbers).to eq(%w[66500 1200 4000])

      get :index, params: {s: ""}
      expect(rendered_numbers).to eq(%w[1200 4000 66500])
    end

    it "selects and orders the columns from ?c=, remembers them, and resets on a blank ?c=" do
      # sum first, then the number; the name is explicitly hidden and everything
      # the param does not mention is appended hidden as well.
      get :index, params: {c: "sum,nr,~bez"}
      expect(rendered_column_keys).to eq(%w[booking_sum number])

      get :index
      expect(rendered_column_keys).to eq(%w[booking_sum number])

      # A blank param is an explicit "back to the default columns" and beats the
      # remembered selection.
      get :index, params: {c: ""}
      expect(rendered_column_keys)
        .to eq(%w[number name short_name account_kind moss_status booking_sum booking_count])
    end

    it "falls back to page 1 when the page is beyond the last one (D4)" do
      get :index, params: {z: "1", p: "999"}
      expect(rendered_numbers).to eq(%w[1200])
    end

    it "forgets the remembered state on ?r=1 and redirects to the bare URL" do
      get :index, params: {z: "1"}
      get :index, params: {r: "1"}
      expect(response).to redirect_to("/fin/bookkeeping/ledger_accounts")

      get :index
      expect(rendered_numbers).to eq(%w[1200 4000 66500])
    end
  end

  describe "GET index with a filter" do
    it "searches the name over the Bezeichnung and the Kurzbezeichnung" do
      get :index, params: {f: "!(!(!(q,ct,erloese)))"}
      expect(rendered_numbers).to eq(%w[4000])

      # "Kostenkurz" is only the Kurzbezeichnung -- one search hits both columns.
      get :index, params: {f: "!(!(!(q,ct,kostenkurz)))"}
      expect(rendered_numbers).to eq(%w[66500])
    end

    it "narrows on the Kontoart and re-counts the footer" do
      get :index, params: {f: "!(!(!(ak,in,'BANK')))"}
      expect(rendered_numbers).to eq(%w[1200])
      expect(response.body.squish).to include("1 Sachkonten angezeigt · 2 Buchungen · Summe -200,00 €")

      get :index, params: {f: "!(!(!(ak,not_in,'BANK')))"}
      expect(rendered_numbers).to eq(%w[4000 66500])
    end

    it "narrows on the Moss status, counting a NULL status as inaktiv" do
      get :index, params: {f: "!(!(!(ms,in,active)))"}
      expect(rendered_numbers).to eq(%w[1200])

      get :index, params: {f: "!(!(!(ms,in,deactivated)))"}
      expect(rendered_numbers).to eq(%w[4000 66500])
    end

    it "remembers the filter on a bare revisit and clears it on a blank ?f=" do
      get :index, params: {f: "!(!(!(ak,in,'BANK')))"}
      get :index
      expect(rendered_numbers).to eq(%w[1200])

      get :index, params: {f: ""}
      expect(rendered_numbers).to eq(%w[1200 4000 66500])
    end
  end

  # Which accounts the list shows at all (Fin::LedgerAccountsController's own
  # visibility rule, not a filter): `visible` always, `hidden` never, `auto` only
  # when Moss knows the account as active or it carries a booking. Personal
  # accounts are no Sachkonten and have their own page.
  describe "GET index, the visibility rule" do
    it "hides an unbooked auto account, shows it once Moss knows it or it is booked" do
      create_account("2000", "Testauto", "EXPENSE", visibility: "auto")
      get :index
      expect(rendered_numbers).not_to include("2000")

      WsjrdpLedgerAccount.find_by(number: "2000").update!(moss_status: "active")
      get :index
      expect(rendered_numbers).to include("2000")

      WsjrdpLedgerAccount.find_by(number: "2000").update!(moss_status: "deactivated")
      create_booking("1200", "BANK", "2000", "EXPENSE", 10, "D")
      get :index
      expect(rendered_numbers).to include("2000")
    end

    it "never shows a hidden account and never a Personenkonto" do
      create_account("2100", "Testverborgen", "EXPENSE", visibility: "hidden",
        moss_status: "active")
      create_account("3100", "Testkreditor", "CREDITOR")
      get :index
      expect(rendered_numbers).to eq(%w[1200 4000 66500])
    end

    # An account the LIST leaves out still has its detail page.
    it "still renders the detail page of an account it leaves out" do
      create_account("2100", "Testverborgen", "EXPENSE", visibility: "hidden")
      get :show, params: {number: "2100"}
      expect(response).to be_successful
      expect(response.body).to include("Testverborgen")
    end
  end

  describe "POST apply" do
    it "encodes the posted tree into the filter param and redirects (PRG)" do
      post :apply, params: {filter_json: [[["account_kind", "in", "BANK"]]].to_json}
      expect(response).to have_http_status(:see_other)
      expect(CGI.unescape(response.location))
        .to end_with("/fin/bookkeeping/ledger_accounts?f=!(!(!(ak,in,'BANK')))")
    end

    it "emits a blank filter param when nothing survives" do
      post :apply, params: {filter_json: [[["nope", "in", "x"]]].to_json}
      expect(response.location).to end_with("?f=")
    end
  end

  # The pager of the expandable table, rendered by the wagon's Kaminari theme
  # "wsjrdp" (app/views/kaminari/wsjrdp/): the two icon-only step buttons first
  # and always, then the page numbers with page 1 and the last page spelled out
  # instead of an "Erste"/"Letzte" label.
  describe "GET index, the pager" do
    # Twelve accounts at one row per page (?z=1) make twelve pages, so the first
    # and the last one fall outside the window of four and the gap shows.
    before { 9.times { |i| create_account("81#{i}0", "Testkonto #{i}", "EXPENSE") } }

    # The <li>s of the first paging line (the one above the table).
    def pager_items
      Nokogiri::HTML(response.body).css(".bk-pagination .pagination").first.css("li")
    end

    # Each item as the text it shows -- a step button by its accessible name.
    def pager_labels
      pager_items.map { |li| li.at_css("[aria-label]")&.[]("aria-label") || li.text.strip }
    end

    # The two step buttons, in the order they are rendered.
    def step_items
      pager_items.select { |li| li["class"].to_s.include?("bk-page-step") }
    end

    it "leads with the step buttons and spells out the first and the last page" do
      get :index, params: {z: "1", p: "6"}
      expect(response).to be_successful
      expect(pager_labels).to eq(["Vorherige Seite", "Nächste Seite",
        "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "...", "12"])

      # Both outer pages are reachable as ordinary number links, and no tag
      # spells them "Erste"/"Letzte" any more.
      hrefs = pager_items.css("a.page-link").pluck("href")
      expect(hrefs).to include(a_string_matching(/\bp=1\b/)).and include(a_string_matching(/\bp=12\b/))
      expect(pager_items.text).not_to match(/Erste|Letzte/)
    end

    it "disables the step back on the first page and links the step forward" do
      get :index, params: {z: "1", p: "1"}
      prev_item, next_item = step_items
      expect(prev_item["class"]).to include("disabled")
      expect(prev_item.at_css("a")).to be_nil
      expect(prev_item.at_css("span.page-link")["aria-disabled"]).to eq("true")
      expect(prev_item.at_css("i.fas.fa-chevron-left")).to be_present

      expect(next_item["class"]).not_to include("disabled")
      link = next_item.at_css("a.page-link")
      expect(link["rel"]).to eq("next")
      expect(link["title"]).to eq("Nächste Seite")
      expect(link["href"]).to match(/\bp=2\b/)
      expect(link.at_css("i.fas.fa-chevron-right")).to be_present
      expect(link.text.strip).to be_blank
    end

    it "disables the step forward on the last page and keeps it in place" do
      get :index, params: {z: "1", p: "12"}
      prev_item, next_item = step_items
      expect(pager_labels.first(2)).to eq(["Vorherige Seite", "Nächste Seite"])

      expect(next_item["class"]).to include("disabled")
      expect(next_item.at_css("a")).to be_nil
      expect(next_item.at_css("span.page-link")["aria-disabled"]).to eq("true")

      expect(prev_item["class"]).not_to include("disabled")
      expect(prev_item.at_css("a.page-link")["rel"]).to eq("prev")
      expect(prev_item.at_css("a.page-link")["href"]).to match(/\bp=11\b/)
    end

    it "drops the open-rows param from every link, the step buttons included" do
      get :index, params: {z: "1", p: "6", o: "1200"}
      hrefs = pager_items.css("a.page-link").pluck("href")
      expect(hrefs).to be_present
      expect(hrefs).to all(satisfy { |h| !h.include?("o=") })
    end
  end

  describe "GET show" do
    it "renders the account's detail page with its embedded bookings table" do
      get :show, params: {number: "1200"}
      expect(response).to be_successful
      expect(response.body).to include("Testbank").and include("Testbuchung 1200")
    end

    # "In Buchungen-Ansicht öffnen" leads to the Buchungen listing pinned to
    # this account. That page reads its filter from the ?f= param alone (Rison
    # with the schema's short keys), so the link carries the condition there
    # and not in a query param of its own. The embedded list shows both booking
    # sides, hence "Konto oder Gegenkonto" (kgk).
    it "opens the Buchungen listing filtered to this account on either side" do
      get :show, params: {number: "1200"}

      expect(open_in_bookings_href).to eq("/fin/bookkeeping/bookings?f=!(!(!(kgk,in,'1200')))")
    end

    it "renders only the turbo frame for a lazily loaded detail row" do
      request.headers["Turbo-Frame"] = "bkframe-account-1200"
      get :show, params: {number: "1200", l: "1"}
      expect(response).to be_successful
      # The embedded table lives under the "b" prefix and keeps the nesting level
      # the summary list put into the frame URL.
      expect(response.body).to include("bs=").and include("l=1")
      expect(response.body).not_to include("<html")
    end

    it "remembers the embedded table's sort per account (D2)" do
      get :show, params: {number: "1200", bs: "amt"}
      get :show, params: {number: "1200"}
      # amt is the active, ascending sort of THIS account's table: clicking it
      # again would turn it around and leave nothing else.
      expect(response.body).to include("bs=amt~")

      get :show, params: {number: "66500"}
      # The other account still has the policy default (booking_date, desc).
      expect(response.body).to include("bs=amt,bdt~")
    end
  end
end
