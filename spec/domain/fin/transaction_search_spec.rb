# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Fin::TransactionSearch do
  let!(:giro) { it_account("Giro", iban: InternalTransferSpecHelpers::GIRO_IBAN) }
  let!(:savings) { it_account("Tagesgeld", iban: InternalTransferSpecHelpers::SAVINGS_IBAN) }
  let!(:wallet) { it_account("Wallet", wallet: true) }
  let(:day) { Date.new(2026, 3, 5) }

  let!(:out) { it_camt(giro, -677.48, day, cdtr_name: "Musterverein") }
  let!(:into) { it_camt(savings, 677.48, day + 1) }
  let!(:other) { it_camt(savings, 12, day - 20, description: "Zinsgutschrift") }
  let!(:top_up) { it_top_up(wallet, 300, day) }

  def found(**options) = described_class.new(**options).legs.map(&:record)

  it "finds bank and Moss transactions, nearest to the anchor first" do
    expect(found(anchor: day)).to eq([out, top_up, into, other])
  end

  it "narrows by sign, source and account" do
    expect(found(sign: "out")).to eq([out])
    expect(found(sign: "in", sources: %w[moss])).to eq([top_up])
    expect(found(accounts: [savings.id])).to contain_exactly(into, other)
  end

  it "narrows by date range" do
    expect(found(from: day, to: day + 1)).to contain_exactly(out, into, top_up)
  end

  it "reads an amount as whole euros, as an exact amount or as a range, on the magnitude" do
    expect(found(amount: "677")).to contain_exactly(out, into)
    expect(found(amount: "677,48")).to contain_exactly(out, into)
    expect(found(amount: "677,4")).to be_empty
    expect(found(amount: "10-400")).to contain_exactly(other, top_up)
    expect(described_class.new(amount: "viel")).to be_invalid_amount
  end

  it "finds the rows of exactly a signed target amount" do
    expect(found(target: "677.48")).to eq([into])
  end

  it "matches every word in the text or the counterparty" do
    expect(found(text: "muster")).to eq([out])
    expect(found(text: "zins gutschrift")).to eq([other])
    expect(found(text: "zins muster")).to be_empty
  end

  it "leaves out legs of a transfer unless asked, and the excluded keys" do
    WsjrdpInternalTransfer.link!([out])

    expect(found).not_to include(out)
    expect(found(linked: true)).to include(out)
    expect(found(exclude: [into.internal_transfer_leg_key])).not_to include(into)
  end

  it "counts all matches, beyond the rows it shows" do
    stub_const("#{described_class}::LIMIT", 2)
    search = described_class.new(anchor: day)

    expect(search.legs.size).to eq(2)
    expect(search.total_count).to eq(4)
  end
end
