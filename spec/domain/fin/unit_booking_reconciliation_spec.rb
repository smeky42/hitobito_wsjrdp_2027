# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# What the units see, sorted into Unit-Budget, assigned and open, and the
# assignment of a secondary cost center. Invented numbers, names and amounts.
describe Fin::UnitBookingReconciliation do
  # An expense Konto: with "C" its signed amount comes out positive. 700000
  # names no account, so the Konto decides the Unit-Budget alone: 66500 says
  # yes, 66630 and 66680 say no.
  def book(amount, primary:, secondary: nil, konto: "66630")
    DatevBooking.create!(buchungs_guid: SecureRandom.uuid,
      account_number: konto, account_kind: "EXPENSE",
      offsetting_account_number: "700000", offsetting_account_kind: "CREDITOR",
      cost_center_number: primary, secondary_cost_center_number: secondary,
      base_amount: amount, transaction_amount: amount, debit_credit: "C",
      base_currency: "EUR", booking_date: Date.new(2026, 5, 1),
      posting_text: "Test #{primary}")
  end

  before do
    WsjrdpCostCenter.create!(number: "U1", name: "Unit U1", is_unit_cost_center: true)
    WsjrdpCostCenter.create!(number: "U2", name: "Unit U2", is_unit_cost_center: true)
    WsjrdpCostCenter.create!(number: "3810", name: "Unit Treffen Reisekosten")
    WsjrdpCostCenter.create!(number: "3800", name: "UL-Team-Wochenende")
    WsjrdpLedgerAccount.create!(number: "66500", name: "Verpflegung", is_unit_budget: true)
    WsjrdpLedgerAccount.create!(number: "66630", name: "Reisekosten ÖPNV", is_unit_budget: false)
    WsjrdpLedgerAccount.create!(number: "66680", name: "Kilometergeld", is_unit_budget: false)
  end

  let!(:unit_budget) { book(100, primary: "U1", konto: "66500") }
  let!(:unit_budget_with_secondary) { book(50, primary: "U1", secondary: "3810", konto: "66500") }
  let!(:open_oepnv) { book(30, primary: "U1") }
  let!(:open_km) { book(20, primary: "U2", konto: "66680") }
  let!(:central_with_unit) { book(70, primary: "3800", secondary: "U1", konto: "66500") }
  let!(:unit_with_central) { book(40, primary: "U1", secondary: "3810") }
  let!(:elsewhere) { book(99, primary: "1600") }
  # A booking naming the unit only as secondary cost center whose primary one
  # is unknown: the accounts decide, and 66500 says yes -- it counts against
  # the Unit-Budget, as the group's tile counts it, so it is no assigned one.
  let!(:unknown_primary) { book(8, primary: "X9", secondary: "U1", konto: "66500") }

  let(:reconciliation) { described_class.new }

  it "sorts what the units see into three disjoint sets" do
    expect(reconciliation.shown.pluck(:id)).to contain_exactly(unit_budget.id, unit_budget_with_secondary.id,
      open_oepnv.id, open_km.id, central_with_unit.id, unit_with_central.id, unknown_primary.id)
    expect(reconciliation.unit_budget.pluck(:id))
      .to contain_exactly(unit_budget.id, unit_budget_with_secondary.id, unknown_primary.id)
    expect(reconciliation.assigned.pluck(:id)).to contain_exactly(central_with_unit.id, unit_with_central.id)
    expect(reconciliation.open.pluck(:id)).to contain_exactly(open_oepnv.id, open_km.id)
  end

  it "counts and sums a set, signed" do
    expect(reconciliation.figure(reconciliation.open)).to have_attributes(count: 2, sum: 50)
    expect(reconciliation.figure(reconciliation.shown).count).to eq(7)
  end

  # The deciding side of the rule names the atom: the Konto, the Gegenkonto
  # where it alone said no, the booking where its flag did.
  it "groups the open bookings by the account that keeps them out, as atoms" do
    refund = DatevBooking.create!(buchungs_guid: SecureRandom.uuid,
      account_number: "18000", account_kind: "BANK",
      offsetting_account_number: "66680", offsetting_account_kind: "EXPENSE",
      cost_center_number: "U1", base_amount: 12, transaction_amount: 12, debit_credit: "C",
      base_currency: "EUR", booking_date: Date.new(2026, 5, 2), posting_text: "RK")
    flagged = book(5, primary: "U2", konto: "66500")
    flagged.update!(is_unit_budget: false)

    atoms = reconciliation.open_atoms
    expect(atoms.map(&:key)).to eq(%w[b g66680 k66630 k66680])
    expect(atoms.map(&:label)).to eq(["Buchung (Flag nein)", "Gegenkto 66680 Kilometergeld",
      "Konto 66630 Reisekosten ÖPNV", "Konto 66680 Kilometergeld"])
    expect(atoms.map(&:count)).to eq([1, 1, 1, 1])
    expect(atoms.find { |atom| atom.key == "k66630" }.sum).to eq(30)
    expect(reconciliation.with_atom(reconciliation.open, described_class::OPEN_ATOM_SQL)
      .find(refund.id).selection_atom).to eq("g66680")
    expect(reconciliation.with_atoms(reconciliation.open, described_class::OPEN_ATOM_SQL, %w[g66680 b])
      .pluck(:id)).to contain_exactly(refund.id, flagged.id)
  end

  it "groups the assigned bookings by the pair's central cost center" do
    atoms = reconciliation.assigned_atoms
    expect(atoms.map { |atom| [atom.key, atom.label, atom.count] })
      .to eq([["3800", "3800 UL-Team-Wochenende", 1], ["3810", "3810 Unit Treffen Reisekosten", 1]])
    expect(reconciliation.with_atom(reconciliation.assigned, described_class::ASSIGNED_ATOM_SQL)
      .find(central_with_unit.id).selection_atom).to eq("3800")
  end

  it "proposes 3810 for the travel-cost accounts, on either side, and nothing otherwise" do
    refund = DatevBooking.create!(buchungs_guid: SecureRandom.uuid,
      account_number: "18000", account_kind: "BANK",
      offsetting_account_number: "66680", offsetting_account_kind: "EXPENSE",
      cost_center_number: "U1", base_amount: 12, transaction_amount: 12, debit_credit: "C",
      base_currency: "EUR", booking_date: Date.new(2026, 5, 2), posting_text: "RK")

    expect(reconciliation.proposal(open_oepnv).number).to eq("3810")
    expect(reconciliation.proposal(refund).number).to eq("3810")
    expect(reconciliation.proposal(unit_budget)).to be_nil
    expect(described_class.label(reconciliation.proposal(open_oepnv))).to eq("3810 Unit Treffen Reisekosten")
  end

  it "proposes nothing where the master data lacks the cost center" do
    WsjrdpCostCenter.find_by(number: "3810").destroy!
    expect(described_class.new.proposal(open_oepnv)).to be_nil
  end

  it "offers every cost center but the units' own for assignment" do
    expect(reconciliation.assignable_cost_centers.map(&:number)).to include("3800", "3810")
    expect(reconciliation.assignable_cost_centers.map(&:number)).not_to include("U1", "U2")
  end

  it "assigns the secondary cost center to the open bookings among the ids only" do
    changed = reconciliation.assign!([open_oepnv.id, unit_budget.id, elsewhere.id, 0], "3810")

    expect(changed).to eq(1)
    expect(open_oepnv.reload.secondary_cost_center_number).to eq("3810")
    expect(unit_budget.reload.secondary_cost_center_number).to be_nil
    expect(elsewhere.reload.secondary_cost_center_number).to be_nil
    expect(reconciliation.open.pluck(:id)).to eq([open_km.id])
  end

  it "takes the secondary cost center off the assigned bookings among the ids only" do
    changed = reconciliation.clear!([central_with_unit.id, unit_with_central.id, unit_budget_with_secondary.id, 0])

    expect(changed).to eq(2)
    expect(central_with_unit.reload.secondary_cost_center_number).to be_nil
    expect(unit_with_central.reload.secondary_cost_center_number).to be_nil
    expect(unit_budget_with_secondary.reload.secondary_cost_center_number).to eq("3810")
    expect(reconciliation.open.pluck(:id)).to contain_exactly(open_oepnv.id, open_km.id, unit_with_central.id)
  end

  it "refuses a number that is no assignable cost center" do
    expect { reconciliation.assign!([open_oepnv.id], "U2") }.to raise_error(ArgumentError, /U2/)
    expect { reconciliation.assign!([open_oepnv.id], "9999x") }.to raise_error(ArgumentError)
    expect(open_oepnv.reload.secondary_cost_center_number).to be_nil
  end
end
