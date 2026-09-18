# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The three figures above a group's Buchungen table. All numbers, names and
# booking texts invented.
#
# The Konto is a BANK account, so signed_base_amount is +amount for "D" and
# -amount for "C" (doc/fin/money_conventions.md) -- the spendings below are
# therefore booked "C" and come out negative, while the budgets they are
# measured against are stored positive.
describe Fin::GroupBookkeepingFigures do
  # A1 is the unit's own cost center and carries the budget; A2 belongs to the
  # group as well but is not a unit cost center, so its budget says nothing
  # about what the unit may spend. B1 is another group's.
  let!(:unit_cost_center) do
    WsjrdpCostCenter.create!(number: "A1", name: "Kostenstelle A1",
      is_unit_cost_center: true, explicit_total_budget: 1000)
  end
  let!(:other_cost_center) do
    WsjrdpCostCenter.create!(number: "A2", name: "Kostenstelle A2",
      explicit_total_budget: 500)
  end
  # Another unit's own cost center: a booking on it reaches the accounts, which
  # is what lets the account flag below decide rather than the cost center.
  let!(:foreign_cost_center) do
    WsjrdpCostCenter.create!(number: "B1", name: "Kostenstelle B1", is_unit_cost_center: true)
  end

  # 66600 says a booking on it is NOT a unit's; 66500 names no master record at
  # all, so those bookings fall to the default and count.
  let!(:non_unit_account) do
    WsjrdpLedgerAccount.create!(number: "66600", name: "Testaufwand zentral",
      is_unit_budget: false)
  end

  def create_booking(amount, cost_center:, secondary: nil, offsetting: "66500")
    DatevBooking.create!(buchungs_guid: SecureRandom.uuid,
      account_number: "1200", account_kind: "BANK",
      offsetting_account_number: offsetting, offsetting_account_kind: "EXPENSE",
      cost_center_number: cost_center, secondary_cost_center_number: secondary,
      base_amount: amount, transaction_amount: amount, debit_credit: "C",
      base_currency: "EUR", booking_date: Date.new(2026, 2, 1),
      posting_text: "Testbuchung #{cost_center}")
  end

  let!(:own) { create_booking(100, cost_center: "A1") }
  let!(:central) { create_booking(300, cost_center: "A2", offsetting: "66600") }
  let!(:via_secondary) { create_booking(50, cost_center: "B1", secondary: "A1") }
  let!(:foreign) { create_booking(999, cost_center: "B1") }

  subject(:figures) { described_class.new(%w[A1 A2]) }

  it "sums the bookings of the group on either cost-center column" do
    expect(figures.total).to eq(-450)
  end

  it "leaves the bookings of another group out" do
    expect(figures.total).not_to eq(-450 - 999)
  end

  # The subset the resolved rule calls true. The booking on A2 is out twice
  # over: A2 is not a unit's own cost center, and its Gegenkonto says no as well.
  it "sums the Unit-Budget part alone" do
    expect(figures.unit_budget).to eq(-150)
  end

  # The cost-centre step on its own: this booking's accounts both fall to the
  # default "yes", and it still does not count -- A2 is the group's, but not
  # the unit's own.
  it "keeps a booking on a cost center that is not a unit's own out" do
    create_booking(40, cost_center: "A2")

    expect(figures.total).to eq(-490)
    expect(figures.unit_budget).to eq(-150)
  end

  # Both cost centers of a booking are the group's: it belongs to the set once,
  # not twice -- the `or` is one condition over two columns, not a union.
  it "counts a booking whose two cost centers are both the group's once" do
    create_booking(20, cost_center: "A1", secondary: "A2")

    expect(figures.total).to eq(-470)
    expect(figures.unit_budget).to eq(-170)
  end

  # Only the cost centers marked as a unit's own carry the budget the tiles
  # measure against -- A2's 500 is the contingent's money.
  it "takes the budget from the unit cost centers alone" do
    expect(figures.budget).to eq(1000)
  end

  # The share is taken over the expenses (the signed sum turned), so a spending
  # unit's share is positive: 150 of 1000.
  it "states the used share in percent" do
    expect(figures.used_share).to eq(15)
  end

  # The tiles talk of expenses as positive figures: the signed booking sums
  # with their sign turned; the budget is positive as stored.
  it "turns the signed sums into expenses" do
    expect(figures.expenses_total).to eq(450)
    expect(figures.expenses_unit_budget).to eq(150)
    expect(figures).to be_budget
  end

  it "has no share where no cost center of the group is a unit's own" do
    unit_cost_center.update!(is_unit_cost_center: false)

    expect(described_class.new(%w[A1 A2]).budget).to eq(0)
    expect(described_class.new(%w[A1 A2]).used_share).to be_nil
  end

  it "has no share where the unit cost center carries no budget" do
    unit_cost_center.update!(explicit_total_budget: nil)

    expect(described_class.new(%w[A1 A2]).budget).to eq(0)
    expect(described_class.new(%w[A1 A2]).used_share).to be_nil
  end

  it "has no share where the budgets add up to zero" do
    unit_cost_center.update!(explicit_total_budget: 0)

    expect(described_class.new(%w[A1 A2]).used_share).to be_nil
    expect(described_class.new(%w[A1 A2])).not_to be_budget
  end

  it "answers zero for a group without cost centers" do
    empty = described_class.new([])

    expect(empty.total).to eq(0)
    expect(empty.unit_budget).to eq(0)
    expect(empty.used_share).to be_nil
  end

  # The booking's own flag is the first step and beats both the cost center and
  # the accounts.
  it "follows a booking's own Unit-Budget override" do
    central.update!(is_unit_budget: true)

    expect(described_class.new(%w[A1 A2]).unit_budget).to eq(-450)
  end
end
