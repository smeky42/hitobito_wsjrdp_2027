# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe WsjrdpSubCostCenter do
  let(:cost_center) { WsjrdpCostCenter.create!(number: "8100", name: "Testkostenstelle") }
  let(:other_cost_center) { WsjrdpCostCenter.create!(number: "8200", name: "Andere Kostenstelle") }

  # A booking on a BANK account debited: signed_base_amount is +base_amount.
  def booking(attrs = {})
    defaults = {buchungs_guid: SecureRandom.uuid, booking_date: Date.new(2026, 1, 15),
                base_amount: 10, transaction_amount: 10, debit_credit: "D",
                account_number: "18000", account_kind: "BANK",
                offsetting_account_number: "66500", offsetting_account_kind: "EXPENSE"}
    DatevBooking.create!(defaults.merge(attrs))
  end

  describe "cost_center association" do
    it "links by the cost center number, in both directions" do
      sub = described_class.create!(cost_center: cost_center, number: "10", name: "Teil A")

      expect(sub.cost_center_number).to eq("8100")
      expect(sub.reload.cost_center).to eq(cost_center)
      expect(cost_center.sub_cost_centers.reload).to eq([sub])
    end

    it "is optional: a cost_center_number naming no cost center is valid" do
      expect(described_class.new(cost_center_number: "8999", number: "10")).to be_valid
    end

    it "lets a cost center be destroyed, leaving its sub cost centers behind" do
      sub = described_class.create!(cost_center: cost_center, number: "10", name: "Teil A")

      expect(cost_center.destroy).to be_truthy
      expect(cost_center.errors).to be_empty
      expect(sub.reload.cost_center_number).to eq("8100")
      expect(sub.cost_center).to be_nil
    end
  end

  describe "datev_bookings association" do
    it "lists only the bookings of its own cost center" do
      sub = described_class.create!(cost_center: cost_center, number: "10")
      described_class.create!(cost_center: other_cost_center, number: "10")
      mine = booking(cost_center_number: "8100", sub_cost_center_number: "10")
      booking(cost_center_number: "8200", sub_cost_center_number: "10")

      expect(sub.datev_bookings.pluck(:id)).to eq([mine.id])
    end
  end

  describe ".with_booking_summary" do
    it "counts and sums only the bookings whose pair names the sub cost center" do
      sub = described_class.create!(cost_center: cost_center, number: "10")
      described_class.create!(cost_center: cost_center, number: "20")
      booking(cost_center_number: "8100", sub_cost_center_number: "10", base_amount: 25)
      booking(cost_center_number: "8100", sub_cost_center_number: "10", base_amount: 7)
      booking(cost_center_number: "8100", sub_cost_center_number: "20", base_amount: 100)
      booking(cost_center_number: "8100", base_amount: 500)

      row = described_class.with_booking_summary.find(sub.id)

      expect(row.booking_count).to eq(2)
      expect(row.booking_sum).to eq(32)
    end

    it "reports 0 and still appears for a sub cost center without bookings" do
      sub = described_class.create!(cost_center: cost_center, number: "30")

      row = described_class.with_booking_summary.find(sub.id)

      expect(row.booking_count).to eq(0)
      expect(row.booking_sum).to eq(0)
    end

    it "keeps the same number under two cost centers apart" do
      mine = described_class.create!(cost_center: cost_center, number: "10")
      theirs = described_class.create!(cost_center: other_cost_center, number: "10")
      booking(cost_center_number: "8100", sub_cost_center_number: "10", base_amount: 25)
      booking(cost_center_number: "8200", sub_cost_center_number: "10", base_amount: 7)
      booking(cost_center_number: "8200", sub_cost_center_number: "10", base_amount: 3)

      rows = described_class.with_booking_summary.index_by(&:id)

      expect(rows[mine.id].booking_count).to eq(1)
      expect(rows[mine.id].booking_sum).to eq(25)
      expect(rows[theirs.id].booking_count).to eq(2)
      expect(rows[theirs.id].booking_sum).to eq(10)
    end

    it "composes with an ordinary where on the model's own columns" do
      described_class.create!(cost_center: cost_center, number: "10", short_name: "A")
      described_class.create!(cost_center: other_cost_center, number: "10", short_name: "B")
      booking(cost_center_number: "8100", sub_cost_center_number: "10", base_amount: 25)
      booking(cost_center_number: "8200", sub_cost_center_number: "10", base_amount: 7)

      rows = described_class.with_booking_summary.where(cost_center_number: "8200")

      expect(rows.map(&:short_name)).to eq(["B"])
      expect(rows.sum(:booking_sum)).to eq(7)
    end
  end

  describe "number uniqueness" do
    it "allows the same number under another cost center" do
      described_class.create!(cost_center: cost_center, number: "10")

      expect(described_class.new(cost_center: other_cost_center, number: "10")).to be_valid
    end

    it "rejects the same number under the same cost center" do
      described_class.create!(cost_center: cost_center, number: "10")

      expect(described_class.new(cost_center: cost_center, number: "10")).not_to be_valid
    end
  end

  describe "generated columns" do
    it "derives display_short_name from short_name, falling back to name" do
      named = described_class.create!(cost_center: cost_center, number: "10", name: "Teil A")
      short = described_class.create!(cost_center: cost_center, number: "20",
        name: "Teil B", short_name: "B")

      expect(named.reload.display_short_name).to eq("Teil A")
      expect(short.reload.display_short_name).to eq("B")
    end

    it "takes the yearly sum or the explicit total, whichever is larger in absolute value" do
      summed = described_class.create!(cost_center: cost_center, number: "10",
        budget_2025: -1000, budget_2026: -500, explicit_total_budget: -900)
      explicit = described_class.create!(cost_center: cost_center, number: "20",
        budget_2025: -1000, explicit_total_budget: -4000)

      expect(summed.reload.effective_total_budget).to eq(-1500)
      expect(explicit.reload.effective_total_budget).to eq(-4000)
    end
  end

  describe "WsjrdpBudgetable" do
    it "reports the years that have a budget set" do
      sub = described_class.create!(cost_center: cost_center, number: "10",
        budget_2025: -1000, budget_2027: -250)

      expect(sub.budgets_by_year).to eq(2025 => -1000, 2027 => -250)
    end
  end

  describe "#to_s" do
    it "is the number and the short display name" do
      sub = described_class.create!(cost_center: cost_center, number: "10",
        name: "Teil A", short_name: "A")

      expect(sub.reload.to_s).to eq("10 A")
    end
  end
end
