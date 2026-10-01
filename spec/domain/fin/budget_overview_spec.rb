# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Budget against DATEV actuals per cost center and year. Invented numbers,
# names and amounts.
describe Fin::BudgetOverview do
  # A bank Konto, so signed_base_amount is -amount for "C": an outflow, which
  # the overview counts as positive spending.
  def spend(number, amount, date, debit_credit = "C", secondary: nil, is_unit_budget: nil)
    DatevBooking.create!(buchungs_guid: SecureRandom.uuid,
      account_number: "1200", account_kind: "BANK",
      offsetting_account_number: "66500", offsetting_account_kind: "EXPENSE",
      cost_center_number: number, secondary_cost_center_number: secondary,
      is_unit_budget: is_unit_budget, base_amount: amount, transaction_amount: amount,
      debit_credit: debit_credit, base_currency: "EUR", booking_date: date,
      posting_text: "Test #{number}")
  end

  before do
    WsjrdpCostCenter.create!(number: "K100", name: "Alpha", budget_2025: 1000, budget_2026: 500)
    WsjrdpCostCenter.create!(number: "K200", name: "Beta")
    WsjrdpCostCenter.create!(number: "K300", name: "Gamma")
    WsjrdpCostCenter.create!(number: "U1", name: "Unit 1", explicit_total_budget: 2000,
      is_unit_cost_center: true)
    spend("K100", 900, Date.new(2025, 5, 1))
    spend("K100", 600, Date.new(2026, 2, 1))
    spend("K100", 300, Date.new(2026, 3, 1), "D")
    spend("K200", 40, Date.new(2026, 1, 1))
    spend("U1", 300, Date.new(2026, 4, 1))
    spend("K999", 7, Date.new(2026, 4, 1))
    spend("9", 5000, Date.new(2026, 4, 1))
  end

  let(:overview) { described_class.new }

  def row(number) = overview.rows.find { |r| r.number == number }

  it "puts the cost centers with a budget or bookings into rows, the units not" do
    expect(overview.rows.map(&:number)).to eq(%w[K100 K200 K999])
  end

  it "counts the bookings of a year against that year's budget, spending positive" do
    expect(row("K100").cells[2025]).to have_attributes(budget: 1000, actual: 900)
    expect(row("K100").cells[2026]).to have_attributes(budget: 500, actual: 300)
    expect(row("K100").cells[2025].percent).to eq(90)
    expect(row("K100").total).to have_attributes(budget: 1500, actual: 1200)
  end

  # The budget assignment (DatevBooking::BUDGET_COST_CENTER_SQL): a unit's
  # booking outside its Unit-Budget counts against a regular secondary cost
  # center; inside the Unit-Budget it stays with the unit, and a regular
  # primary cost center keeps its booking whatever the secondary one says.
  describe "the budget assignment" do
    before do
      WsjrdpCostCenter.create!(number: "U2", name: "Unit 2", is_unit_cost_center: true)
      spend("U1", 50, Date.new(2026, 5, 1), secondary: "K200", is_unit_budget: false)
      spend("U1", 60, Date.new(2026, 5, 2), secondary: "K200", is_unit_budget: true)
      spend("U1", 70, Date.new(2026, 5, 3), secondary: "U2", is_unit_budget: false)
      spend("K100", 80, Date.new(2026, 5, 4), secondary: "K200")
    end

    it "counts a unit's booking outside its Unit-Budget against the regular secondary cost center" do
      expect(row("K200").cells[2026]).to have_attributes(actual: 90, secondary: 50)
      expect(row("K200").total).to have_attributes(actual: 90, secondary: 50)
    end

    it "leaves the primary cost center its own bookings" do
      expect(row("K100").cells[2026]).to have_attributes(actual: 380, secondary: 0)
    end

    it "agrees with the bookings filter" do
      assigned = Arel::Nodes::Equality.new(Arel.sql("(#{DatevBooking::BUDGET_COST_CENTER_SQL})"),
        Arel::Nodes.build_quoted("K200"))
      filtered = DatevBooking.with_unit_budget_accounts.where(assigned)
      expect(-filtered.sum(:signed_base_amount)).to eq(row("K200").total.actual)
    end
  end

  it "colors by the share spent" do
    expect(row("K100").cells[2025].level).to eq(:warn)
    expect(row("K100").cells[2026].level).to eq(:ok)
    expect(row("K200").cells[2026].level).to eq(:unbudgeted)
    expect(row("K100").cells[2027].level).to eq(:empty)
    expect(described_class::Cell.new(budget: 100, actual: 101).level).to eq(:over)
    expect(described_class::Cell.new(budget: 100, actual: 80).level).to eq(:ok)
    expect(described_class::Cell.new(budget: 100, actual: 100).level).to eq(:warn)
    expect(described_class::Cell.new(budget: 100, actual: -20).level).to eq(:income)
    expect(described_class::Cell.new(budget: 100, actual: -20).percent).to eq(-20)
    expect(described_class::Cell.new(budget: nil, actual: -20).level).to eq(:income)
  end

  it "shows a number only bookings carry, and leaves out the placeholder number" do
    expect(row("K999")).to have_attributes(cost_center: nil, name: nil)
    expect(row("9")).to be_nil
  end

  it "sums the rows in sum spending and those in sum income apart, with or without a budget" do
    spend("K300", 80, Date.new(2026, 5, 1), "D")
    spending, income = overview.sums
    expect(spending.sum_label).to eq("Alle Ausgaben")
    expect(spending.total).to have_attributes(budget: 1500, actual: 1247)
    expect(spending.cells[2025]).to have_attributes(budget: 1000, actual: 900)
    expect(spending.cells[2026]).to have_attributes(budget: 500, actual: 347)
    expect(spending.cells[2027]).to be_empty
    expect(income.sum_label).to eq("Alle Einnahmen")
    expect(income.total).to have_attributes(budget: nil, actual: -80)
  end

  it "counts a cost center with a budget as spending, even while its IST is income" do
    spend("K100", 5000, Date.new(2026, 6, 1), "D")
    expect(row("K100").total.actual).to be_negative
    expect(overview.sums.map(&:sum_label)).to eq(["Alle Ausgaben"])
    expect(overview.sums.first.total).to have_attributes(budget: 1500, actual: -3753)
  end

  it "has no income sum without a row in sum income" do
    expect(overview.sums.map(&:sum_label)).to eq(["Alle Ausgaben"])
  end
end
