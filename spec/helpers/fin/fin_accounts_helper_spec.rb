# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Fin::FinAccountsHelper do
  let(:bank) do
    WsjrdpFinAccount.new(short_name: "Vereinskonto", account_identification: "DE19100100103333333333",
      iban: "DE19100100103333333333", servicer_bic: "GENODEF1TEST", status: "active")
  end
  let(:wallet) { WsjrdpFinAccount.new(short_name: "Moss-Wallet", account_identification: "MOSS-WALLET-TEST") }

  def copied(html) = Capybara.string(html.to_s).all("a.fin-copy").pluck("data-copy-to-clipboard")

  it "does not repeat an identification equal to the IBAN" do
    expect(helper.fin_format_wsjrdp_fin_account_account_identification(bank)).to eq(hide: true)
    expect(helper.fin_format_wsjrdp_fin_account_account_identification(wallet)).to eq("MOSS-WALLET-TEST")
  end

  it "copies the IBAN without the spaces of the display, and nothing that is not there" do
    expect(copied(helper.fin_format_wsjrdp_fin_account_iban(bank))).to eq(["DE19100100103333333333"])
    expect(helper.fin_format_wsjrdp_fin_account_servicer_bic(wallet)).to be_nil
  end

  it "identifies an account by its IBAN, a wallet by the IBAN it is funded through, else by its identification" do
    expect(helper.fin_account_summary_identifier(bank)).to include("DE19 1001 0010 3333 3333 33")
    expect(helper.fin_account_summary_identifier(wallet)).to eq("MOSS-WALLET-TEST")

    wallet.top_up_iban = "DE16100100101111111111"
    expect(helper.fin_account_summary_identifier(wallet))
      .to include("DE16 1001 0010 1111 1111 11", WsjrdpFinAccount.human_attribute_name(:top_up_iban))
  end

  it "adds the stored status for the write tier only" do
    allow(helper).to receive(:can?).with(:update, bank).and_return(false)
    expect(helper.fin_format_wsjrdp_fin_account_status(bank)).to eq(bank.status_display)

    allow(helper).to receive(:can?).with(:update, bank).and_return(true)
    expect(helper.fin_format_wsjrdp_fin_account_status(bank)).to include(">active<")
  end

  it "links the bookkeeping account where it exists, else shows its number alone" do
    allow(helper).to receive(:can?).and_return(true)
    WsjrdpLedgerAccount.create!(number: "18100", name: "Skatbank")
    bank.assign_attributes(bookkeeping_account_number: "18100", bookkeeping_account_type: "WsjrdpLedgerAccount")
    expect(helper.fin_format_wsjrdp_fin_account_bookkeeping_account_number(bank))
      .to include("18100 Skatbank", ledger_account_path("18100"))

    bank.bookkeeping_account_number = "99999"
    expect(helper.fin_format_wsjrdp_fin_account_bookkeeping_account_number(bank)).to eq("99999")
  end
end
