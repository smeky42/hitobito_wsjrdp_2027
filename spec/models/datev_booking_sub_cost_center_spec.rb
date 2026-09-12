# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The sub cost center of a booking (doc/fin/sub_cost_centers.md): a link over
# BOTH numbers, without a foreign key, tolerating the pair a DATEV import can
# leave behind. Every number below is invented.
describe DatevBooking do
  def booking(attrs = {})
    defaults = {buchungs_guid: SecureRandom.uuid,
                booking_date: Date.new(2026, 1, 15),
                base_amount: 10, transaction_amount: 10,
                debit_credit: "D",
                account_number: "18000", account_kind: "BANK",
                offsetting_account_number: "66500", offsetting_account_kind: "EXPENSE",
                cost_center_number: "8100"}
    described_class.create!(defaults.merge(attrs))
  end

  let!(:cost_center) { WsjrdpCostCenter.create!(number: "8100", name: "Kostenstelle A") }
  let!(:other_cost_center) { WsjrdpCostCenter.create!(number: "8200", name: "Kostenstelle B") }
  # The SAME number under two cost centers -- a sub cost center number is unique
  # within its cost center only.
  let!(:sub) do
    WsjrdpSubCostCenter.create!(cost_center: cost_center, number: "10", name: "Teil A")
  end
  let!(:other_sub) do
    WsjrdpSubCostCenter.create!(cost_center: other_cost_center, number: "10", name: "Teil B")
  end

  describe "the association" do
    it "resolves within the booking's own cost center" do
      b = booking(sub_cost_center_number: "10")

      expect(b.reload.sub_cost_center).to eq(sub)
      expect(b.sub_cost_center).not_to eq(other_sub)
    end

    it "picks the sub cost center of the booking's cost center, not the other one" do
      b = booking(cost_center_number: "8200", sub_cost_center_number: "10")

      expect(b.reload.sub_cost_center).to eq(other_sub)
    end

    it "is nil when the number names no sub cost center under that cost center" do
      b = booking(sub_cost_center_number: "10")
      b.update_columns(cost_center_number: "8300") # rubocop:disable Rails/SkipsModelValidations

      expect(b.reload.sub_cost_center).to be_nil
    end

    it "preloads without touching the database again" do
      booking(sub_cost_center_number: "10")
      loaded = described_class.preload(:sub_cost_center).to_a

      expect(loaded.map(&:sub_cost_center)).to eq([sub])
    end
  end

  describe ".with_sub_cost_center" do
    # A short name of its own, so the two exposed columns are distinguishable
    # (display_short_name falls back to the name when short_name is blank).
    let!(:named_sub) do
      WsjrdpSubCostCenter.create!(cost_center: cost_center, number: "30",
        name: "Teil C", short_name: "C")
    end

    it "exposes the sub cost center's names as columns of the relation" do
      b = booking(sub_cost_center_number: "30")

      row = described_class.with_sub_cost_center.find(b.id)

      expect(row.sub_cost_center_name).to eq("Teil C")
      expect(row.sub_cost_center_short_name).to eq("C")
    end

    it "leaves both columns nil for a pair that does not resolve" do
      stale = booking(sub_cost_center_number: "30")
      stale.update_columns(cost_center_number: "8300") # rubocop:disable Rails/SkipsModelValidations
      unassigned = booking(sub_cost_center_number: nil)

      rows = described_class.with_sub_cost_center.index_by(&:id)

      expect(rows[stale.id].sub_cost_center_name).to be_nil
      expect(rows[stale.id].sub_cost_center_short_name).to be_nil
      expect(rows[stale.id].sub_cost_center_number).to eq("30")
      expect(rows[unassigned.id].sub_cost_center_name).to be_nil
    end

    it "keeps every ordinary booking column usable" do
      b = booking(sub_cost_center_number: "30", base_amount: 25,
        posting_text: "Testbuchung")

      row = described_class.with_sub_cost_center.find(b.id)

      expect(row.buchungs_guid).to eq(b.buchungs_guid)
      expect(row.posting_text).to eq("Testbuchung")
      expect(row.booking_date).to eq(Date.new(2026, 1, 15))
      expect(row.signed_base_amount).to eq(25)
      expect(row.sub_cost_center).to eq(named_sub)
    end

    it "composes with an ordinary where on the booking's own columns" do
      booking(sub_cost_center_number: "30")
      wanted = booking(cost_center_number: "8200", sub_cost_center_number: "10")

      rows = described_class.with_sub_cost_center.where(cost_center_number: "8200")

      expect(rows.map(&:id)).to eq([wanted.id])
      expect(rows.first.sub_cost_center_name).to eq("Teil B")
    end
  end

  describe "a pair that stopped resolving" do
    # What a DATEV import does: it rewrites the KOST field (cost_center_number)
    # of an existing booking. There is no foreign key, so the write goes through
    # and the stored pair can stop naming a row.
    let(:stale) do
      b = booking(sub_cost_center_number: "10")
      b.update_columns(cost_center_number: "8300") # rubocop:disable Rails/SkipsModelValidations
      b.reload
    end

    it "reads as nil but keeps its raw number" do
      expect(stale.sub_cost_center).to be_nil
      expect(stale.sub_cost_center_number).to eq("10")
    end

    it "still saves when another field changes" do
      expect(stale.update(user_comment: "geprüft")).to be(true)
      expect(stale.reload.sub_cost_center_number).to eq("10")
      expect(stale.user_comment).to eq("geprüft")
    end
  end

  # The pair is not validated: any number may be stored, and a pair that stops
  # resolving is a legal state -- a DATEV import moves a booking to another cost
  # center without touching its sub cost center. The edit control is what
  # narrows the choice (Fin::BookingsHelper#fin_sub_cost_center_select_options).
  describe "assigning a sub cost center" do
    it "accepts a sub cost center of the booking's own cost center" do
      expect(described_class.new(cost_center_number: "8100", sub_cost_center_number: "10"))
        .to be_valid
    end

    it "accepts a number that resolves to nothing" do
      b = booking(cost_center_number: nil)
      b.sub_cost_center_number = "10"

      expect(b).to be_valid
      expect(b.sub_cost_center).to be_nil
    end

    it "lets a stale pair be cleared" do
      b = booking(sub_cost_center_number: "10")
      b.update_columns(cost_center_number: "8300") # rubocop:disable Rails/SkipsModelValidations

      expect(b.reload.update(sub_cost_center_number: nil)).to be(true)
    end
  end
end
