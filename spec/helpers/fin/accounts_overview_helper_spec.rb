# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The monthly chart of /fin/acc: the legs of an Umbuchung stay out of Ein and
# Aus, but still move the balance line.
describe Fin::AccountsOverviewHelper do
  let(:giro) { it_account("Giro", iban: InternalTransferSpecHelpers::GIRO_IBAN) }
  let(:wallet) { it_account("Wallet", top_up_iban: InternalTransferSpecHelpers::WALLET_TOP_UP_IBAN, wallet: true) }
  let(:rows) { [[giro, 0], [wallet, 0]] }

  def series(name) = helper.fin_monthly_movements(rows).find { |entry| entry[:name] == name }[:data]

  before do
    it_camt(giro, 1000, Date.new(2026, 3, 1), dbtr_iban: "DE66100100102222222222")
    out = it_camt(giro, -300, Date.new(2026, 3, 5), cdtr_iban: InternalTransferSpecHelpers::WALLET_TOP_UP_IBAN)
    top_up = it_top_up(wallet, 300, Date.new(2026, 3, 5))
    MossBooking.create!(moss_transaction: top_up, moss_expense: MossExpense.create!(moss_transaction: top_up,
      moss_expense_uuid: SecureRandom.uuid, type: "MossTopUpExpense", expense_number: 1,
      signed_expense_base_amount: 300), sub_row_number: 1, signed_base_amount: 300)
    WsjrdpInternalTransfer.link!([out, top_up])
  end

  it "leaves the legs of a transfer out of Ein and Aus" do
    expect(series("Ein")["2026-03"]).to eq(1000.0)
    expect(series("Aus")["2026-03"]).to eq(0.0)
  end

  it "still ends the balance line at the total balance" do
    expect(series("Kontostand").values.last).to eq(1000.0)
  end

  it "keeps the legs of an open transfer out as well" do
    open_out = it_camt(giro, -50, Date.new(2026, 3, 9), cdtr_iban: InternalTransferSpecHelpers::WALLET_TOP_UP_IBAN)
    WsjrdpInternalTransfer.link!([open_out])

    expect(series("Aus")["2026-03"]).to eq(0.0)
    expect(series("Kontostand").values.last).to eq(950.0)
  end
end
