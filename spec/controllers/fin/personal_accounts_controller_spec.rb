# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Kreditoren page: the RELATION-backed Buchhaltung summary
# (WsjrdpPersonalAccount.with_booking_summary), its generic CNF filter
# (Fin::PersonalAccountsFilterSchema), the "Schnellauswahl" presets above it and
# the footer totals over the filtered set.
describe Fin::PersonalAccountsController do
  render_views

  let(:person) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

  # Invented numbers and names: six digits, a creditor starting 7-9.
  def create_account(number, name, moss_status)
    WsjrdpPersonalAccount.create!(number: number, name: name, account_kind: "CREDITOR",
      moss_status: moss_status)
  end

  # The creditor is the Konto, so the leg is +amount for "D", -amount for "C".
  def create_booking(number, amount, debit_credit = "D")
    DatevBooking.create!(buchungs_guid: SecureRandom.uuid,
      account_number: number, account_kind: "CREDITOR",
      offsetting_account_number: "66500", offsetting_account_kind: "EXPENSE",
      base_amount: amount, transaction_amount: amount, debit_credit: debit_credit,
      base_currency: "EUR", booking_date: Date.new(2026, 2, 1),
      posting_text: "Testbuchung #{number}")
  end

  # 700101 aktiv, balance 30 over 2 bookings; 700102 inaktiv, balance -50 over
  # 1; 700103 Moss-unknown (NULL -> inaktiv), no booking; 700104 aktiv, no
  # booking. Order by number, by sum and by count all differ.
  before do
    create_account("700101", "Alpha Werkstatt", "active")
    create_account("700102", "Beta Handel", "deactivated")
    create_account("700103", "Gamma GmbH", nil)
    create_account("700104", "Delta AG", "active")
    create_booking("700101", 100)
    create_booking("700101", 70, "C")
    create_booking("700102", 50, "C")
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
    response.body.scan(/bkframe-supplier-(\d+)/).flatten
  end

  def rendered_column_keys
    response.body[%r{<thead>.*?</thead>}m].to_s.scan(/colkey='(\w+)'/).flatten
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
    it "lists every Kreditor in its natural order, by number" do
      get :index
      expect(response).to be_successful
      expect(rendered_numbers).to eq(%w[700101 700102 700103 700104])
      expect(rendered_column_keys)
        .to eq(%w[number name moss_status booking_balance booking_count])
    end

    it "shows the Moss status as aktiv / inaktiv, a NULL status as inaktiv" do
      get :index
      body = response.body[%r{<tbody[^>]*>.*</tbody>}m].to_s
      # The cell holds the tinted status span, so read it up to the cell's end
      # and drop the tags.
      cells = body.scan(%r{colkey='moss_status'>(.*?)</td>}m).flatten
      expect(cells.map { |cell| cell.gsub(/<[^>]+>/, "").strip })
        .to eq(%w[aktiv inaktiv inaktiv aktiv])
      expect(body).not_to include("Deaktiviert")
    end

    it "counts the shown Kreditoren and their bookings in the footer, without a balance" do
      get :index
      expect(response.body).to include("4 Kreditoren angezeigt · 3 Buchungen")
      expect(response.body).not_to include("Saldo gesamt")
    end
  end

  describe "GET index with a filter" do
    it "narrows on the count with the strict > and re-counts the footer" do
      get :index, params: {f: "!(!(!(bc,gt,0)))"}
      expect(rendered_numbers).to eq(%w[700101 700102])
      expect(response.body).to include("2 Kreditoren angezeigt · 3 Buchungen")
    end

    it "narrows on a balance range" do
      get :index, params: {f: "!(!(!(bb,bt,-60,-10)))"}
      expect(rendered_numbers).to eq(%w[700102])
    end

    # |Saldo| (bba) sees a magnitude regardless of sign; Saldo (bb) does not.
    it "narrows on the balance's magnitude, and on the signed balance" do
      get :index, params: {f: "!(!(!(bba,nz)))"}
      expect(rendered_numbers).to eq(%w[700101 700102])

      get :index, params: {f: "!(!(!(bba,ge,50)))"}
      expect(rendered_numbers).to eq(%w[700102])

      get :index, params: {f: "!(!(!(bb,ge,50)))"}
      expect(rendered_numbers).to eq([])

      get :index, params: {f: "!(!(!(bb,le,-50)))"}
      expect(rendered_numbers).to eq(%w[700102])
    end

    # A hand-written URL filters, and the condition reaches the builder's
    # editable value, so a chip labels it and the editor can re-save it.
    it "applies a strict comparison from a hand-written URL" do
      get :index, params: {f: "!(!(!(bb,lt,0)))"}
      expect(rendered_numbers).to eq(%w[700102])
      expect(CGI.unescapeHTML(response.body)).to include('[["booking_balance","lt",0]]')
    end

    it "narrows on the Moss status, counting a NULL status as inaktiv" do
      get :index, params: {f: "!(!(!(ms,in,deactivated)))"}
      expect(rendered_numbers).to eq(%w[700102 700103])

      get :index, params: {f: "!(!(!(ms,in,active)))"}
      expect(rendered_numbers).to eq(%w[700101 700104])
    end

    it "searches the name over both name columns" do
      get :index, params: {f: "!(!(!(q,ct,alpha)))"}
      expect(rendered_numbers).to eq(%w[700101])
    end

    it "remembers the filter on a bare revisit and clears it on a blank ?f=" do
      get :index, params: {f: "!(!(!(bc,gt,0)))"}
      get :index
      expect(rendered_numbers).to eq(%w[700101 700102])

      get :index, params: {f: ""}
      expect(rendered_numbers).to eq(%w[700101 700102 700103 700104])
    end

    it "offers a 'Filter zurücksetzen' that clears only the filter" do
      get :index, params: {f: "!(!(!(bc,gt,0)))", s: "bb~"}
      href = response.body[/href="([^"]*)"[^>]*>Filter zurücksetzen/, 1]
      expect(href).to include("f=").and include("s=bb~")
      expect(href).not_to match(/f=[^&"]/)
    end

    it "sorts by the aggregates and by the Moss status" do
      get :index, params: {s: "bb"}
      expect(rendered_numbers).to eq(%w[700102 700103 700104 700101])

      get :index, params: {s: "bc~"}
      expect(rendered_numbers.first).to eq("700101")

      get :index, params: {s: "ms,nr"}
      expect(rendered_numbers).to eq(%w[700101 700104 700102 700103])
    end

    it "shows everything on one page with ?z=all" do
      get :index, params: {z: "all"}
      expect(rendered_numbers.size).to eq(4)
    end
  end

  # What the builder is handed for the two aggregates: the Saldo as ONE variant
  # group whose members carry the sign metadata -- that is what the editor
  # renders as the ± / |x| toggle instead of a sub-variant dropdown -- and the
  # count as a plain attribute, both starting on "≠ 0".
  describe "the builder's catalog" do
    def catalog_attributes
      JSON.parse(Nokogiri::HTML(response.body).at_css(".flt-root")["data-catalog"])["attributes"]
    end

    it "ships the Saldo sign pair, magnitude first, and every operator offered" do
      get :index
      balances = catalog_attributes.select { |a| a["variant_group"] == "Saldo" }
      expect(balances.map { |a| [a["key"], a["label"], a["sign"]] }).to eq(
        [["booking_balance_abs", "|Saldo|", "absolute"],
          ["booking_balance", "Saldo", "signed"]]
      )
      expect(balances.pluck("operand_min")).to eq([0, nil])
      expect(balances.first["operators"].pluck("key")).to eq(%w[nonzero between lte gte lt gt eq])
      expect(balances.first["operators"].pluck("pickable")).to all(be true)
    end

    it "leaves the Buchungen count without a sign, on the same operator list" do
      get :index
      count = catalog_attributes.find { |a| a["key"] == "booking_count" }
      expect(count["sign"]).to be_nil
      expect(count["variant_group"]).to be_nil
      expect(count["operators"].pluck("key")).to eq(%w[nonzero between lte gte lt gt eq])
    end
  end

  describe "the Schnellauswahl presets" do
    it "renders one link per preset, Saldo first, none of them pressed on a bare page" do
      get :index
      expect(preset_links.keys).to eq(["Nur mit Saldo ≠ 0", "Nur mit Buchungen"])
      expect(preset_links.keys.map { |label| preset_pressed(label) }).to eq(%w[false false])
      expect(preset_filter("Nur mit Saldo ≠ 0")).to eq("!(!(!(bba,nz)))")
      expect(preset_filter("Nur mit Buchungen")).to eq("!(!(!(bc,nz)))")
    end

    it "toggles a preset on and off again through the URL" do
      get :index
      get :index, params: {f: preset_filter("Nur mit Buchungen")}
      expect(rendered_numbers).to eq(%w[700101 700102])
      expect(preset_pressed("Nur mit Buchungen")).to eq("true")

      # Pressed again, the link clears the filter (present but blank).
      expect(preset_filter("Nur mit Buchungen")).to eq("")
      get :index, params: {f: ""}
      expect(rendered_numbers).to eq(%w[700101 700102 700103 700104])
    end

    it "keeps the other preset's slot when one is switched off" do
      get :index
      get :index, params: {f: preset_filter("Nur mit Saldo ≠ 0")}
      expect(preset_pressed("Nur mit Saldo ≠ 0")).to eq("true")
      # Switching the second one on adds its slot next to the first one's.
      get :index, params: {f: preset_filter("Nur mit Buchungen")}
      expect(preset_pressed("Nur mit Saldo ≠ 0")).to eq("true")
      expect(preset_pressed("Nur mit Buchungen")).to eq("true")

      # Switching the first one off removes exactly its slot -- the other stays.
      get :index, params: {f: preset_filter("Nur mit Saldo ≠ 0")}
      expect(preset_pressed("Nur mit Saldo ≠ 0")).to eq("false")
      expect(preset_pressed("Nur mit Buchungen")).to eq("true")
      expect(rendered_numbers).to eq(%w[700101 700102])
    end

    it "does not count an OR-widened slot as the preset's" do
      get :index, params: {f: "!(!(!(bc,nz),!(bc,eq,0)))"}
      expect(preset_pressed("Nur mit Buchungen")).to eq("false")
      expect(rendered_numbers).to eq(%w[700101 700102 700103 700104])
    end

    # `≠ 0` says nothing about the sign, so `Saldo ≠ 0` IS `|Saldo| ≠ 0`: a
    # user who builds the condition on the signed member by hand sees the
    # preset switched on, and its toggle takes exactly that slot away again
    # (Wsjrdp::Filtering::SlotEquality, `aliases:`).
    it "counts the signed twin of the |Saldo| preset as the preset's own slot" do
      get :index, params: {f: "!(!(!(bb,nz)))"}

      expect(rendered_numbers).to eq(%w[700101 700102])
      expect(preset_pressed("Nur mit Saldo ≠ 0")).to eq("true")
      expect(preset_filter("Nur mit Saldo ≠ 0")).to eq("")
      expect(doc.css(".flt-applied .flt-chip")).to be_empty
    end

    # A comparison IS about the sign, so the preset stays off and the slot
    # keeps its chip.
    it "leaves a signed comparison to itself" do
      get :index, params: {f: "!(!(!(bb,ge,10)))"}

      expect(preset_pressed("Nur mit Saldo ≠ 0")).to eq("false")
      expect(doc.css(".flt-applied .flt-chip").map { |chip| chip.text.strip })
        .to eq(["Saldo ≥ 10"])
    end

    it "is pressed on the count's own ≠ 0" do
      get :index, params: {f: "!(!(!(bc,nz)))"}

      expect(rendered_numbers).to eq(%w[700101 700102])
      expect(preset_pressed("Nur mit Buchungen")).to eq("true")
      expect(preset_filter("Nur mit Buchungen")).to eq("")
    end

    # A preset may carry an `icon` and a `css_class` (the Moss wallet's kind
    # presets do). These two declare neither, so their links must stay byte for
    # byte what they were before that feature: the plain button classes, and no
    # icon anywhere but the on/off tick.
    it "renders a preset without icon and colour exactly as before" do
      get :index
      links = Nokogiri::HTML(response.body).css("a.flt-preset")
      expect(links.pluck("class")).to eq(["btn btn-sm btn-outline-secondary flt-preset"] * 2)
      expect(links.css("i")).to be_empty

      get :index, params: {f: preset_filter("Nur mit Buchungen")}
      links = Nokogiri::HTML(response.body).css("a.flt-preset")
      expect(links.pluck("class")).to eq(["btn btn-sm btn-outline-secondary flt-preset"] * 2)
      # The pressed link's only <i> is the tick's check, inside the tick span.
      expect(links.css("i").map { |i| [i["class"], i.parent["class"]] })
        .to eq([["fas fa-check", "flt-preset-tick"]])
      expect(links.flat_map { |a| a.xpath("./i") }).to be_empty
    end

    # The lock itself is client-side (the builder's JS strips the href and sets
    # aria-disabled once the builder differs from the applied filter), so a
    # rendered page always shows the toggles ready to click.
    it "leaves the toggles enabled while the builder has no unapplied edits" do
      get :index
      expect(preset_links.values).to all(include('href="'))
      expect(preset_links.values).to all(satisfy { |tag| !tag.include?("aria-disabled") })
      expect(response.body).to include("gesperrt, bis die Änderungen angewendet oder verworfen sind")
    end
  end

  # The filter LINE above the table (doc/wsjrdp/expandable_table.md): the
  # "Schnellauswahl" bar and the applied filter's chips on its left, the pane's
  # toggle at its right end -- with the pane itself between the line and the
  # table's toolbar.
  describe "the filter line" do
    def line = doc.at_css(".flt-line")

    def pane = doc.at_css(".wsjrdp-pane.flt-pane")

    def chip_buttons = doc.css(".flt-applied .flt-chip")

    def chip_texts = chip_buttons.map { |chip| chip.text.strip }

    # The state the page rendered from, and the two DOM ids the helpers derive
    # from it -- the cross-partial contract between line, pane and builder JS.
    def state = controller.summary_table_state

    def pane_id = controller.helpers.et_pane_id(state)

    def presets_id = controller.helpers.et_filter_presets_id(state)

    # The widget's four landmarks, in the order it renders them.
    let(:landmarks) do
      {line: ".flt-line", pane: ".wsjrdp-pane.flt-pane",
       toolbar: ".exp-toolbar-below-filter", table: "table.bookings-table"}
    end

    def landmark_order
      doc.css(landmarks.values.join(", ")).map { |node|
        landmarks.find { |_name, selector| node.matches?(selector) }.first
      }
    end

    it "holds the preset bar on the left and the pane's toggle at its right end" do
      get :index

      expect(line).to be_present
      expect(line["data-pane-line"]).to eq(pane_id)
      expect(pane["id"]).to eq(pane_id)

      bar = line.at_css(".flt-line-left .flt-presets")
      expect(bar["id"]).to eq(presets_id)
      expect(bar.css("a.flt-preset").size).to eq(2)

      # The toggle is the line's LAST child -- whatever the left half holds.
      toggle = line.element_children.last
      expect(toggle.name).to eq("button")
      expect(toggle["class"].split).to include("pane-toggle")
      expect(toggle["data-pane-target"]).to eq(pane_id)
      expect(toggle["aria-controls"]).to eq(pane_id)
    end

    # `e` is the pane's field (a cookie, overridable by the param); this page's
    # policy opens the pane by default.
    it "takes aria-expanded and the line's open state from the pane field" do
      get :index
      expect(line["class"].split).to include("open")
      expect(line.at_css("button.pane-toggle")["aria-expanded"]).to eq("true")

      get :index, params: {e: "0"}
      expect(line["class"].split).not_to include("open")
      expect(line.at_css("button.pane-toggle")["aria-expanded"]).to eq("false")
    end

    it "chips the applied user filter, one per slot, with 'und' between them" do
      get :index, params: {f: "!(!(!(q,ct,alpha)),!(!(ms,in,active)))"}

      expect(rendered_numbers).to eq(%w[700101])
      expect(doc.at_css(".flt-applied .flt-label").text.strip).to eq("Filter")
      expect(chip_texts).to eq(["Name enthält alpha", "Moss Status ist aktiv"])
      expect(doc.css(".flt-applied .flt-and").map { |node| node.text.strip }).to eq(["und"])
    end

    # A chip is a way INTO the builder: an open-only control, never a link.
    it "makes every chip a pane-opener button pointing at the pane" do
      get :index, params: {f: "!(!(!(ms,in,active)))"}

      expect(chip_buttons.size).to eq(1)
      expect(chip_buttons.pluck("class")).to all(eq("flt-chip pane-opener"))
      expect(chip_buttons.pluck("type")).to all(eq("button"))
      expect(chip_buttons.pluck("data-pane-target")).to all(eq(pane_id))
      expect(chip_buttons.pluck("title")).to all(eq("Filter öffnen"))
    end

    # The preset toggle already shows that slot, so a chip would say it twice.
    it "leaves out the slot of an ACTIVE preset and chips the rest" do
      get :index, params: {f: "!(!(!(bc,nz)),!(!(ms,in,active)))"}

      expect(preset_pressed("Nur mit Buchungen")).to eq("true")
      expect(chip_texts).to eq(["Moss Status ist aktiv"])
      expect(doc.css(".flt-applied .flt-and")).to be_empty
    end

    it "renders no .flt-applied at all when every slot belongs to an active preset" do
      get :index, params: {f: "!(!(!(bc,nz)))"}

      expect(preset_pressed("Nur mit Buchungen")).to eq("true")
      expect(doc.css(".flt-applied")).to be_empty
      expect(doc.css(".flt-nofilter")).to be_empty
    end

    # "Kein Filter aktiv" is for a line that would otherwise be blank; here the
    # preset bar is the line's content and already says that none is switched on.
    it "never says 'Kein Filter aktiv' while there are presets" do
      get :index

      # By the DOM, not by the body: the chips partial names the words in a CSS
      # comment of its own <style> block.
      expect(doc.css(".flt-presets")).to be_present
      expect(doc.css(".flt-applied")).to be_empty
      expect(doc.css(".flt-nofilter")).to be_empty
    end

    it "renders line, pane, toolbar and table in that order" do
      get :index

      expect(landmark_order).to eq(%i[line pane toolbar table])
    end

    # The line owns the filter toggle; the toolbar keeps the column hamburger.
    it "keeps the toggle out of the toolbar and the hamburger out of the line" do
      get :index

      toolbar = doc.at_css(".exp-toolbar-below-filter")
      expect(toolbar).to be_present
      expect(toolbar.css(".pane-toggle")).to be_empty
      expect(toolbar.css(".exp-tools")).to be_present
      expect(line.css(".exp-tools")).to be_empty
      expect(doc.css("button.pane-toggle").size).to eq(1)
    end

    # et_filter_reset_url: the filter param present but blank (no default tree
    # declared), sort and page size untouched, this table's page and open rows
    # dropped with the filter change (D4).
    it "resets only the filter, keeping the rest of the table's state" do
      get :index, params: {f: "!(!(!(bc,gt,0)))", s: "bb~", z: "25", p: "1", o: "700101"}
      reset = doc.css("a").find { |a| a.text.strip == "Filter zurücksetzen" }

      expect(reset["href"]).to eq("/fin/bookkeeping/personal_accounts?f=&s=bb~&z=25")
    end
  end

  describe "POST apply" do
    it "encodes the posted tree into the filter param and redirects (PRG)" do
      post :apply, params: {filter_json: [[["booking_count", "gt", 0]]].to_json}
      expect(response).to have_http_status(:see_other)
      expect(CGI.unescape(response.location))
        .to end_with("/fin/bookkeeping/personal_accounts?f=!(!(!(bc,gt,0)))")
    end

    it "emits a blank filter param when nothing survives" do
      post :apply, params: {filter_json: [[["nope", "in", "x"]]].to_json}
      expect(response.location).to end_with("?f=")
    end
  end

  describe "GET show" do
    it "renders the Kreditor's detail page with its embedded bookings table" do
      get :show, params: {number: "700101"}
      expect(response).to be_successful
      expect(response.body).to include("Alpha Werkstatt").and include("Testbuchung 700101")
    end

    # "In Buchungen-Ansicht öffnen" leads to the Buchungen listing pinned to
    # this Kreditor. That page reads its filter from the ?f= param alone (Rison
    # with the schema's short keys, any_account -> kgk), so the link carries the
    # condition there and not in a query param of its own. A creditor can stand
    # on either side of a booking, which is why the attribute is "Konto oder
    # Gegenkonto" -- the same two-sided view the embedded list takes
    # (DatevBooking.legs).
    it "opens the Buchungen listing filtered to this Kreditor" do
      get :show, params: {number: "700101"}

      expect(open_in_bookings_href).to eq("/fin/bookkeeping/bookings?f=!(!(!(kgk,in,'700101')))")
    end

    # ... and that wire value, read by the Buchungen page's own schema, selects
    # exactly this Kreditor's bookings -- the link is only worth as much as what
    # the target page makes of it.
    it "carries a filter that selects exactly this Kreditor's bookings" do
      get :show, params: {number: "700101"}
      wire = CGI.unescape(open_in_bookings_href[/[?&]f=([^&]*)/, 1].to_s)

      schema = Fin::DatevBookingsFilterSchema.bound(
        except: Fin::BookingsController::EXCLUDED_FILTER_ATTRIBUTES
      )
      query = Fin::DatevBookingsFilterSchema.decode(wire, schema: schema)
      scope = Fin::DatevBookingsFilterSchema.compile(query, schema: schema,
        relation: DatevBooking.all)

      expect(scope.pluck(:account_number).uniq).to eq(["700101"])
      expect(scope.count).to eq(2)
      expect(DatevBooking.count).to eq(3)
    end

    it "renders only the turbo frame for a lazily loaded detail row" do
      request.headers["Turbo-Frame"] = "bkframe-supplier-700101"
      get :show, params: {number: "700101", l: "1"}
      expect(response).to be_successful
      expect(response.body).to include("bs=").and include("l=1")
      expect(response.body).not_to include("<html")
    end

    # Gives the Kreditor the two jsonb blocks the exports write. Invented
    # values; the DATEV codes are the two whose meaning is documented
    # (doc/fin/personal_accounts.md). The list examples keep their row counts,
    # because this changes an existing account instead of adding one.
    def add_raw_columns
      WsjrdpPersonalAccount.find_by(number: "700101").update!(
        other_datev_columns: {"Adressattyp" => "2", "Zahlungsträger" => "7"},
        other_moss_columns: {"VAT Rate" => "19"}
      )
    end

    # One label/value row of the page's field list, by its label.
    def page_row(label)
      doc.css("dl.fin-detail-list .row")
        .find { |row| row.at_css("dt").text.strip == label }
    end

    def page_labels = doc.css("dl.fin-detail-list dt").map { |dt| dt.text.strip }

    # The detail's own heading, not the sheet title the layout puts above it.
    def detail_heading = doc.at_css("#main h1").text

    it "heads the page with the number and the name and lists the fields" do
      get :show, params: {number: "700101"}

      expect(detail_heading).to include("700101").and include("Alpha Werkstatt")
      expect(doc.css("dl.fin-detail-list")).to be_present
      expect(doc.css("dl.row.small")).to be_empty
      expect(doc.css("a").map { |a| a.text.strip }).to include("Zurück zu Kreditoren")
    end

    # The blank modes of the partial: a blank field disappears, while the bank
    # details and the Moss defaults keep their row and say "nicht gesetzt".
    it "drops a blank field and marks the missing BIC as unset" do
      get :show, params: {number: "700101"}

      expect(page_labels).to include("Name").and include("BIC")
      expect(page_labels).not_to include("USt-IdNr.")
      expect(page_row("BIC").at_css("dd span.text-muted.small").text).to eq("nicht gesetzt")
      expect(page_row("Name").at_css("dd").text.strip).to eq("Alpha Werkstatt")
    end

    # One class on the dl, one style block for the whole response -- however
    # many details the page renders.
    it "lightens the labels through the kit's class and its single style block" do
      get :show, params: {number: "700101"}

      expect(doc.css("dl.fin-detail-list")).to be_present
      kit_styles = doc.css("style").select { |tag| tag.text.include?(".fin-detail-list dt") }
      expect(kit_styles.size).to eq(1)
    end

    it "opens the one raw area on the page and names the documented DATEV codes" do
      add_raw_columns
      get :show, params: {number: "700101"}

      area = doc.at_css("details.fin-detail-raw")
      expect(doc.css("details").size).to eq(1)
      expect(doc.css("details.fin-detail-raw[open]").size).to eq(1)
      expect(area.at_css("summary").text.strip).to eq("Rohdaten")
      blocks = area.css("div.booking-detail-label")
      expect(blocks.map { |title| title.text.strip })
        .to eq(["DATEV Rohdaten", "Moss Rohdaten"])
      expect(area.text).to include("2 Unternehmen")
        .and include("7 SEPA-Überweisung mit einer Rechnung")
      expect(area.text).to include("VAT Rate:").and include("19")
    end

    it "renders the compact detail without a heading for a lazily loaded row" do
      add_raw_columns
      request.headers["Turbo-Frame"] = "bkframe-supplier-700101"
      get :show, params: {number: "700101", l: "1"}

      expect(response.body).not_to include("<h1")
      expect(doc.css("dl.row.small")).to be_present
      expect(doc.css("dl.fin-detail-list")).to be_empty
      expect(doc.css("details.fin-detail-raw").size).to eq(1)
      expect(doc.css("details[open]")).to be_empty
      expect(doc.at_css("details.fin-detail-raw summary").text.strip).to eq("Rohdaten")
      expect(doc.css(".fin-embedded-bookings")).to be_present
      expect(response.body).to include("l=1")
    end

    # A number the master data does not describe is a stub record: no field has
    # a value, so what is left besides header and bookings is the Moss status
    # (a record Moss does not know counts as inaktiv, like in the list) and the
    # six rows the partial keeps on blank: :unset -- the bank details and the
    # Moss defaults; with no raw column stored, the raw area renders nothing.
    it "renders a number without a Kreditor record" do
      get :show, params: {number: "799999"}

      expect(response).to be_successful
      expect(detail_heading).to include("799999")
      expect(page_labels).to eq(["Moss Status", "IBAN", "BIC", "Standard-Konto",
        "Standard-Kostenstelle", "Standard-Sphäre", "Team"])
      expect(page_row("Moss Status").at_css("dd").text.strip).to eq("inaktiv")
      expect((page_labels - ["Moss Status"]).map { |label| page_row(label).at_css("dd").text.strip })
        .to all(eq("nicht gesetzt"))
      expect(doc.css(".bk-item-detail details")).to be_empty
      expect(doc.css(".fin-embedded-bookings")).to be_present
    end
  end
end
