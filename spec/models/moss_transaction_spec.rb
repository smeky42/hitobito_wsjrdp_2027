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
end
