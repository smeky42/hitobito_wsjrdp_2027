# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe MossTransaction do
  describe "#description" do
    it "joins the kind's name and the Buchungstext with an en dash" do
      tx = MossReimbursement.new(transaction_name: "Fahrt nach Mainz", transaction_posting_text: "RK Unit A1")
      expect(tx.description).to eq("Fahrt nach Mainz – RK Unit A1")
      expect(MossCardTransaction.new(merchant_name: "Supermarkt", transaction_posting_text: "Verpflegung").description)
        .to eq("Supermarkt – Verpflegung")
      expect(MossTopUp.new(top_up_sender: "Vereinskonto").description).to eq("Einzahlung – Vereinskonto")
    end

    it "falls back to the SEPA reference and never returns nil" do
      expect(MossInvoice.new(payment_reference: "RE 4711").description).to eq("RE 4711")
      expect(MossInvoice.new.description).to eq("")
    end

    it "truncates to the given length" do
      tx = MossReimbursement.new(transaction_name: "A" * 60, transaction_posting_text: "B" * 60)
      expect(tx.description(length: 100).length).to eq(100)
      expect(tx.description(length: 100)).to end_with("…")
      expect(tx.description(length: 200)).to eq(tx.description)
    end
  end

  # Every URL is derived from a stored uuid -- except a top-up's, which Moss
  # addresses by an internal id no export carries. All uuids below are invented.
  describe "#moss_record_url / #moss_export_url" do
    let(:uuid) { "11111111-2222-3333-4444-555555555555" }
    let(:kind_uuid) { "66666666-7777-8888-9999-000000000000" }

    it "derives the card payment's record and export pages from the transaction uuid" do
      tx = MossCardTransaction.new(moss_transaction_uuid: uuid)
      expect(tx.moss_record_url).to eq("https://getmoss.com/app/transactions/all/#{uuid}")
      expect(tx.moss_export_url).to eq("https://getmoss.com/app/export/card-transactions/#{uuid}")
    end

    it "derives an invoice's and a reimbursement's pages from their own uuid" do
      invoice = MossInvoice.new(moss_transaction_uuid: uuid, moss_invoice_uuid: kind_uuid)
      expect(invoice.moss_record_url).to eq("https://getmoss.com/app/invoices/all/#{kind_uuid}")
      expect(invoice.moss_export_url).to eq("https://getmoss.com/app/export/invoices/#{kind_uuid}")

      payout = MossReimbursement.new(moss_transaction_uuid: uuid, moss_reimbursement_uuid: kind_uuid)
      expect(payout.moss_record_url).to eq("https://getmoss.com/app/reimbursements/all/#{kind_uuid}")
      expect(payout.moss_export_url).to eq("https://getmoss.com/app/export/reimbursements/#{kind_uuid}")
    end

    it "falls back to the base URLs when the kind's own uuid is missing" do
      invoice = MossInvoice.new(moss_transaction_uuid: uuid)
      expect(invoice.moss_record_url).to eq("https://getmoss.com/app/transactions/all/#{uuid}")
      expect(invoice.moss_export_url).to eq("https://getmoss.com/app/export/balance-movements/#{uuid}")
    end

    it "gives a top-up no URL at all" do
      tx = MossTopUp.new(moss_transaction_uuid: uuid)
      expect(tx.moss_record_url).to be_nil
      expect(tx.moss_export_url).to be_nil
    end
  end

  # The uuid ARRAY holding every Moss id a row stands for. All uuids below are
  # invented.
  describe "#all_moss_transaction_uuids" do
    let(:uuids) { ["aaaaaaaa-1111-2222-3333-444444444444", "bbbbbbbb-5555-6666-7777-888888888888"] }

    def top_up(**attrs)
      MossTopUp.new(moss_transaction_uuid: "cccccccc-9999-0000-1111-222222222222",
        signed_total_base_amount: 500, currency: "EUR",
        payment_date: Date.new(2026, 5, 3), **attrs)
    end

    it "defaults to an empty array" do
      expect(MossTopUp.new.all_moss_transaction_uuids).to eq([])
      expect(MossCardTransaction.new.all_moss_transaction_uuids).to eq([])
    end

    it "round-trips a list of uuids as strings" do
      tx = top_up(all_moss_transaction_uuids: uuids)
      tx.save!
      expect(tx.reload.all_moss_transaction_uuids).to eq(uuids)
    end

    it "round-trips back to an empty array" do
      tx = top_up(all_moss_transaction_uuids: uuids)
      tx.save!
      tx.update!(all_moss_transaction_uuids: [])
      expect(tx.reload.all_moss_transaction_uuids).to eq([])
    end

    it "finds a row by any of its uuids" do
      tx = top_up(all_moss_transaction_uuids: uuids)
      tx.save!
      expect(MossTransaction.where("? = ANY(all_moss_transaction_uuids)", uuids.last).pluck(:id))
        .to eq([tx.id])
    end

    it "is backed by a GIN index for those lookups" do
      expect(ActiveRecord::Base.connection.index_exists?(:moss_transactions,
        :all_moss_transaction_uuids, name: "index_moss_transactions_all_uuids")).to be(true)
    end
  end

  # The generated identity of a row: the id of the Moss object it stands for --
  # the reimbursement's or the invoice's where the kind has one, else the first
  # seen Transaction ID. All uuids below are invented.
  describe "#moss_object_uuid" do
    let(:transaction_uuid) { "dddddddd-1111-2222-3333-444444444444" }
    let(:kind_uuid) { "eeeeeeee-5555-6666-7777-888888888888" }

    def transaction(klass, **attrs)
      klass.create!(signed_total_base_amount: 500, currency: "EUR",
        payment_date: Date.new(2026, 5, 3), **attrs)
    end

    it "is a reimbursement's own uuid" do
      row = transaction(MossReimbursement, moss_transaction_uuid: transaction_uuid,
        moss_reimbursement_uuid: kind_uuid)
      expect(row.reload.moss_object_uuid).to eq(kind_uuid)
    end

    it "is an invoice's own uuid" do
      row = transaction(MossInvoice, moss_transaction_uuid: transaction_uuid,
        moss_invoice_uuid: kind_uuid)
      expect(row.reload.moss_object_uuid).to eq(kind_uuid)
    end

    it "is the transaction uuid of a top-up and of a card payment" do
      top_up = transaction(MossTopUp, moss_transaction_uuid: transaction_uuid)
      card = transaction(MossCardTransaction, moss_transaction_uuid: kind_uuid)
      expect(top_up.reload.moss_object_uuid).to eq(transaction_uuid)
      expect(card.reload.moss_object_uuid).to eq(kind_uuid)
    end

    # A reimbursement's uuid and another row's Transaction ID name the same Moss
    # object; only the unique index over the generated column catches that.
    it "is unique across the kinds" do
      transaction(MossReimbursement, moss_transaction_uuid: transaction_uuid,
        moss_reimbursement_uuid: kind_uuid)
      expect { transaction(MossTopUp, moss_transaction_uuid: kind_uuid) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
