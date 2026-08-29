# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Kostenstellen page: the relation-backed Buchhaltung summary
# (WsjrdpCostCenter.with_booking_summary), its generic CNF filter
# (Fin::CostCentersFilterSchema), the "Schnellauswahl" preset above it, the
# hidden fixed slot that pins one cost center out of the list, and the footer
# totals over the filtered set.
describe Fin::CostCentersController do
  render_views

  let(:person) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

  # Invented numbers and names. Cost-center numbers may contain letters, which
  # is why the fabricated ones do.
  def create_cost_center(number, name, short_name, moss_status)
    WsjrdpCostCenter.create!(number: number, name: name, short_name: short_name,
      moss_status: moss_status)
  end

  # The Konto is a BANK account, so signed_base_amount is +amount for "D" and
  # -amount for "C" (no income/expense sign flip, see
  # doc/fin/money_conventions.md).
  def create_booking(cost_center_number, amount, debit_credit = "D")
    DatevBooking.create!(buchungs_guid: SecureRandom.uuid,
      account_number: "1200", account_kind: "BANK",
      offsetting_account_number: "66500", offsetting_account_kind: "EXPENSE",
      cost_center_number: cost_center_number,
      base_amount: amount, transaction_amount: amount, debit_credit: debit_credit,
      base_currency: "EUR", booking_date: Date.new(2026, 2, 1),
      posting_text: "Testbuchung #{cost_center_number}")
  end

  # K100 aktiv, sum 30 over 2 bookings; K200 inaktiv, no Kurzbezeichnung, sum 50
  # over 1; K300 Moss-unknown (NULL -> inaktiv), no booking. Plus the cost center
  # the page pins out (Fin::CostCentersController::HIDDEN_COST_CENTER_NUMBER),
  # with a booking whose amount would be impossible to overlook in the footer.
  before do
    create_cost_center("K100", "Alpha Lager", "Alpha", "active")
    create_cost_center("K200", "Beta Zelte", nil, "deactivated")
    create_cost_center("K300", "Gamma Küche", "Gamma kurz", nil)
    create_cost_center(Fin::CostCentersController::HIDDEN_COST_CENTER_NUMBER,
      "Platzhalter", "PH", "active")
    create_booking("K100", 100)
    create_booking("K100", 70, "C")
    create_booking("K200", 50)
    create_booking(Fin::CostCentersController::HIDDEN_COST_CENTER_NUMBER, 500)
    sign_in(person)
  end

  def doc = Nokogiri::HTML(response.body)

  # The href of the detail's "In Buchungen-Ansicht öffnen" button, with the HTML
  # escaping of the Rison's quotes undone.
  def open_in_bookings_href
    CGI.unescapeHTML(
      response.body[%r{<a[^>]*href="([^"]*)"[^>]*>In Buchungen-Ansicht öffnen</a>}, 1].to_s
    )
  end

  # The row keys of the rendered page, in order (the widget puts them into the
  # lazy detail frame's DOM id).
  def rendered_numbers
    response.body.scan(/bkframe-cost_center-(\w+)/).flatten
  end

  def rendered_column_keys
    response.body[%r{<thead>.*?</thead>}m].to_s.scan(/colkey='(\w+)'/).flatten
  end

  def body_rows = response.body[%r{<tbody[^>]*>.*</tbody>}m].to_s

  # One cell of the rendered table body, per row, as its inner markup.
  def cells(key)
    body_rows.scan(/colkey='#{key}'>(.*?)<\/td>/m).flatten
  end

  # The preset toggle links by label, each as its raw <a> tag.
  def preset_links
    response.body.scan(%r{<a[^>]*\bflt-preset\b[^>]*>.*?</a>}m)
      .to_h { |tag| [tag.gsub(/<[^>]+>/, "").strip, tag] }
  end

  # The decoded `f` value a preset link points at ("" when it clears the filter).
  def preset_filter(label)
    href = CGI.unescapeHTML(preset_links.fetch(label)[/href="([^"]*)"/, 1].to_s)
    CGI.unescape(href[/[?&]f=([^&]*)/, 1].to_s)
  end

  def preset_pressed(label)
    preset_links.fetch(label)[/aria-pressed="([^"]*)"/, 1]
  end

  describe "GET index" do
    it "lists every Kostenstelle in its natural order, by number" do
      get :index
      expect(response).to be_successful
      expect(rendered_numbers).to eq(%w[K100 K200 K300])
    end

    # The detail's header line is rendered OUTSIDE the lazy turbo frame, above
    # it: it is there while the frame still says "Wird geladen …", and no
    # summary row carries a link icon of its own.
    it "puts the Detailseite double link above each row's lazy frame" do
      get :index

      bars = doc.css(".exp-detail .exp-detail-linkbar")
      expect(bars.size).to eq(3)
      expect(doc.css("tr.exp-row i.fa-eye")).to be_empty
      expect(bars.map { |bar| bar.css(".btn-group").size }).to eq([1, 1, 1])
      expect(bars.first.next_element.name).to eq("turbo-frame")

      same, new_tab = bars.first.css("a")
      expect(same.text.squish).to eq("Detailseite")
      expect(same["href"]).to eq(cost_center_path("K100"))
      expect(same["target"]).to be_nil
      expect(new_tab["href"]).to eq(cost_center_path("K100"))
      expect(new_tab["target"]).to eq("_blank")
      expect(new_tab["title"]).to eq("Detailseite in neuem Tab öffnen")
    end

    it "shows the Kurzbezeichnung right after the Bezeichnung" do
      get :index
      expect(rendered_column_keys)
        .to eq(%w[number name short_name moss_status booking_sum booking_count])
      expect(response.body).to include("Kurzbezeichnung")
      expect(cells("short_name").map { |cell| cell.gsub(/<[^>]+>/, "").strip })
        .to eq(["Alpha", "—", "Gamma kurz"])
    end

    it "shows the Moss status as a tinted aktiv / inaktiv, a NULL status as inaktiv" do
      get :index
      expect(cells("moss_status").map { |cell| cell[/moss-status-(\w+)/, 1] })
        .to eq(%w[active inactive inactive])
      expect(cells("moss_status").map { |cell| cell.gsub(/<[^>]+>/, "").strip })
        .to eq(%w[aktiv inaktiv inaktiv])
      expect(response.body).to include(".moss-status-active")
    end

    it "counts the shown Kostenstellen, their bookings and their sum in the footer" do
      get :index
      expect(response.body.squish).to include("3 Kostenstellen angezeigt · 3 Buchungen · Summe 80,00 €")
    end

    it "sorts by the aggregates, by the names and by the Moss status" do
      get :index, params: {s: "sum"}
      expect(rendered_numbers).to eq(%w[K300 K100 K200])

      get :index, params: {s: "bc~"}
      expect(rendered_numbers.first).to eq("K100")

      # Sorting on the Kurzbezeichnung: NULLS LAST puts the one without last.
      get :index, params: {s: "kbz"}
      expect(rendered_numbers).to eq(%w[K100 K300 K200])

      get :index, params: {s: "ms,nr"}
      expect(rendered_numbers).to eq(%w[K100 K200 K300])
    end
  end

  describe "GET index with a filter" do
    it "searches the name over the Bezeichnung and the Kurzbezeichnung" do
      get :index, params: {f: "!(!(!(q,ct,zelte)))"}
      expect(rendered_numbers).to eq(%w[K200])

      # "Gamma kurz" is only the Kurzbezeichnung -- one search hits both columns.
      get :index, params: {f: "!(!(!(q,ct,kurz)))"}
      expect(rendered_numbers).to eq(%w[K300])
    end

    it "narrows on the Moss status, counting a NULL status as inaktiv" do
      get :index, params: {f: "!(!(!(ms,in,deactivated)))"}
      expect(rendered_numbers).to eq(%w[K200 K300])

      get :index, params: {f: "!(!(!(ms,in,active)))"}
      expect(rendered_numbers).to eq(%w[K100])
    end

    it "narrows on the booking count and re-counts the footer" do
      get :index, params: {f: "!(!(!(bc,nz)))"}
      expect(rendered_numbers).to eq(%w[K100 K200])
      expect(response.body.squish).to include("2 Kostenstellen angezeigt · 3 Buchungen · Summe 80,00 €")

      get :index, params: {f: "!(!(!(bc,gt,1)))"}
      expect(rendered_numbers).to eq(%w[K100])
    end

    it "remembers the filter on a bare revisit and clears it on a blank ?f=" do
      get :index, params: {f: "!(!(!(bc,nz)))"}
      get :index
      expect(rendered_numbers).to eq(%w[K100 K200])

      get :index, params: {f: ""}
      expect(rendered_numbers).to eq(%w[K100 K200 K300])
    end
  end

  # The hidden fixed slot (D2e): host-authored, ANDed ahead of every user slot,
  # never shown and never in the URL -- so nothing a user can do brings the
  # pinned cost center back.
  describe "the pinned-out Kostenstelle" do
    let(:hidden) { Fin::CostCentersController::HIDDEN_COST_CENTER_NUMBER }

    it "keeps it out of the rows and out of the footer totals" do
      get :index
      expect(rendered_numbers).not_to include(hidden)
      # Its booking (500) is in neither the count nor the sum.
      expect(response.body.squish).to include("3 Kostenstellen angezeigt · 3 Buchungen · Summe 80,00 €")
    end

    it "keeps it out on one page, under a filter and after a reset" do
      get :index, params: {z: "all"}
      expect(rendered_numbers).not_to include(hidden)

      # A filter every cost center matches, the pinned one included.
      get :index, params: {f: "!(!(!(ms,in,active)))"}
      expect(rendered_numbers).to eq(%w[K100])

      get :index, params: {f: ""}
      expect(rendered_numbers).to eq(%w[K100 K200 K300])
    end

    it "neither chips it nor puts it into the filter line" do
      get :index
      expect(doc.css(".flt-applied .flt-chip")).to be_empty
      expect(response.body).not_to include("Platzhalter")
    end

    # Its detail page is reachable -- pinning is a decision of the LIST.
    it "still renders its detail page" do
      get :show, params: {number: hidden}
      expect(response).to be_successful
      expect(response.body).to include("Platzhalter")
    end
  end

  describe "the Schnellauswahl preset" do
    it "offers 'Nur mit Buchungen' and toggles it through the URL" do
      get :index
      expect(preset_links.keys).to eq(["Nur mit Buchungen"])
      expect(preset_pressed("Nur mit Buchungen")).to eq("false")
      expect(preset_filter("Nur mit Buchungen")).to eq("!(!(!(bc,nz)))")

      get :index, params: {f: preset_filter("Nur mit Buchungen")}
      expect(rendered_numbers).to eq(%w[K100 K200])
      expect(preset_pressed("Nur mit Buchungen")).to eq("true")

      # Pressed again, the link clears the filter (present but blank).
      expect(preset_filter("Nur mit Buchungen")).to eq("")
      get :index, params: {f: ""}
      expect(rendered_numbers).to eq(%w[K100 K200 K300])
    end
  end

  describe "POST apply" do
    it "encodes the posted tree into the filter param and redirects (PRG)" do
      post :apply, params: {filter_json: [[["booking_count", "nonzero"]]].to_json}
      expect(response).to have_http_status(:see_other)
      expect(CGI.unescape(response.location))
        .to end_with("/fin/bookkeeping/cost_centers?f=!(!(!(bc,nz)))")
    end

    it "emits a blank filter param when nothing survives" do
      post :apply, params: {filter_json: [[["nope", "in", "x"]]].to_json}
      expect(response.location).to end_with("?f=")
    end
  end

  describe "GET show" do
    # The six budget rows the partial always keeps (blank: :unset), in the order
    # it lists them.
    let(:budget_labels) do
      ["Budget 2025", "Budget 2026", "Budget 2027", "Budget 2028",
        "Gesamtbudget (explizit)", "Gesamtbudget"]
    end

    it "renders the Kostenstelle's detail page with its embedded bookings table" do
      get :show, params: {number: "K100"}
      expect(response).to be_successful
      expect(response.body).to include("Alpha Lager").and include("Testbuchung K100")
    end

    # "In Buchungen-Ansicht öffnen" leads to the Buchungen listing pinned to
    # this Kostenstelle. That page reads its filter from the ?f= param alone
    # (Rison with the schema's short keys, cost_center -> cc), so the link
    # carries the condition there and not in a query param of its own.
    it "opens the Buchungen listing filtered to this Kostenstelle" do
      get :show, params: {number: "K100"}

      expect(open_in_bookings_href).to eq("/fin/bookkeeping/bookings?f=!(!(!(cc,in,'K100')))")
    end

    # The embedded bookings table brings the same header line. Its "In Moss"
    # group appears only for a booking that came from Moss -- these did not, so
    # every booking's line holds the Detailseite group alone.
    it "gives each embedded booking a Detailseite link and no In-Moss link" do
      get :show, params: {number: "K100"}

      lines = doc.css(".exp-detail-links")
      expect(lines.size).to eq(2)
      expect(lines.map { |line| line.css(".btn-group").size }).to eq([1, 1])
      expect(lines.map { |line| line.css("a").first.text.squish }).to eq(%w[Detailseite Detailseite])
      expect(lines.flat_map { |line| line.css("a").pluck("href") }.uniq.size).to eq(2)
      expect(response.body).not_to include("In Moss")
    end

    # A booking that DID come from Moss gets the second group, on either of the
    # two levels the Moss->DATEV chain posts at: the clearing booking of a
    # transaction, or the expense booking of one of its splits. Both lead to the
    # SAME transaction's record in Moss.
    it "adds the In-Moss link to a booking that came from Moss" do
      clearing, expense = DatevBooking.where(cost_center_number: "K100").order(:id).to_a
      uuid = SecureRandom.uuid
      transaction = MossTransaction.create!(type: "MossCardTransaction", moss_transaction_uuid: uuid,
        signed_total_base_amount: -170, currency: "EUR", payment_date: Date.new(2026, 2, 1),
        clearing_datev_booking: clearing)
      moss_expense = MossExpense.create!(moss_transaction: transaction, moss_transaction_uuid: uuid,
        type: "MossCardTransactionExpense", expense_number: 1, signed_expense_base_amount: -170)
      MossBooking.create!(moss_transaction: transaction, moss_expense: moss_expense,
        moss_transaction_uuid: uuid, booking_unique_item_number: "#{uuid}_1",
        signed_base_amount: -170, expense_datev_booking: expense)

      get :show, params: {number: "K100"}

      lines = doc.css(".exp-detail-links")
      expect(lines.map { |line| line.css(".btn-group").size }).to eq([2, 2])
      expect(lines.map { |line| line.css("a").first.text.squish }).to eq(["In Moss", "In Moss"])
      expect(lines.map { |line| line.css("a").first["href"] })
        .to eq([transaction.moss_record_url] * 2)
    end

    it "renders only the turbo frame for a lazily loaded detail row" do
      request.headers["Turbo-Frame"] = "bkframe-cost_center-K100"
      get :show, params: {number: "K100", l: "1"}
      expect(response).to be_successful
      expect(response.body).to include("bs=").and include("l=1")
      expect(response.body).not_to include("<html")
    end

    # Gives K100 two of its four yearly budgets. Invented amounts; the effective
    # total is generated by the database from them. The list examples keep their
    # row counts, because this changes an existing cost center instead of adding
    # one.
    def add_budgets
      WsjrdpCostCenter.find_by(number: "K100").update!(budget_2025: -1000, budget_2027: -250)
    end

    # The money format of the Finanzen lists joins number and symbol with a
    # non-breaking space.
    def money(text) = "#{text}#{Fin::MoneyHelper::NBSP}€"

    # One label/value row of the page's field list, by its label.
    def page_row(label)
      doc.css("dl.fin-detail-list .row")
        .find { |row| row.at_css("dt").text.strip == label }
    end

    def page_labels = doc.css("dl.fin-detail-list dt").map { |dt| dt.text.strip }

    # The shown value of a row. An editable row renders the formatted value in
    # its .fin-edit-display span next to the hidden input; a plain row holds
    # the value in the dd itself.
    def page_value(label)
      dd = page_row(label).at_css("dd")
      (dd.at_css(".fin-edit-display") || dd).text.strip
    end

    # The blank marker of a row, nil when the row carries a value.
    def unset_marker(label) = page_row(label).at_css("dd span.text-muted.small")&.text

    # The detail's own heading, not the sheet title the layout puts above it.
    def detail_heading = doc.at_css("#main h1").text

    it "heads the page with the number and the name and lists the fields" do
      get :show, params: {number: "K100"}

      expect(detail_heading).to include("K100").and include("Alpha Lager")
      expect(doc.css("dl.fin-detail-list")).to be_present
      expect(doc.css("dl.row.small")).to be_empty
      expect(doc.css("a").map { |a| a.text.strip }).to include("Zurück zu Kostenstellen")
      expect(page_row("Bezeichnung").at_css("dd").text.strip).to eq("Alpha Lager")
      expect(page_row("Moss Status").at_css("dd").text.strip).to eq("aktiv")
    end

    it "drops a blank field instead of leaving an empty label behind" do
      get :show, params: {number: "K200"}

      expect(page_labels).to include("Bezeichnung")
      expect(page_labels).not_to include("Kurzname")
      expect(page_labels).not_to include("Verantwortliche Person")
    end

    # The budgets stand on blank: :unset -- they say what the master data would
    # carry, so a year without one keeps its row and spells the absence out.
    it "keeps all six budget rows and marks the unset ones" do
      add_budgets
      get :show, params: {number: "K100"}

      expect(page_labels & budget_labels).to eq(budget_labels)
      expect(page_value("Budget 2025")).to eq(money("-1.000,00"))
      expect(page_value("Budget 2027")).to eq(money("-250,00"))
      expect(unset_marker("Budget 2026")).to eq("nicht gesetzt")
      expect(unset_marker("Budget 2028")).to eq("nicht gesetzt")
      expect(unset_marker("Gesamtbudget (explizit)")).to eq("nicht gesetzt")
    end

    # The generated total, with the help line saying where the number comes from.
    it "shows the generated Gesamtbudget with its explanation" do
      add_budgets
      get :show, params: {number: "K100"}

      row = page_row("Gesamtbudget")
      expect(row.at_css("dd").text).to include(money("-1.250,00"))
      expect(row.at_css("dd span.form-text").text).to include("Automatisch berechnet")
    end

    it "renders the compact detail without a heading for a lazily loaded row" do
      add_budgets
      request.headers["Turbo-Frame"] = "bkframe-cost_center-K100"
      get :show, params: {number: "K100", l: "1"}

      expect(response.body).not_to include("<h1")
      expect(doc.css("dl.row.small")).to be_present
      expect(doc.css("dl.fin-detail-list")).to be_empty
      expect(doc.css(".fin-embedded-bookings")).to be_present
      expect(response.body).to include("l=1")
    end

    # A number the master data does not describe is a stub record: no field has
    # a value, so what is left besides header and bookings is the Moss status
    # (a record Moss does not know counts as inaktiv, like in the list) and the
    # six budget rows the partial keeps on blank: :unset.
    it "renders a number without a Kostenstellen record" do
      get :show, params: {number: "K999"}

      expect(response).to be_successful
      expect(detail_heading).to include("K999")
      expect(page_labels).to eq(["Moss Status"] + budget_labels)
      expect(page_row("Moss Status").at_css("dd").text.strip).to eq("inaktiv")
      expect(budget_labels.map { |label| unset_marker(label) })
        .to all(eq("nicht gesetzt"))
      expect(doc.css(".fin-embedded-bookings")).to be_present
    end
  end
end
