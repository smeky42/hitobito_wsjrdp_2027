# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Controlling page "Budget". Invented numbers and amounts.
describe Fin::BudgetsController do
  render_views

  let(:person) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

  before do
    WsjrdpCostCenter.create!(number: "K100", name: "Alpha", short_name: "Alpha", budget_2025: 1000)
    DatevBooking.create!(buchungs_guid: SecureRandom.uuid,
      account_number: "1200", account_kind: "BANK",
      offsetting_account_number: "66500", offsetting_account_kind: "EXPENSE",
      cost_center_number: "K100", base_amount: 1234, transaction_amount: 1234,
      debit_credit: "C", base_currency: "EUR", booking_date: Date.new(2025, 6, 1),
      posting_text: "Test")
    sign_in(person)
  end

  def doc = Nokogiri::HTML(response.body)

  # The cells of one row of a table, by column key, as shown: without the
  # tooltips' <template>s.
  def row_cells(table_id, key) = shown(raw_cells(doc.at_css("tr[aria-controls='#{table_id}-#{key}']")))

  def raw_cells(tr) = tr.css("td").to_h { |td| [td["data-colkey"], td] }

  def shown(cells) = cells.transform_values { |td| td.dup.tap { |copy| copy.css("template").each(&:remove) } }

  # The tooltip of a cell, its text squished.
  def tip(tr, column_key) = raw_cells(tr)[column_key].at_css("template.fin-budget-tip-content").xpath(".//text()").map(&:text).join(" ").squish

  def helper_label(budget, actual)
    controller.view_context.fin_budget_percent_label(Fin::BudgetOverview::Cell.new(budget: budget, actual: actual))
  end

  # The header labels, without the sort controls (arrows, rank boxes, chips).
  def head_labels(index)
    doc.css("#main table")[index].css("thead th").map do |th|
      th = th.dup
      th.css(".exp-sort-caret, .exp-sort-rank, .exp-sort-chips").each(&:remove)
      th.text.strip
    end
  end

  def row_order(table_id) = doc.css("tr[aria-controls^='#{table_id}-']").map { |tr| tr["aria-controls"].delete_prefix("#{table_id}-") }

  # The rows of the n-th table in order, by their first cell ("Alle Ausgaben" etc. for the
  # sum row).
  def first_cells(index) = doc.css("#main table")[index].css("tbody tr.exp-row").map { |tr| tr.at_css("td").then { |td| (td.at_css("span") || td).text.strip } }

  # The (first) sum row of the n-th table, by column key.
  def sum_cells(index)
    shown(raw_cells(doc.css("#main table")[index].at_css("tr.fin-budget-sum-row")))
  end

  it "shows each cost center's IST against its budget, with percent and a red bar over 100 %" do
    get :index

    expect(response).to be_successful
    expect(head_labels(0)).to eq(["Kostenstelle", "2025", "2026", "2027", "Gesamt"])
    cells = row_cells("budget_cost_center", "K100")
    expect(cells["number"].at_css("span").text).to eq("K100")
    expect(cells["number"].at_css("span.fw-bold")).to be_nil
    expect(cells["number"].at_css("span.fw-light.text-muted").text).to eq("Alpha")
    cell = cells["year_2025"]
    expect(cell.at_css(".fin-budget-amounts").text.squish).to eq("1.234 / 1.000")
    expect(cell.at_css(".fin-budget-percent").text).to eq("123,4 %")
    expect(tip(doc.at_css("tr[aria-controls='budget_cost_center-K100']"), "year_2025"))
      .to eq("K100 Alpha · 2025 1.234,00 € / 1.000,00 € 123,4 %")
    expect(cell.at_css("[title], .fin-budget-secondary")).to be_nil
    expect(cell.at_css(".fin-budget-bar-fill")["class"]).to include("fin-budget-over")
    expect(cell.at_css(".fin-budget-bar-fill")["style"]).to include("background-color: color-mix(in oklch, #6E0D18 47%, #BE1E2D)")
    expect(cell.at_css(".fin-budget-percent")["style"]).to eq("color: color-mix(in oklch, #6E0D18 47%, #BE1E2D)")
    expect(cell.at_css(".fin-budget-bar-fill")["style"]).to include("width: 100")
  end

  describe "sorting by a measure" do
    before do
      WsjrdpCostCenter.create!(number: "K200", name: "Beta", short_name: "Beta", budget_2025: 100)
      WsjrdpCostCenter.create!(number: "K300", name: "Gamma", short_name: "Gamma")
      [["K200", 50], ["K300", 9999]].each do |number, amount|
        DatevBooking.create!(buchungs_guid: SecureRandom.uuid,
          account_number: "1200", account_kind: "BANK",
          offsetting_account_number: "66500", offsetting_account_kind: "EXPENSE",
          cost_center_number: number, base_amount: amount, transaction_amount: amount,
          debit_credit: "C", base_currency: "EUR", booking_date: Date.new(2025, 6, 1),
          posting_text: "Test")
      end
    end

    it "orders by number while nothing is sorted, without a bar" do
      get :index
      expect(row_order("budget_cost_center")).to eq(%w[K100 K200 K300])
      expect(doc.at_css(".exp-sort-bar")).to be_nil
    end

    it "offers ist, soll and % per year and Gesamt" do
      get :index
      chips = doc.css("#main table")[0].css("th[data-colkey='year_2025'] .exp-sort-chip").map { |chip| chip.text.delete("⇅").strip }
      expect(chips).to eq(["ist", "soll", "%"])
    end

    it "sorts by the share spent, a cost center without budget last either way, and outlines it" do
      get :index, params: {s: "25_pct~"}
      expect(row_order("budget_cost_center")).to eq(%w[K100 K200 K300])
      expect(row_cells("budget_cost_center", "K200")["year_2025"].at_css(".fin-budget-percent .fin-budget-sorted").text).to eq("50,0 %")
      expect(doc.at_css(".exp-sort-bar").text.squish).to include("2025 Ausschöpfung ↓")

      get :index, params: {s: "25_pct"}
      expect(row_order("budget_cost_center")).to eq(%w[K200 K100 K300])
    end

    it "sorts by IST first and budget second" do
      get :index, params: {s: "ges_ist~"}
      expect(row_order("budget_cost_center")).to eq(%w[K300 K100 K200])
      get :index, params: {s: "ges_soll~"}
      expect(row_order("budget_cost_center")).to eq(%w[K100 K200 K300])
    end
  end

  it "offers 2028 in the column menu and shows it when picked" do
    get :index, params: {c: "nr,25,26,27,28,ges"}
    expect(head_labels(0)).to eq(["Kostenstelle", "2025", "2026", "2027", "2028", "Gesamt"])
  end

  it "opens the cost center's detail from a row" do
    get :index

    frame = doc.at_css("turbo-frame#bkframe-budget_cost_center-K100")
    expect(frame["src"]).to start_with(cost_center_path("K100"))
  end

  it "has a sum row Alle Ausgaben in whole euros, the exact amounts in the tooltips, without a detail" do
    get :index
    sum = sum_cells(0)
    expect(sum["number"].text.strip).to eq("Alle Ausgaben")
    expect(sum["year_2025"].at_css(".fin-budget-amounts").text.squish).to eq("1.234 / 1.000")
    expect(sum["total"].at_css(".fin-budget-amounts").text.squish).to eq("1.234 / 1.000")
    expect(tip(doc.at_css("tr.fin-budget-sum-row"), "total")).to eq("Alle Ausgaben · Gesamt 1.234,00 € / 1.000,00 € 123,4 %")
    expect(doc.at_css("tr.fin-budget-sum-row")["aria-controls"]).to be_nil
  end

  it "sums the cost centers in sum income in a row of their own, not in the unit table" do
    WsjrdpCostCenter.create!(number: "K900", name: "Ertrag")
    DatevBooking.create!(buchungs_guid: SecureRandom.uuid,
      account_number: "1200", account_kind: "BANK",
      offsetting_account_number: "66500", offsetting_account_kind: "EXPENSE",
      cost_center_number: "K900", base_amount: 500, transaction_amount: 500,
      debit_credit: "D", base_currency: "EUR", booking_date: Date.new(2025, 6, 1),
      posting_text: "Einnahme")
    get :index
    expect(first_cells(0)).to eq(["K100", "K900", "Alle Ausgaben", "Alle Einnahmen"])
    income = shown(raw_cells(doc.css("#main table")[0].css("tr.fin-budget-sum-row")[1]))
    expect(income["total"].at_css(".fin-budget-amounts").text.squish).to eq("-500 / –")
  end

  it "sorts the sum row with the others, last by number" do
    get :index
    expect(first_cells(0)).to eq(["K100", "Alle Ausgaben"])
    get :index, params: {s: "ges_ist~"}
    expect(first_cells(0)).to eq(["Alle Ausgaben", "K100"])
  end

  it "names the part through the secondary cost center in the tooltip" do
    WsjrdpCostCenter.create!(number: "U9", name: "Unit 9", is_unit_cost_center: true)
    DatevBooking.create!(buchungs_guid: SecureRandom.uuid,
      account_number: "1200", account_kind: "BANK",
      offsetting_account_number: "66500", offsetting_account_kind: "EXPENSE",
      cost_center_number: "U9", secondary_cost_center_number: "K100", is_unit_budget: false, base_amount: 100, transaction_amount: 100,
      debit_credit: "C", base_currency: "EUR", booking_date: Date.new(2025, 6, 1),
      posting_text: "Test")
    get :index
    expect(tip(doc.at_css("tr[aria-controls='budget_cost_center-K100']"), "year_2025"))
      .to end_with("davon 100,00 € über sekundäre Kostenstelle")
  end

  it "leaves a cell without budget and IST empty" do
    get :index
    expect(row_cells("budget_cost_center", "K100")["year_2026"].text.strip).to eq("")
  end

  # A cost center that took money in: the percent negative, the bar green and
  # as long as the share in absolute value.
  it "colors the bar on one scale: sand at 0 %, amber at 80 %, red at 100 %, bordeaux from 150 %" do
    view = controller.view_context
    expect(view.fin_budget_scale_color(0)).to eq("color-mix(in oklch, #E3A21A 0%, #D9D2BF)")
    expect(view.fin_budget_scale_color(40)).to eq("color-mix(in oklch, #E3A21A 50%, #D9D2BF)")
    expect(view.fin_budget_scale_color(90)).to eq("color-mix(in oklch, #BE1E2D 50%, #E3A21A)")
    expect(view.fin_budget_scale_color(400)).to eq("color-mix(in oklch, #6E0D18 100%, #BE1E2D)")
  end

  it "shows income as a negative percent with a green bar" do
    DatevBooking.create!(buchungs_guid: SecureRandom.uuid,
      account_number: "1200", account_kind: "BANK",
      offsetting_account_number: "66500", offsetting_account_kind: "EXPENSE",
      cost_center_number: "K100", base_amount: 1500, transaction_amount: 1500,
      debit_credit: "D", base_currency: "EUR", booking_date: Date.new(2025, 7, 1),
      posting_text: "Einnahme")
    get :index

    cell = row_cells("budget_cost_center", "K100")["year_2025"]
    expect(cell.at_css(".fin-budget-percent").text).to eq("-26,6 %")
    expect(cell.at_css(".fin-budget-bar-fill")["class"]).to include("fin-budget-income")
    expect(cell.at_css(".fin-budget-bar-fill")["style"]).to include("width: 26.6%")
  end

  it "shows the units in a table of their own, without years" do
    WsjrdpCostCenter.create!(number: "U1", name: "Unit 1", explicit_total_budget: 1000,
      is_unit_cost_center: true)
    get :index

    expect(doc.at_css("tr[aria-controls='budget_cost_center-U1']")).to be_nil
    expect(head_labels(1)).to eq(["Kostenstelle", "Gesamtausgaben", "Unit-Budget"])
    expect(row_cells("budget_unit", "U1")["unit_budget"].at_css(".fin-budget-amounts").text.squish)
      .to eq("0 / 1.000")
    expect(row_cells("budget_unit", "U1")["expenses"].text.strip).to eq("0")
    expect(tip(doc.at_css("tr[aria-controls='budget_unit-U1']"), "expenses")).to eq("U1 Unit 1 · Gesamtausgaben 0,00 €")
    expect(helper_label(BigDecimal(1000), BigDecimal("-1"))).to eq("-0,1 %")
    expect(sum_cells(1)["number"].text.strip).to eq("Alle Ausgaben")
  end

  it "is a tab of the Controlling area" do
    get :index
    tabs = doc.css(".nav-tabs a, ul.nav a").map { |a| a.text.strip }
    expect(tabs).to include("Übersicht", "Budget")
  end
end
