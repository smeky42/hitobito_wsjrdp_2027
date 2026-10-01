# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The unit table of the Budget page. Invented numbers and amounts.
describe Fin::UnitBudgetOverview do
  # A bank Konto, so "C" is an outflow: spending, counted positive here.
  def spend(amount, primary:, secondary: nil, is_unit_budget: nil)
    DatevBooking.create!(buchungs_guid: SecureRandom.uuid,
      account_number: "1200", account_kind: "BANK",
      offsetting_account_number: "66500", offsetting_account_kind: "EXPENSE",
      cost_center_number: primary, secondary_cost_center_number: secondary,
      is_unit_budget: is_unit_budget, base_amount: amount, transaction_amount: amount,
      debit_credit: "C", base_currency: "EUR", booking_date: Date.new(2026, 4, 1),
      posting_text: "Test")
  end

  before do
    WsjrdpCostCenter.create!(number: "U1", name: "Unit 1", explicit_total_budget: 1000,
      is_unit_cost_center: true)
    WsjrdpCostCenter.create!(number: "U2", name: "Unit 2", is_unit_cost_center: true)
    WsjrdpCostCenter.create!(number: "K100", name: "Zentral", is_unit_cost_center: false)
    spend(300, primary: "U1")
    spend(200, primary: "U1", is_unit_budget: false)
    spend(50, primary: "K100", secondary: "U1")
    spend(40, primary: "U1", secondary: "U1")
    spend(70, primary: "K100", secondary: "U2")
  end

  let(:overview) { described_class.new }

  def row(number) = overview.rows.find { |r| r.number == number }

  it "lists every unit cost center" do
    expect(overview.rows.map(&:number)).to eq(%w[U1 U2])
  end

  it "counts every booking on the primary or the secondary cost center, once" do
    expect(row("U1").expenses).to eq(590)
    expect(row("U2").expenses).to eq(70)
  end

  it "measures the Unit-Budget spending against the Gesamtbudget" do
    expect(row("U1").unit_budget).to have_attributes(budget: 1000, actual: 340)
    expect(row("U2").unit_budget).to have_attributes(budget: nil, actual: 0)
  end

  it "agrees with the finance tiles of a group with the unit's cost center" do
    figures = Fin::GroupBookkeepingFigures.new(["U1"])
    expect(row("U1").expenses).to eq(figures.expenses_total)
    expect(row("U1").unit_budget.actual).to eq(figures.expenses_unit_budget)
    expect(row("U1").unit_budget.budget).to eq(figures.budget)
  end

  it "sums all spending, and the Unit-Budget spending of the units with a budget" do
    expect(overview.sum.expenses).to eq(660)
    expect(overview.sum.unit_budget).to have_attributes(budget: 1000, actual: 340)
  end
end
