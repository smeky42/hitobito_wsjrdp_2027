# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The cells of the Controlling page "Budget". Invented numbers and amounts.
describe Fin::BudgetsHelper do
  def cell(budget, actual, secondary: 0)
    Fin::BudgetOverview::Cell.new(budget: budget&.to_d, actual: actual.to_d, secondary: secondary.to_d)
  end

  def parts(budget_cell, **options) = Nokogiri::HTML.fragment(helper.fin_budget_cell_parts(budget_cell, **options))

  def tip_text(budget_cell, heading: "K100 Alpha · 2025")
    Nokogiri::HTML.fragment(helper.fin_budget_cell(budget_cell, heading: heading))
      .at_css("template.fin-budget-tip-content").xpath(".//text()").map(&:text).join(" ").squish
  end

  it "shows IST against budget in whole euros, the percent and a full red bar over 100 %" do
    html = parts(cell(1000, 1234))

    aggregate_failures do
      expect(html.at_css(".fin-budget-amounts").text.squish).to eq("1.234 / 1.000")
      expect(html.at_css(".fin-budget-percent").text).to eq("123,4 %")
      fill = html.at_css(".fin-budget-bar-fill")
      expect(fill["class"]).to include("fin-budget-over")
      expect(fill["style"]).to eq("width: 100%; background-color: #{helper.fin_budget_scale_color(123.4)}")
      expect(html.at_css(".fin-budget-percent")["style"]).to eq("color: #{helper.fin_budget_scale_color(123.4)}")
    end
  end

  it "shows income as a negative percent with a green bar as long as its absolute share" do
    html = parts(cell(1000, -266))

    aggregate_failures do
      expect(html.at_css(".fin-budget-percent").text).to eq("-26,6 %")
      expect(html.at_css(".fin-budget-bar-fill")["class"]).to include("fin-budget-income")
      expect(html.at_css(".fin-budget-bar-fill")["style"]).to eq("width: 26.6%")
    end
  end

  it "labels the percent with one decimal, IST without budget as such, an empty cell not at all" do
    aggregate_failures do
      expect(helper.fin_budget_percent_label(cell(1000, -1))).to eq("-0,1 %")
      expect(helper.fin_budget_percent_label(cell(nil, 50))).to eq("ohne Budget")
      expect(helper.fin_budget_percent_label(cell(nil, 0))).to be_nil
    end
  end

  it "leaves a cell without budget and IST empty" do
    expect(helper.fin_budget_cell(cell(nil, 0), heading: "x")).to eq("")
  end

  it "repeats the cell with cents in the tooltip and names the part through the secondary cost center" do
    aggregate_failures do
      expect(tip_text(cell(1000, 1234))).to eq("K100 Alpha · 2025 1.234,00 € / 1.000,00 € 123,4 %")
      expect(tip_text(cell(1000, 1234, secondary: 100)))
        .to end_with("davon 100,00 € über sekundäre Kostenstelle")
    end
  end

  it "sets the measures the column is sorted by in bold" do
    state = instance_double(Wsjrdp::TableState, sort_list: [["year_2025__pct", "desc"], ["number", "asc"]])
    allow(state).to receive(:sort_column_for) { |key| key.split("__").first }
    sorted = helper.fin_budget_sorted_measures(state, "year_2025")

    aggregate_failures do
      expect(sorted).to eq(["pct"])
      expect(parts(cell(100, 50), sorted: sorted).at_css(".fin-budget-percent .fin-budget-sorted").text).to eq("50,0 %")
    end
  end

  it "colors on one scale: sand at 0 %, amber at 80 %, red at 100 %, bordeaux from 150 %" do
    aggregate_failures do
      expect(helper.fin_budget_scale_color(0)).to eq("color-mix(in oklch, #E3A21A 0%, #D9D2BF)")
      expect(helper.fin_budget_scale_color(40)).to eq("color-mix(in oklch, #E3A21A 50%, #D9D2BF)")
      expect(helper.fin_budget_scale_color(90)).to eq("color-mix(in oklch, #BE1E2D 50%, #E3A21A)")
      expect(helper.fin_budget_scale_color(400)).to eq("color-mix(in oklch, #6E0D18 100%, #BE1E2D)")
    end
  end

  it "heads a sum row's tooltip with its label and names a cost center by number and name" do
    sum = Fin::BudgetOverview::Row.new(number: nil, cost_center: nil, cells: {}, total: cell(nil, 0),
      sum_label: "Alle Ausgaben")
    center = Fin::BudgetOverview::Row.new(number: "K100", cost_center: WsjrdpCostCenter.new(name: "Alpha"),
      cells: {}, total: cell(nil, 0))

    aggregate_failures do
      expect(helper.fin_budget_tip_heading(sum, "Gesamt")).to eq("Alle Ausgaben · Gesamt")
      expect(helper.fin_budget_name_cell(sum)).to eq("Alle Ausgaben")
      expect(helper.fin_budget_tip_heading(center, "2025")).to eq("K100 Alpha · 2025")
      expect(Nokogiri::HTML.fragment(helper.fin_budget_name_cell(center)).text).to eq("K100Alpha")
    end
  end
end
