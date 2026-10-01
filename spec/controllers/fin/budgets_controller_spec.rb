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

  # The cells of one row of a table, by column key.
  def row_cells(table_id, key)
    doc.at_css("tr[aria-controls='#{table_id}-#{key}']").css("td").to_h { |td| [td["data-colkey"], td] }
  end

  def helper_label(budget, actual)
    controller.view_context.fin_budget_percent_label(Fin::BudgetOverview::Cell.new(budget: budget, actual: actual))
  end

  def head_labels(index) = doc.css("#main table")[index].css("thead th").map { |th| th.text.delete("⇅").strip }

  it "shows each cost center's IST against its budget, with percent and a red bar over 100 %" do
    get :index

    expect(response).to be_successful
    expect(head_labels(0)).to eq(["Kostenstelle", "2025", "2026", "2027", "Gesamt"])
    cells = row_cells("budget_cost_center", "K100")
    expect(cells["number"].at_css("span.fw-bold").text).to eq("K100")
    expect(cells["number"].at_css("span.fw-light.text-muted").text).to eq("Alpha")
    cell = cells["year_2025"]
    expect(cell.at_css(".fin-budget-amounts").text.squish).to eq("1.234 / 1.000")
    expect(cell.at_css(".fin-budget-percent").text).to eq("123 %")
    expect(cell.at_css(".fin-budget-bar-fill")["class"]).to include("fin-budget-over")
    expect(cell.at_css(".fin-budget-bar-fill")["style"]).to include("width: 100")
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

  it "ends each table in a sum row, the Gesamt in euros and cents" do
    get :index
    footer = doc.at_css("#main table tfoot tr.exp-footer-row").css("td").to_h { |td| [td["data-colkey"], td] }
    expect(footer["number"].text.strip).to eq("Summe")
    expect(footer["year_2025"].at_css(".fin-budget-amounts").text.squish).to eq("1.234 / 1.000")
    expect(footer["total"].at_css(".fin-budget-amounts").text.squish).to eq("1.234,00 / 1.000,00")
  end

  it "leaves a cell without budget and IST empty" do
    get :index
    expect(row_cells("budget_cost_center", "K100")["year_2026"].text.strip).to eq("")
  end

  # A cost center that took money in: the percent negative, the bar green and
  # as long as the share in absolute value.
  it "shows income as a negative percent with a green bar" do
    DatevBooking.create!(buchungs_guid: SecureRandom.uuid,
      account_number: "1200", account_kind: "BANK",
      offsetting_account_number: "66500", offsetting_account_kind: "EXPENSE",
      cost_center_number: "K100", base_amount: 1500, transaction_amount: 1500,
      debit_credit: "D", base_currency: "EUR", booking_date: Date.new(2025, 7, 1),
      posting_text: "Einnahme")
    get :index

    cell = row_cells("budget_cost_center", "K100")["year_2025"]
    expect(cell.at_css(".fin-budget-percent").text).to eq("-27 %")
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
      .to eq("0,00 / 1.000,00")
    expect(row_cells("budget_unit", "U1")["expenses"].text.strip).to eq("0,00")
    expect(helper_label(BigDecimal(1000), BigDecimal("-1"))).to eq("-0,1 %")
    expect(doc.css("#main table")[1].at_css("tfoot td").text.strip).to eq("Summe")
  end

  it "is a tab of the Controlling area" do
    get :index
    tabs = doc.css(".nav-tabs a, ul.nav a").map { |a| a.text.strip }
    expect(tabs).to include("Übersicht", "Budget")
  end
end
