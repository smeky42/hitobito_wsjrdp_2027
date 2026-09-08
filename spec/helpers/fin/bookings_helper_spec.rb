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
end
