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
  def spend(number, amount, date, debit_credit = "C")
    DatevBooking.create!(buchungs_guid: SecureRandom.uuid,
      account_number: "1200", account_kind: "BANK",
      offsetting_account_number: "66500", offsetting_account_kind: "EXPENSE",
      cost_center_number: number, base_amount: amount, transaction_amount: amount,
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

  it "sums per column only the cells with a budget" do
    expect(overview.sum.total).to have_attributes(budget: 1500, actual: 1200)
    expect(overview.sum.cells[2026]).to have_attributes(budget: 500, actual: 300)
    expect(overview.sum.cells[2027]).to be_empty
  end
end
