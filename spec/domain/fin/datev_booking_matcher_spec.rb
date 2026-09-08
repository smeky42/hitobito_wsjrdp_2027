# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The deterministic half of the rating (doc/fin/recon_linking.md §3/§4): a link
# whose datev_booking_link_meta carries one of the automatic, import-equivalent
# classification values rates :automatic / 100 % with that value's canonical
# German label -- WITHOUT re-deriving anything from the booking text or the
# dates. Every name, date, amount and account number below is invented.
describe Fin::DatevBookingMatcher do
  let(:person) { Fabricate(:person) }

  # A fee booking whose text and dates deliberately carry NO signal: nothing
  # here could produce a rating on its own (see the last example), so a 100 %
  # result can only come from the stored classification.
  def booking(**attrs)
    DatevBooking.create!({buchungs_guid: SecureRandom.uuid,
                          account_number: "18000", account_kind: "BANK",
                          offsetting_account_number: "41030", offsetting_account_kind: "INCOME",
                          base_amount: 25, transaction_amount: 25, debit_credit: "D",
                          base_currency: "EUR", booking_date: Date.new(2026, 3, 10)}.merge(attrs))
  end

  # A Beitragsbuchung linked to `bkg`, stamped exactly as the DATEV importer
  # stamps an automatic link (author 1 = system, score 1.0).
  def entry(bkg, classification, **attrs)
    AccountingEntry.create!({subject: person, author: person, amount_eur: 25,
                             description: "Beitragsrate", value_date: Date.new(2025, 1, 2),
                             booking_date: Date.new(2025, 1, 2), datev_booking: bkg,
                             datev_booking_link_meta: {
                               "created_at" => "2026-03-11T08:00:00+01:00", "author_id" => 1,
                               "score" => 1.0, "automatic_manual" => "automatic",
                               "classification_string" => classification
                             }}.merge(attrs))
  end

  describe ".rate_pair" do
    described_class::AUTOMATIC_LINK_BASES.each do |classification, label|
      it "rates the automatic classification #{classification} as a locked 100 % match" do
        bkg = booking
        match = described_class.rate_pair(bkg, entry(bkg, classification))

        expect(match.kind).to eq :import
        expect(match.tier).to eq :automatic
        expect(match.score).to eq 100
        expect(match.basis).to eq label
        expect(match.details).to include(label)
      end
    end

    # The Retouren rule lives entirely in the importer (it needs the camt side
    # and a +-14-day uniqueness window), so the matcher can only ever READ its
    # classification back -- which is exactly what fixes the rating here.
    it "labels a Retoure link in German" do
      expect(described_class::AUTOMATIC_LINK_BASES[described_class::CLASSIFICATION_CAMT_RETURN])
        .to eq "Retoure: Rücklastschrift nach Betrag und Buchungsdatum"
    end

    it "rates an unclassified link of the same pair as no match at all" do
      bkg = booking
      expect(described_class.rate_pair(bkg, entry(bkg, nil))).to be_nil
    end
  end

  # A UI connect stamps only the two classifications detect_link_type can decide
  # from the pair alone; a Retoure pair stays unclassified there.
  describe ".connect_pair!" do
    it "does not stamp the Retoure classification on a manual connect" do
      bkg = booking(posting_text: "Retoure Beitrag", original_posting_text: "Retoure Beitrag")
      unlinked = AccountingEntry.create!(subject: person, author: person, amount_eur: -25,
        description: "Rücklastschrift", value_date: Date.new(2026, 3, 10),
        booking_date: Date.new(2026, 3, 10))

      expect(described_class.connect_pair!(bkg, unlinked, linked_by_id: person.id)).to be true
      meta = unlinked.reload.datev_booking_link_meta
      expect(meta["classification_string"]).to be_nil
      expect(meta["automatic_manual"]).to eq "manual"
    end
  end
end
