# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Buchhaltung sub-tab of a group's Finanzen tab (/groups/:id/finance/bookkeeping).
# The page is gated on :show_finance, so it answers to the group's own leaders,
# to a person whose finance_group_ids list the group, and to the finance tiers
# from the audit tier up; the read tier stays out.
describe Group::BookkeepingController do
  render_views

  let(:extern) { Group::Extern.create!(name: "Extern", parent: groups(:root)) }
  let(:auditor) { Fabricate(Group::Extern::FinanceAuditor.name.to_sym, group: extern).person }
  let(:reader) { Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person }

  def show(group) = get(:show, params: {group_id: group.id})

  it "renders the page with its sub-tab for a unit leader on their own unit" do
    sign_in(people(:ul_a_1))

    show(groups(:unit_a))

    expect(response).to be_successful
    expect(response.body).to include("Buchhaltung")
    expect(response.body).to include(I18n.t("groups.finance.bookkeeping.no_cost_centers"))

    # The sub-tab links to the group once. Without Sheet::Group::Finance#path_args
    # the group would travel twice and the second one would become the format
    # (".../finance/bookkeeping.8").
    tabs = Nokogiri::HTML(response.body).css("ul.nav-sub a").pluck("href")
    expect(tabs).to include(group_finance_bookkeeping_path(groups(:unit_a)))
    expect(response.body).not_to match(%r{/finance/bookkeeping\.\d})
  end

  it "refuses a unit leader on another unit" do
    sign_in(people(:ul_a_1))

    expect { show(groups(:unit_b)) }.to raise_error(CanCan::AccessDenied)
  end

  it "refuses a youth participant on their own unit" do
    sign_in(people(:yp_a_1))

    expect { show(groups(:unit_a)) }.to raise_error(CanCan::AccessDenied)
  end

  it "refuses the CMT leader on a unit without an entry in finance_group_ids" do
    sign_in(people(:cmt_leader))

    expect { show(groups(:unit_b)) }.to raise_error(CanCan::AccessDenied)
  end

  it "renders for the CMT leader on a unit listed in their finance_group_ids" do
    cmt_leader = people(:cmt_leader)
    cmt_leader.update!(finance_group_ids: {groups(:unit_b).id.to_s => "show"})
    sign_in(cmt_leader)

    show(groups(:unit_b))

    expect(response).to be_successful
  end

  it "renders for the audit tier, which is not layer-bound" do
    sign_in(auditor)

    show(groups(:unit_a))

    expect(response).to be_successful
  end

  it "refuses the read tier, which grants nothing on a group" do
    sign_in(reader)

    expect { show(groups(:unit_a)) }.to raise_error(CanCan::AccessDenied)
  end

  # The cost centers of the group (groups.additional_info["cost_center_numbers"],
  # assigned on /fin/admin/group_cost_centers). All numbers and names invented.
  describe "the Kostenstellen block" do
    let!(:cost_center) { WsjrdpCostCenter.create!(number: "A1", name: "Kostenstelle A1") }

    def doc = Nokogiri::HTML(response.body)

    def chips = doc.css("#main .badge")

    before { groups(:unit_a).update!(cost_center_numbers: ["A1"]) }

    # A unit leader reaches the page through their own group and holds nothing
    # in the Finanzen section, so the chip carries no link into it.
    it "shows the unit leader the chips as plain text" do
      sign_in(people(:ul_a_1))

      show(groups(:unit_a))

      expect(response).to be_successful
      expect(chips.text).to include("A1").and include("Kostenstelle A1")
      expect(response.body).not_to include("/fin/bookkeeping/cost_centers/")
    end

    it "shows the unit leader the empty text where nothing is assigned" do
      groups(:unit_a).update!(cost_center_numbers: [])
      sign_in(people(:ul_a_1))

      show(groups(:unit_a))

      expect(response.body).to include(I18n.t("groups.finance.bookkeeping.no_cost_centers"))
      expect(chips).to be_empty
    end

    it "links the chips for somebody who may open a cost center" do
      sign_in(Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person)

      show(groups(:unit_a))

      expect(response).to be_successful
      expect(chips.css("a").pluck("href")).to include(cost_center_path("A1"))
    end

    # ONE compact line, not a heading with a block under it: the label is muted
    # and the chips stand beside it. The only heading left on the page is the
    # one over the table.
    it "puts the label and the chips into one line" do
      sign_in(people(:ul_a_1))

      show(groups(:unit_a))

      line = doc.at_css("#main .d-flex.flex-wrap.align-items-baseline")
      expect(line.text).to include("Kostenstellen").and include("Kostenstelle A1")
      expect(line.css(".badge").size).to eq(1)
      expect(doc.css("#main h2").map { |heading| heading.text.strip }).to eq(["Buchungen"])
    end

    it "keeps the empty text in that line for a group without cost centers" do
      groups(:unit_a).update!(cost_center_numbers: [])
      sign_in(people(:ul_a_1))

      show(groups(:unit_a))

      line = doc.at_css("#main .d-flex.flex-wrap.align-items-baseline")
      expect(line.text).to include("Kostenstellen")
        .and include(I18n.t("groups.finance.bookkeeping.no_cost_centers"))
    end
  end

  # The bookings of the group: the Buchungen table of /fin/bookkeeping/bookings,
  # PINNED to the group's cost centers by one fixed filter slot over
  # `any_cost_center` and reduced to the columns and filter attributes a group
  # needs (Group::BookkeepingController::COLUMNS / FILTERS). All numbers, names
  # and booking texts invented.
  describe "the Buchungen table" do
    let!(:batch) do
      DatevBookingBatch.create!(consultant_number: "1", client_number: "2",
        label: "Teststapel", period_from: Date.new(2026, 1, 1),
        period_to: Date.new(2026, 1, 31), financial_year_start: Date.new(2026, 1, 1),
        primanota_number: "01-2026/0001", import_export: "import")
    end

    def create_booking(posting_text, cost_center:, secondary: nil)
      DatevBooking.create!(batch: batch, buchungs_guid: SecureRandom.uuid,
        account_number: "1200", account_kind: "BANK",
        offsetting_account_number: "66500", offsetting_account_kind: "EXPENSE",
        cost_center_number: cost_center, secondary_cost_center_number: secondary,
        base_amount: 100, transaction_amount: 100, debit_credit: "D",
        base_currency: "EUR", booking_date: Date.new(2026, 2, 1),
        posting_text: posting_text)
    end

    let!(:cost_center_a) { WsjrdpCostCenter.create!(number: "A1", name: "Kostenstelle A1") }
    let!(:cost_center_b) { WsjrdpCostCenter.create!(number: "B1", name: "Kostenstelle B1") }

    let!(:own_booking) { create_booking("Buchung Alpha", cost_center: "A1") }
    # Booked on ANOTHER cost center and only tagged with the group's as the
    # secondary one -- the reason the pin uses `any_cost_center`.
    let!(:secondary_booking) { create_booking("Buchung Beta", cost_center: "B1", secondary: "A1") }
    let!(:foreign_booking) { create_booking("Buchung Gamma", cost_center: "B1") }

    before do
      groups(:unit_a).update!(cost_center_numbers: ["A1"])
      groups(:unit_b).update!(cost_center_numbers: ["B1"])
      sign_in(people(:ul_a_1))
    end

    def doc = Nokogiri::HTML(response.body)

    # The filter builder's root node carries the whole filter as data: the
    # locked (fixed) slots, the picker's catalog and the applied user slots.
    def flt_root = doc.at_css(".flt-root")

    # The row keys of the rendered page: the widget puts them into each row's
    # lazy detail frame id, under this table's own prefix.
    def rendered_ids = response.body.scan(/bkframe-gb-(\d+)/).flatten.uniq

    def visible_columns = doc.css("thead th[data-colkey]").pluck("data-colkey")

    def column_menu = doc.at_css(".tbl-burger-panel")

    # The applied USER conditions, as the filter line words them.
    def chip_texts = doc.css(".flt-chip").map { |chip| chip.text.strip }

    # The Schnellauswahl toggle links by label, each as its raw <a> tag.
    def preset_links
      response.body.scan(%r{<a[^>]*\bflt-preset\b[^>]*>.*?</a>}m)
        .to_h { |tag| [tag.gsub(/<[^>]+>/, "").strip, tag] }
    end

    # The decoded `gbf` value a preset link points at ("" when it clears it).
    def preset_filter(label)
      href = CGI.unescapeHTML(preset_links.fetch(label)[/href="([^"]*)"/, 1].to_s)
      CGI.unescape(href[/[?&]gbf=([^&]*)/, 1].to_s)
    end

    def preset_pressed(label)
      preset_links.fetch(label)[/aria-pressed="([^"]*)"/, 1]
    end

    # The table's summary line. .strip, not .squish: squish would fold the money
    # format's NBSP away.
    def summary_line
      doc.css("div.text-muted.small").map { |node| node.text.strip }
        .find { |text| text.include?("Summe (gefiltert)") }
    end

    def sign_in_on_both_units
      cmt_leader = people(:cmt_leader)
      cmt_leader.update!(finance_group_ids: {groups(:unit_a).id.to_s => "show",
                                             groups(:unit_b).id.to_s => "show"})
      sign_in(cmt_leader)
    end

    # The browser's half of the PRG: follow the redirect the apply POST answered
    # with, so the filter travels the way it does in the UI -- through the URL,
    # which is also what puts it into the store.
    def follow_apply(group)
      query = Rack::Utils.parse_query(URI.parse(response.location).query)
      get :show, params: query.merge("group_id" => group.id)
    end

    it "lists the group's bookings on either cost-center column" do
      show(groups(:unit_a))

      expect(response).to be_successful
      expect(rendered_ids).to match_array([own_booking.id.to_s, secondary_booking.id.to_s])
      expect(response.body).to include("Buchung Alpha").and include("Buchung Beta")
      expect(response.body).not_to include("Buchung Gamma")
    end

    # The pin is a fixed slot, so it is compiled into the relation AND shown as
    # a locked chip -- the page says what it is showing.
    it "pins the table with a locked Kostenstellen condition" do
      show(groups(:unit_a))

      expect(JSON.parse(flt_root["data-locked"])).to eq([[["any_cost_center", "in", "A1"]]])
      expect(flt_root["data-catalog"]).to include("Kostenstelle oder sekundäre Kostenstelle")
    end

    it "shows no table at all for a group without cost centers" do
      groups(:unit_a).update!(cost_center_numbers: [])

      show(groups(:unit_a))

      expect(response).to be_successful
      expect(response.body).to include(I18n.t("groups.finance.bookkeeping.no_cost_centers"))
      expect(doc.css("table.bookings-table")).to be_empty
      expect(response.body).not_to include("Buchung Alpha")
    end

    # Every way into a booking stays on the group's own route: the detail page
    # of a row and the frame its pane is lazy-loaded from.
    it "links each row to the group's own booking page" do
      show(groups(:unit_a))

      booking_path = group_finance_bookkeeping_booking_path(groups(:unit_a), own_booking)
      expect(doc.css("#main a").pluck("href")).to include(booking_path)
      expect(doc.css("turbo-frame").pluck("src"))
        .to include(a_string_starting_with(booking_path))
      expect(response.body).not_to include("/fin/bookkeeping/bookings/")
    end

    it "drops a column this table does not have from ?gbc=" do
      get :show, params: {group_id: groups(:unit_a).id, gbc: "bdt,sphere,posting_text"}

      expect(response).to be_successful
      expect(visible_columns).to include("booking_date", "posting_text")
      expect(visible_columns).not_to include("sphere_number")
    end

    # Whether a booking counts against the unit's budget is what a unit reads
    # its own list by, so unlike on /fin the column is there from the start --
    # right behind the amount.
    it "shows the Unit-Budget column by default" do
      show(groups(:unit_a))

      expect(visible_columns).to include("unit_budget")
      expect(column_menu.text).to include("Unit-Budget?")
    end

    # The Konto names the side that carries the money; the second account
    # number is bookkeeping detail. It stays in the menu.
    it "leaves the Gegenkonto out of the default columns" do
      show(groups(:unit_a))

      expect(visible_columns).to include("account_number")
      expect(visible_columns).not_to include("offsetting_account_number")
      expect(column_menu.text).to include("Gegenkonto")
    end

    # With ONE cost center the locked chip above the table already names it and
    # every row would repeat it.
    it "leaves the Kostenstelle out where the group has exactly one" do
      show(groups(:unit_a))

      expect(visible_columns).not_to include("cost_center_number")
      expect(column_menu.text).to include("Kostenstelle")
    end

    it "shows the Kostenstelle where the group has two" do
      groups(:unit_a).update!(cost_center_numbers: %w[A1 B1])

      show(groups(:unit_a))

      expect(visible_columns).to include("cost_center_number")
    end

    # The column menu still offers both, so a hand-written ?gbc= brings them
    # back -- the defaults are a starting point, not the allow-list.
    it "takes both back through ?gbc=" do
      get :show, params: {group_id: groups(:unit_a).id, gbc: "bdt,cc,oacc"}

      expect(visible_columns).to include("cost_center_number", "offsetting_account_number")
    end

    # The filter attribute over the RESOLVED answer: no booking here carries a
    # flag, so the accounts decide -- 66500 is the Gegenkonto of all three.
    it "narrows on the resolved Unit-Budget through ?gbf=" do
      WsjrdpLedgerAccount.create!(number: "66500", name: "Testaufwand",
        is_unit_budget: false)

      get :show, params: {group_id: groups(:unit_a).id, gbf: "!(!(!(ub,in,'false')))"}
      expect(rendered_ids).to match_array([own_booking.id.to_s, secondary_booking.id.to_s])

      get :show, params: {group_id: groups(:unit_a).id, gbf: "!(!(!(ub,in,'true')))"}
      expect(rendered_ids).to be_empty
    end

    it "does not offer Sphäre in the column menu" do
      show(groups(:unit_a))

      expect(column_menu.text).to include("Belegfeld 1")
      expect(column_menu.text).not_to include("Sphäre")
    end

    it "calls the Datum column Buchungsdatum" do
      show(groups(:unit_a))

      expect(doc.at_css("thead th[data-colkey=booking_date]").text).to include("Buchungsdatum")
    end

    it "ignores a ?gbs= naming a column outside the table" do
      show(groups(:unit_a))
      expect(doc.css("thead a[aria-sort]")).not_to be_empty

      get :show, params: {group_id: groups(:unit_a).id, gbs: "sphere~"}

      expect(response).to be_successful
      expect(controller.booking_table_state.sort_list).to eq([])
      expect(doc.css("thead a[aria-sort]")).to be_empty
    end

    it "drops a ?gbf= naming an attribute the picker does not offer" do
      get :show, params: {group_id: groups(:unit_a).id, gbf: "!(!(!(sph,in,S1)))"}

      expect(response).to be_successful
      expect(chip_texts).to be_empty
      # The same wire form with an attribute the table HAS does become a chip,
      # so the example above shows the allow-list working, not a broken param.
      get :show, params: {group_id: groups(:unit_a).id, gbf: "!(!(!(q,ct,Alpha)))"}
      expect(chip_texts.join(" ")).to include("Alpha")
    end

    it "redirects the apply POST back to the page (PRG)" do
      post :apply, params: {group_id: groups(:unit_a).id,
                            filter_json: [[["text", "contains", "Alpha"]]].to_json}

      expect(response).to have_http_status(:see_other)
      expect(response.location).to include(group_finance_bookkeeping_path(groups(:unit_a)))
      expect(response.location).to include("gbf=")
      # The group travels in the path, never in the query string.
      expect(URI.parse(response.location).query).not_to include("group_id")
    end

    # The store key carries the group id, so one unit's remembered filter never
    # shows up on another's page.
    it "remembers the filter per group" do
      sign_in_on_both_units

      post :apply, params: {group_id: groups(:unit_a).id,
                            filter_json: [[["text", "contains", "Alpha"]]].to_json}
      follow_apply(groups(:unit_a))
      expect(chip_texts.join(" ")).to include("Alpha")

      show(groups(:unit_a))
      expect(chip_texts.join(" ")).to include("Alpha")

      show(groups(:unit_b))
      expect(response).to be_successful
      expect(chip_texts).to be_empty
    end

    # The one-click shortcut into the user filter, over the same RESOLVED answer
    # the column shows. 1200 names no account here and 66500 says no, so only a
    # booking carrying the flag itself counts against the unit's budget.
    describe "the Unit-Budget Schnellauswahl" do
      let!(:expense) do
        WsjrdpLedgerAccount.create!(number: "66500", name: "Testaufwand", is_unit_budget: false)
      end

      it "offers the preset, unpressed" do
        show(groups(:unit_a))

        expect(preset_links.keys).to eq(["Unit-Budget"])
        expect(preset_pressed("Unit-Budget")).to eq("false")
      end

      it "narrows the rows to the resolved answer when it is switched on" do
        own_booking.update!(is_unit_budget: true)
        show(groups(:unit_a))

        get :show, params: {group_id: groups(:unit_a).id, gbf: preset_filter("Unit-Budget")}

        expect(response).to be_successful
        expect(preset_pressed("Unit-Budget")).to eq("true")
        expect(rendered_ids).to eq([own_booking.id.to_s])
      end

      # It is a shortcut into the USER part, not a pin: the slot lands in the
      # builder's editable value, beside the group's locked Kostenstellen slot.
      # While the preset is pressed the bar speaks for that slot, so it gets no
      # chip of its own (doc/wsjrdp/expandable_table.md, "Presets").
      it "leaves the slot in the user part of the filter" do
        show(groups(:unit_a))

        get :show, params: {group_id: groups(:unit_a).id, gbf: preset_filter("Unit-Budget")}

        expect(JSON.parse(flt_root["data-value"])).to eq([[["unit_budget", "in", "true"]]])
        expect(JSON.parse(flt_root["data-locked"])).to eq([[["any_cost_center", "in", "A1"]]])
        expect(chip_texts).to be_empty
      end

      # Both figures come from the same filtered relation: the group's two
      # bookings add up to 200, of which the one carrying the flag counts.
      it "states the Unit-Budget share of the sum" do
        own_booking.update!(is_unit_budget: true)

        show(groups(:unit_a))

        nbsp = Fin::MoneyHelper::NBSP
        expect(summary_line).to eq("2 Buchungen · Summe (gefiltert): 200,00#{nbsp}€ · " \
          "davon Unit-Budget: 100,00#{nbsp}€ (1 Buchungen)")
      end
    end

    # The three figures between the Kostenstellen line and the table. They read
    # the PINNED set, never the filtered one (Fin::GroupBookkeepingFigures).
    #
    # The bookings of this describe are booked "D" on a BANK Konto and are
    # therefore POSITIVE; the budgets below carry the same sign, so the share
    # comes out positive the way it does for a spending unit with its negative
    # amounts and negative budget.
    describe "the Kennzahlen tiles" do
      # 66600 says a booking on it is not a unit's; the other two keep 66500,
      # which names no master record and falls to the default.
      let!(:central_account) do
        WsjrdpLedgerAccount.create!(number: "66600", name: "Testaufwand zentral",
          is_unit_budget: false)
      end

      # Both cost centers are a unit's own, so the cost-centre step passes and
      # the ACCOUNTS decide -- 66600 is what keeps the second booking out of the
      # Unit-Budget (doc/fin/unit_budget.md).
      before do
        cost_center_a.update!(is_unit_cost_center: true)
        cost_center_b.update!(is_unit_cost_center: true)
        secondary_booking.update!(offsetting_account_number: "66600")
      end

      def tiles
        doc.css(".gb-figure").to_h do |tile|
          [tile.at_css(".gb-figure-label").text.strip, tile.at_css(".gb-figure-value").text.strip]
        end
      end

      def tile_hints = doc.css(".gb-figure-hint").map { |hint| hint.text.strip }

      def money(text) = "#{text}#{Fin::MoneyHelper::NBSP}€"

      # The tiles talk of expenses: the signed sums with their sign turned. The
      # bookings of this spec are debits of +100, so they read as -100 spent --
      # and as -20 % of the (positive) budget used.
      it "states the expenses, the Unit-Budget part of them, the budget and the share" do
        cost_center_a.update!(explicit_total_budget: 500)

        show(groups(:unit_a))

        expect(tiles["Ausgaben Gesamt"]).to eq(money("-200,00"))
        expect(tiles["Ausgaben Unit-Budget"]).to eq(money("-100,00"))
        expect(tiles["Unit-Budget"]).to eq(money("500,00"))
        expect(tiles["Unit-Budget Verbraucht"]).to match(/\A-20\s*%\z/)
        expect(tile_hints).to be_empty
      end

      # Only a cost center marked as a unit's own carries the budget: A1 here is
      # the group's, but not the unit's, so there is nothing to measure against.
      it "says so where no cost center of the group is a unit's own" do
        cost_center_a.update!(is_unit_cost_center: false, explicit_total_budget: 500)

        show(groups(:unit_a))

        expect(tiles["Unit-Budget"]).to eq("—")
        expect(tiles["Unit-Budget Verbraucht"]).to eq("—")
        expect(tile_hints).to eq(["kein Unit-Budget hinterlegt"])
      end

      it "says so where the unit cost center carries no budget" do
        cost_center_a.update!(is_unit_cost_center: true)

        show(groups(:unit_a))

        expect(tiles["Unit-Budget"]).to eq("—")
        expect(tiles["Unit-Budget Verbraucht"]).to eq("—")
        expect(tile_hints).to eq(["kein Unit-Budget hinterlegt"])
      end

      # The table answers what the viewer is looking at, the tiles where the
      # unit stands -- a filter moves the first and leaves the second alone.
      it "ignores the user's filter" do
        cost_center_a.update!(explicit_total_budget: 500)

        get :show, params: {group_id: groups(:unit_a).id, gbf: "!(!(!(q,ct,Alpha)))"}

        expect(rendered_ids).to eq([own_booking.id.to_s])
        expect(summary_line).to include("1 Buchungen")
        expect(tiles["Ausgaben Gesamt"]).to eq(money("-200,00"))
        expect(tiles["Ausgaben Unit-Budget"]).to eq(money("-100,00"))
        expect(tiles["Unit-Budget Verbraucht"]).to match(/\A-20\s*%\z/)
      end

      it "shows no tiles for a group without cost centers" do
        groups(:unit_a).update!(cost_center_numbers: [])

        show(groups(:unit_a))

        expect(doc.css(".gb-figure")).to be_empty
      end
    end

    it "refuses the apply POST to a youth participant" do
      sign_in(people(:yp_a_1))

      expect { post :apply, params: {group_id: groups(:unit_a).id, filter_json: "[]"} }
        .to raise_error(CanCan::AccessDenied)
    end
  end
end
