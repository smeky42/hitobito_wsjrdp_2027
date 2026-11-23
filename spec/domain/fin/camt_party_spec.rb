# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The other side of a bank transaction (Fin::CamtParty).
describe Fin::CamtParty do
  def account(name, iban)
    WsjrdpFinAccount.create!(short_name: name, account_identification: iban, iban: iban,
      opening_balance_cents: 0, opening_balance_currency: "EUR", opening_balance_date: Date.new(2026, 1, 1))
  end

  let(:giro) { account("Giro", "DE89370400440532013000") }
  let(:savings) { account("Savings", "DE02120300000000202051") }

  def tx(amount, code: nil, on: giro, **attrs)
    @ref = @ref.to_i + 1
    WsjrdpCamtTransaction.create!(fin_account: on, camt_type: "CAMT053", account_identification: on.iban,
      account_servicer_reference: "P#{@ref}", credit_debit_indication: amount.negative? ? "DBIT" : "CRDT",
      signed_base_amount: amount, base_currency: "EUR", value_date: Date.new(2026, 3, 1), description: "Payment",
      bank_transaction_code: code, **attrs)
  end

  def party(row)
    found = WsjrdpCamtTransaction.select(Fin::CamtTransactionsColumns::SELECT_SQL).find(row.id)
    [found.party, found.party_kind]
  end

  it "takes the side by the sign without a known family" do
    expect(party(tx(10, dbtr_name: "Sender", cdtr_name: "Us"))).to eq(["Sender", "name"])
    expect(party(tx(-10, dbtr_name: "Us", cdtr_name: "Payee"))).to eq(["Payee", "name"])
  end

  it "keeps the payment's roles on a return" do
    expect(party(tx(-10, code: "PMNT+IDDT+UPDD", dbtr_name: "Payer", cdtr_name: "Us"))).to eq(["Payer", "name"])
    expect(party(tx(10, code: "PMNT+ICDT+RRTN", dbtr_name: "Us", cdtr_name: "Payee"))).to eq(["Payee", "name"])
  end

  it "labels rows without a party" do
    expect(party(tx(-10, code: "PMNT+ICDT+ESCT", dbtr_name: "Us"))).to eq(["Sammelüberweisung", "label"])
    expect(party(tx(10, code: "PMNT+IDDT+ESDD", cdtr_name: "Us"))).to eq(["Sammellastschrift", "label"])
    expect(party(tx(-1, code: "ACMT+OPCL+ACCC", dbtr_name: "Us"))).to eq(["Bank", "label"])
  end

  it "names an own account by the other side's IBAN" do
    row = tx(-10, code: "PMNT+ICDT+ESCT", cdtr_name: "Us", cdtr_iban: savings.iban)
    expect(party(row)).to eq(["Savings", "account"])
  end

  it "names the other account of an internal transfer" do
    transfer = WsjrdpInternalTransfer.create!(link_meta: {"source" => "manual"})
    out = tx(-5, code: "ACMT+OPCL+ACCC", on: savings, dbtr_name: "Us", internal_transfer_id: transfer.id)
    into = tx(5, code: "ACMT+OPCL+ACCC", on: giro, dbtr_name: "Us", cdtr_name: "Us", internal_transfer_id: transfer.id)
    expect(party(out)).to eq(["Giro", "account"])
    expect(party(into)).to eq(["Savings", "account"])
  end
end
