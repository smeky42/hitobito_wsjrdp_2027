# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# How a booking's OWN link to its Beitragsbuchung reaches the booking detail:
# the rating of that one pair and the tier the chip colours it by. The words
# come from Fin::DatevBookingMatcher::AUTOMATIC_LINK_BASES, so this spec pins
# the label a reader actually sees next to the lock icon. Every name, date,
# amount and account number below is invented.
describe Fin::BookingsHelper do
  let(:person) { Fabricate(:person) }

  # A Retoure fee booking as the DATEV import delivers it: the fee side (41030)
  # is negative, "Retoure" stands in the Buchungstext.
  let(:booking) do
    DatevBooking.create!(buchungs_guid: SecureRandom.uuid,
      account_number: "18000", account_kind: "BANK",
      offsetting_account_number: "41030", offsetting_account_kind: "INCOME",
      base_amount: 25, transaction_amount: 25, debit_credit: "D",
      base_currency: "EUR", booking_date: Date.new(2026, 3, 10),
      posting_text: "Retoure Beitrag", original_posting_text: "Retoure Beitrag")
  end

  # The entry the importer linked to it, stamped with the Retouren rule.
  let!(:linked_entry) do
    AccountingEntry.create!(subject: person, author: person, amount_eur: -25,
      description: "Rücklastschrift", value_date: Date.new(2026, 2, 24),
      booking_date: Date.new(2026, 3, 10), datev_booking: booking,
      datev_booking_link_meta: {
        "created_at" => "2026-03-11T08:00:00+01:00", "author_id" => 1, "score" => 1.0,
        "automatic_manual" => "automatic",
        "classification_string" => Fin::DatevBookingMatcher::CLASSIFICATION_CAMT_RETURN
      })
  end

  describe "#booking_link_rating" do
    subject(:match) { helper.booking_link_rating(booking) }

    it "reads the Retoure classification back as a locked 100 % match" do
      expect(match.tier).to eq :automatic
      expect(match.score).to eq 100
    end

    it "labels it in German" do
      expect(match.basis).to eq "Retoure: Rücklastschrift nach Betrag und Buchungsdatum"
    end

    # The chip's look follows from the tier alone, so the new value gets the
    # same firm green + lock as the two older automatic classifications.
    it "is coloured by the automatic tier" do
      expect(helper.match_tier_style(match))
        .to eq described_class::MATCH_TIER_STYLES[:automatic]
    end

    it "is nil for a booking without a Beitragsbuchung" do
      linked_entry.update!(datev_booking: nil, datev_booking_link_meta: {})
      expect(helper.booking_link_rating(booking.reload)).to be_nil
    end
  end

  # The Unter-Kostenstelle select of the booking detail. A sub cost center
  # number is unique within its cost center only, so the choice is restricted to
  # the booking's own cost center.
  describe "#fin_sub_cost_center_select_options" do
    let!(:cost_center) { WsjrdpCostCenter.create!(number: "8100", name: "Kostenstelle A") }
    let!(:other_cost_center) { WsjrdpCostCenter.create!(number: "8200", name: "Kostenstelle B") }
    let!(:sub) do
      WsjrdpSubCostCenter.create!(cost_center: cost_center, number: "10",
        name: "Teil A", short_name: "A")
    end

    before do
      WsjrdpSubCostCenter.create!(cost_center: other_cost_center, number: "20", name: "Teil B")
      booking.update!(cost_center_number: "8100")
    end

    it "offers only the sub cost centers of the booking's own cost center" do
      expect(helper.fin_sub_cost_center_select_options(booking))
        .to eq([["nicht gesetzt", ""], ["10 A", "10"]])
    end

    it "offers nothing but the blank entry for a booking without a cost center" do
      booking.update!(cost_center_number: nil)

      expect(helper.fin_sub_cost_center_select_options(booking))
        .to eq([["nicht gesetzt", ""]])
    end

    # A DATEV import moved the booking to another cost center: the stored pair
    # no longer resolves, and the form must not drop the value silently.
    it "appends a current value that does not resolve" do
      booking.update!(sub_cost_center_number: "10")
      booking.update_columns(cost_center_number: "8200") # rubocop:disable Rails/SkipsModelValidations

      expect(helper.fin_sub_cost_center_select_options(booking.reload))
        .to eq([["nicht gesetzt", ""], ["20 Teil B", "20"], ["10", "10"]])
    end

    it "does not duplicate a current value that resolves" do
      booking.update!(sub_cost_center_number: sub.number)

      expect(helper.fin_sub_cost_center_select_options(booking))
        .to eq([["nicht gesetzt", ""], ["10 A", "10"]])
    end
  end
end
