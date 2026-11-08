# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe WsjrdpInternalTransfer do
  let(:transfer) { described_class.create! }

  def camt(amount, reference: SecureRandom.hex(8), **attrs)
    WsjrdpCamtTransaction.create!(camt_type: "CAMT053", account_identification: "DE-TEST",
      account_servicer_reference: reference, credit_debit_indication: amount.negative? ? "DBIT" : "CRDT",
      signed_base_amount: amount, base_currency: "EUR", value_date: Date.new(2026, 4, 2),
      description: "Beispielbuchung", **attrs)
  end

  def top_up(amount, **attrs)
    MossTopUp.create!(moss_transaction_uuid: SecureRandom.uuid, signed_total_base_amount: amount,
      signed_total_transaction_amount: amount, currency: "EUR", booking_date: Date.new(2026, 4, 2), **attrs)
  end

  it "starts with empty json columns" do
    expect(transfer.reload).to have_attributes(link_meta: {}, additional_info: {})
  end

  describe "legs" do
    it "links bank and Moss transactions from both sides" do
      debit = camt(-100, internal_transfer: transfer)
      moss = top_up(100, internal_transfer: transfer)

      expect(transfer.reload.camt_transactions).to eq([debit])
      expect(transfer.moss_transactions).to eq([moss])
      expect(transfer.legs).to contain_exactly(debit, moss)
      expect(debit.reload.internal_transfer).to eq(transfer)
      expect(moss.reload.internal_transfer).to eq(transfer)
    end

    it "leaves out a bank transaction that was replaced or deleted" do
      kept = camt(-100, internal_transfer: transfer)
      camt(-100, internal_transfer: transfer, replaced_by_id: kept.id)
      camt(-100, internal_transfer: transfer, deleted_at: Time.zone.now)

      expect(transfer.legs).to eq([kept])
      expect(transfer.balance).to eq(-100)
    end
  end

  describe "#complete?" do
    it "is true for two legs summing to 0 across both tables" do
      camt(-100.5, internal_transfer: transfer)
      top_up(100.5, internal_transfer: transfer)

      expect(transfer.balance).to eq(0)
      expect(transfer).to be_complete
    end

    it "is true for one bank leg split over two counter legs" do
      camt(-100, internal_transfer: transfer)
      camt(60, internal_transfer: transfer)
      camt(40, internal_transfer: transfer)

      expect(transfer).to be_complete
    end

    it "is false while the other leg is missing, and such a transfer is valid" do
      camt(-100, internal_transfer: transfer)

      expect(transfer).to be_valid
      expect(transfer).not_to be_complete
    end

    it "is false when the legs do not sum to 0" do
      camt(-100, internal_transfer: transfer)
      camt(90, internal_transfer: transfer)

      expect(transfer.balance).to eq(-10)
      expect(transfer).not_to be_complete
    end

    it "is false without legs" do
      expect(transfer).not_to be_complete
    end
  end

  describe ".without_internal_transfer" do
    it "selects the bank transactions that are no leg" do
      leg = camt(-100, internal_transfer: transfer)
      other = camt(-50)

      scope = WsjrdpCamtTransaction.where(id: [leg.id, other.id]).without_internal_transfer
      expect(scope).to eq([other])
    end

    it "selects the Moss transactions that are no leg" do
      leg = top_up(100, internal_transfer: transfer)
      other = top_up(50)

      scope = MossTransaction.where(id: [leg.id, other.id]).without_internal_transfer
      expect(scope).to eq([other])
    end
  end

  describe "destroying" do
    it "keeps the legs and clears their link" do
      debit = camt(-100, internal_transfer: transfer)
      moss = top_up(100, internal_transfer: transfer)

      transfer.destroy!

      expect(debit.reload.internal_transfer_id).to be_nil
      expect(moss.reload.internal_transfer_id).to be_nil
    end
  end

  describe "sides, status and amount" do
    it "puts outflows on the Von side and inflows on the Nach side" do
      out = camt(-100, internal_transfer: transfer)
      into = top_up(100, internal_transfer: transfer)

      expect(transfer.from_legs.map(&:record)).to eq([out])
      expect(transfer.to_legs.map(&:record)).to eq([into])
      expect(transfer.status).to eq(:complete)
      expect(transfer.amount).to eq(100)
    end

    it "is open without an inflow even when the sum is 0 by accident" do
      camt(-100, internal_transfer: transfer)
      camt(100, internal_transfer: transfer).update_columns(signed_base_amount: -0.0)

      expect(transfer).not_to be_complete
      expect(transfer.status).to eq(:open)
      expect(transfer.amount).to eq(100)
    end

    it "dates the transfer by its earliest leg" do
      camt(-100, internal_transfer: transfer, value_date: Date.new(2026, 4, 3))
      top_up(100, internal_transfer: transfer, booking_date: Date.new(2026, 4, 2))

      expect(transfer.date).to eq(Date.new(2026, 4, 2))
    end
  end

  describe ".link!" do
    it "makes the rows legs of a new transfer, with its link_meta" do
      out = camt(-100)
      into = top_up(100)

      linked = described_class.link!([out, into], meta: {"source" => "suggestion"}, comment: "Notiz")

      expect(linked.legs).to contain_exactly(out, into)
      expect(linked.link_meta).to include("source" => "suggestion", "at" => be_present)
      expect(linked.comment).to eq("Notiz")
    end

    it "creates nothing when a row is already a leg" do
      out = camt(-100, internal_transfer: transfer)

      expect { described_class.link!([out, top_up(100)]) }
        .to raise_error(described_class::LegTaken)
        .and not_change(described_class, :count)
    end

    it "refuses a bank transaction that was replaced" do
      out = camt(-100)
      out.update_columns(replaced_by_id: camt(-100).id)

      expect { described_class.link!([out]) }.to raise_error(described_class::LegTaken)
    end
  end

  describe "#change!" do
    let!(:out) { camt(-100, internal_transfer: transfer) }
    let!(:into) { top_up(100, internal_transfer: transfer) }

    it "adds and removes legs and records the edit" do
      other = top_up(100)

      transfer.change!(comment: "neu", add: [other], remove: [into], by: {"name" => "Test"})

      expect(transfer.reload.legs).to contain_exactly(out, other)
      expect(into.reload.internal_transfer_id).to be_nil
      expect(transfer.comment).to eq("neu")
      expect(transfer.link_meta["edits"].last)
        .to include("by" => {"name" => "Test"}, "added" => ["moss:#{other.id}"], "removed" => ["moss:#{into.id}"])
    end

    it "changes only the comment without an edit entry" do
      transfer.change!(comment: "nur Text")

      expect(transfer.reload.comment).to eq("nur Text")
      expect(transfer.link_meta).not_to have_key("edits")
    end

    it "dissolves the transfer once it has no legs left" do
      transfer.change!(comment: nil, remove: [out, into])

      expect(transfer).to be_destroyed
      expect(out.reload.internal_transfer_id).to be_nil
    end

    it "rolls everything back when an added row is taken" do
      taken = top_up(100, internal_transfer: described_class.create!)

      expect { transfer.change!(comment: "x", add: [taken], remove: [into]) }
        .to raise_error(described_class::LegTaken)
      expect(into.reload.internal_transfer_id).to eq(transfer.id)
      expect(transfer.reload.comment).to eq("")
    end
  end

  describe "the marks of a leg" do
    it "keeps 'no transfer' and the denied candidates in additional_info, next to what is there" do
      row = camt(-100)
      row.update_columns(additional_info: {"return_debit_status" => "paid"})

      row.mark_not_internal_transfer!
      row.deny_internal_transfer_candidate!("moss:1")
      row.deny_internal_transfer_candidate!("moss:1")

      expect(row.reload).to be_not_internal_transfer
      expect(row.denied_internal_transfer_candidates).to eq(["moss:1"])
      expect(row.additional_info["return_debit_status"]).to eq("paid")
    end

    it "names a leg across both tables" do
      expect(camt(-1).internal_transfer_leg_key).to start_with("camt:")
      expect(top_up(1).internal_transfer_leg_key).to start_with("moss:")
    end
  end
end
