# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Fin::CamtTransactionsFilterSchema do
  let(:bank) do
    WsjrdpFinAccount.create!(short_name: "Vereinskonto", account_identification: "BANK-TEST",
      opening_balance_cents: 0, opening_balance_currency: "EUR", opening_balance_date: Date.new(2026, 1, 1))
  end

  def camt(description, amount:, **attrs)
    WsjrdpCamtTransaction.create!(fin_account: bank, camt_type: "CAMT053",
      account_identification: bank.account_identification, account_servicer_reference: SecureRandom.hex(4),
      credit_debit_indication: amount.negative? ? "DBIT" : "CRDT", signed_base_amount: amount,
      base_currency: "EUR", value_date: Date.new(2026, 4, 2), description: description, **attrs)
  end

  let!(:payment) { camt("Beispielbuchung", amount: -12.34, cdtr_name: "Muster GmbH") }
  let!(:returned) do
    camt("Retoure", amount: -3, return_reason: "MS03", bank_transaction_code: "PMNT+IDDT+UPDD",
      dbtr_name: "Erika Beispiel", comment: "nachfragen")
  end

  def found(tree)
    Wsjrdp::Filtering::Compiler.new(described_class.bound)
      .apply(Wsjrdp::Filtering::Query.parse(tree)).where(fin_account_id: bank.id).to_a
  end

  it "searches all texts, the comment and the other side included" do
    expect(found([[["text", "contains", "nachfragen"]]])).to eq [returned]
    expect(found([[["text", "contains", "Muster GmbH"]]])).to eq [payment]
  end

  it "searches the other side of a payment by itself" do
    expect(found([[["party", "contains", "Muster"]]])).to eq [payment]
  end

  it "tells a return by its kind and its state" do
    expect(found([[["kind", "in", Fin::AccountKinds::BANK_RETURN]]])).to eq [returned]
    expect(found([[["return_state", "in", "in_review"]]])).to eq [returned]
  end
end
