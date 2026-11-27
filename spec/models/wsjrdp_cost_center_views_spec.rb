# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Which cost center a booking counts for (WsjrdpCostCenter::VIEWS).
describe WsjrdpCostCenter do
  # K200 primary of one booking; the unit's U1 primary of another that names
  # K200 as secondary and is no Unit-Budget, so its budget counts for K200.
  before do
    described_class.create!(number: "K200", name: "Beta Zelte")
    described_class.create!(number: "U1", name: "Unit eins", is_unit_cost_center: true)
    [["K200", nil, nil], ["U1", "K200", false]].each do |primary, secondary, unit_budget|
      DatevBooking.create!(buchungs_guid: SecureRandom.uuid, account_number: "1200", account_kind: "BANK",
        offsetting_account_number: "66500", offsetting_account_kind: "EXPENSE", cost_center_number: primary,
        secondary_cost_center_number: secondary, is_unit_budget: unit_budget, base_amount: 5,
        transaction_amount: 5, debit_credit: "D", base_currency: "EUR", booking_date: Date.new(2026, 2, 1))
    end
  end

  def counts(view)
    described_class.with_booking_summary(view).where(number: %w[K200 U1]).order(:number).pluck(:booking_count)
  end

  def listed(number, view) = described_class.bookings_for(number, view).count

  it "counts a booking for the cost center the view names" do
    expect(%w[primary secondary any budget].to_h { |view| [view, counts(view)] })
      .to eq("primary" => [1, 1], "secondary" => [1, 0], "any" => [2, 1], "budget" => [2, 0])
  end

  it "lists a cost center's bookings by the same view" do
    expect(%w[primary secondary any budget].to_h { |view| [view, listed("K200", view)] })
      .to eq("primary" => 1, "secondary" => 1, "any" => 2, "budget" => 2)
  end
end
