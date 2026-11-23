# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The union of bank and Moss transactions (Fin::AccountTransaction).
describe Fin::AccountTransaction do
  let(:account) do
    WsjrdpFinAccount.create!(short_name: "Konto", account_identification: "UNION-TEST",
      opening_balance_cents: 0, opening_balance_currency: "EUR", opening_balance_date: Date.new(2026, 1, 1))
  end

  let!(:camt) do
    WsjrdpCamtTransaction.create!(fin_account: account, camt_type: "CAMT053", account_identification: "UNION-TEST",
      account_servicer_reference: "R1", credit_debit_indication: "CRDT", signed_base_amount: 10,
      base_currency: "EUR", value_date: Date.new(2026, 3, 1), booking_date: Date.new(2026, 3, 2),
      description: "Eingang", dbtr_name: "Absender")
  end

  let!(:moss) do
    MossTransaction.create!(type: "MossTopUp", moss_transaction_uuid: SecureRandom.uuid, fin_account: account,
      signed_total_base_amount: 5, currency: "EUR", booking_date: Date.new(2026, 4, 1), top_up_sender: "Bank X")
  end

  let(:rows) { described_class.all.where(fin_account_id: account.id) }

  it "has one row per bank and per Moss transaction, with its source and key" do
    expect(rows.order(:booking_date).map { |r| [r.source, r.row_key, r.kind, r.party] }).to eq([
      ["camt", "camt-#{camt.id}", "bank", "Absender"],
      ["moss", "moss-#{moss.id}", "transfer", "Bank X"]
    ])
  end

  it "sums, counts and pages in SQL" do
    expect(rows.sum(:signed_base_amount)).to eq(15)
    expect(rows.count).to eq(2)
    expect(rows.order(booking_date: :desc).page(1).per(1).map(&:row_key)).to eq(["moss-#{moss.id}"])
  end

  it "is read-only" do
    expect(rows.first).to be_readonly
  end
end
