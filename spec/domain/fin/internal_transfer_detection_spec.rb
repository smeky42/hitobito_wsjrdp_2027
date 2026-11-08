# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Fin::InternalTransferDetection do
  let!(:giro) { it_account("Giro", iban: InternalTransferSpecHelpers::GIRO_IBAN) }
  let!(:savings) { it_account("Tagesgeld", iban: InternalTransferSpecHelpers::SAVINGS_IBAN) }
  let!(:notice) { it_account("Kündigungsgeld", iban: InternalTransferSpecHelpers::NOTICE_IBAN) }
  let!(:wallet) { it_account("Wallet", top_up_iban: InternalTransferSpecHelpers::WALLET_TOP_UP_IBAN, wallet: true) }
  let(:day) { Date.new(2026, 3, 2) } # a Monday

  subject(:detection) { described_class.new(today: Date.new(2026, 6, 1)) }

  def keys(pairs) = pairs.map { |pair| [pair.from.record, pair.to.record] }

  it "pairs a transfer whose both sides name the other's IBAN" do
    out = it_camt(giro, -1000, day, dbtr_iban: InternalTransferSpecHelpers::GIRO_IBAN, cdtr_iban: InternalTransferSpecHelpers::SAVINGS_IBAN)
    into = it_camt(savings, 1000, day, dbtr_iban: InternalTransferSpecHelpers::GIRO_IBAN, cdtr_iban: InternalTransferSpecHelpers::SAVINGS_IBAN)

    expect(keys(detection.unique)).to eq([[out, into]])
    expect(detection.unique.first.rule).to eq(:both_ibans)
  end

  it "pairs the interest the notice account passes on, where only the arriving side names an IBAN" do
    out = it_camt(notice, -645.83, day, dbtr_iban: InternalTransferSpecHelpers::NOTICE_IBAN)
    into = it_camt(savings, 645.83, day, dbtr_iban: InternalTransferSpecHelpers::NOTICE_IBAN, cdtr_iban: InternalTransferSpecHelpers::SAVINGS_IBAN)

    expect(keys(detection.unique)).to eq([[out, into]])
    expect(detection.unique.first.rule).to eq(:sender_iban)
  end

  it "pairs a Moss top-up through the wallet's top-up IBAN, a day later" do
    out = it_camt(giro, -2500, day, dbtr_iban: InternalTransferSpecHelpers::GIRO_IBAN, cdtr_iban: InternalTransferSpecHelpers::WALLET_TOP_UP_IBAN)
    top_up = it_top_up(wallet, 2500, day + 1)

    expect(keys(detection.unique)).to eq([[out, top_up]])
    expect(detection.unique.first.rule).to eq(:moss_top_up)
    expect(detection.unique.first.gap).to eq(1)
  end

  # Two transfers of the same amount on the same day to two different accounts:
  # each inflow names the same sender, but each outflow names its own receiver.
  it "tells two same-amount transfers apart by the receiver each outflow names" do
    to_savings = it_camt(giro, -500, day, dbtr_iban: InternalTransferSpecHelpers::GIRO_IBAN, cdtr_iban: InternalTransferSpecHelpers::SAVINGS_IBAN)
    to_notice = it_camt(giro, -500, day, dbtr_iban: InternalTransferSpecHelpers::GIRO_IBAN, cdtr_iban: InternalTransferSpecHelpers::NOTICE_IBAN)
    at_savings = it_camt(savings, 500, day, dbtr_iban: InternalTransferSpecHelpers::GIRO_IBAN)
    at_notice = it_camt(notice, 500, day, dbtr_iban: InternalTransferSpecHelpers::GIRO_IBAN)

    expect(keys(detection.unique)).to contain_exactly([to_savings, at_savings], [to_notice, at_notice])
    expect(detection.ambiguous).to be_empty
  end

  it "groups competing candidates instead of guessing" do
    out = it_camt(giro, -2600, day, cdtr_iban: InternalTransferSpecHelpers::WALLET_TOP_UP_IBAN)
    first = it_top_up(wallet, 2600, day)
    second = it_top_up(wallet, 2600, day + 1)

    expect(detection.unique).to be_empty
    expect(detection.ambiguous.size).to eq(1)
    expect(keys(detection.ambiguous.first)).to contain_exactly([out, first], [out, second])
  end

  it "looks 10 calendar days both ways, not 11" do
    out = it_camt(giro, -100, day, cdtr_iban: InternalTransferSpecHelpers::SAVINGS_IBAN)
    it_camt(savings, 100, day + 11, dbtr_iban: InternalTransferSpecHelpers::GIRO_IBAN)
    expect(detection.pairs).to be_empty

    into = it_camt(savings, 100, day + 10, dbtr_iban: InternalTransferSpecHelpers::GIRO_IBAN)
    expect(keys(described_class.new.unique)).to eq([[out, into]])
  end

  it "does not pair a row with a counterparty that is no own account" do
    it_camt(giro, -100, day, cdtr_iban: "DE66100100102222222222")
    it_camt(savings, 100, day, dbtr_iban: "DE66100100102222222222")

    expect(detection.pairs).to be_empty
    expect(detection.missing).to be_empty
  end

  it "does not pair a row whose named IBAN is the wrong account's" do
    it_camt(giro, -100, day, cdtr_iban: InternalTransferSpecHelpers::NOTICE_IBAN)
    it_camt(savings, 100, day, dbtr_iban: InternalTransferSpecHelpers::GIRO_IBAN)

    expect(detection.pairs).to be_empty
  end

  describe "rows that do not take part" do
    let!(:out) { it_camt(giro, -1000, day, cdtr_iban: InternalTransferSpecHelpers::SAVINGS_IBAN) }
    let!(:into) { it_camt(savings, 1000, day, dbtr_iban: InternalTransferSpecHelpers::GIRO_IBAN) }

    it "leaves out a row that is already a leg" do
      WsjrdpInternalTransfer.link!([out])
      expect(detection.pairs).to be_empty
    end

    it "leaves out a row marked as no transfer" do
      into.mark_not_internal_transfer!
      expect(detection.pairs).to be_empty
    end

    it "leaves out a pair one of its rows denies, in either direction" do
      out.deny_internal_transfer_candidate!(into.internal_transfer_leg_key)
      expect(detection.pairs).to be_empty

      out.update_columns(additional_info: {})
      into.deny_internal_transfer_candidate!(out.internal_transfer_leg_key)
      expect(described_class.new.pairs).to be_empty
    end

    it "leaves out a deleted or replaced bank transaction" do
      into.update_columns(deleted_at: Time.current)
      expect(detection.pairs).to be_empty

      replacement = it_camt(savings, 1000, day, dbtr_iban: InternalTransferSpecHelpers::GIRO_IBAN)
      into.update_columns(deleted_at: nil, replaced_by_id: replacement.id)
      expect(keys(described_class.new.unique)).to eq([[out, replacement]])
    end
  end

  describe "#missing" do
    # Thursday before Easter 2026: Good Friday and Easter Monday are no bank
    # days, so the third bank day after it is Thursday, 9 April.
    let(:thursday) { Date.new(2026, 4, 2) }
    let!(:out) { it_camt(giro, -800, thursday, cdtr_iban: InternalTransferSpecHelpers::SAVINGS_IBAN) }

    it "waits for 3 bank days after the row's date" do
      entry = described_class.new(today: Date.new(2026, 4, 9)).missing.first

      expect(entry.leg.record).to eq(out)
      expect(entry.named_account).to eq(savings)
      expect(entry.waiting_until).to eq(Date.new(2026, 4, 9))
      expect(described_class.new(today: Date.new(2026, 4, 9)).waiting.size).to eq(1)
    end

    it "shows the row as without counterpart after that" do
      later = described_class.new(today: Date.new(2026, 4, 10))
      expect(later.without_counterpart.map { |entry| entry.leg.record }).to eq([out])
      expect(later.open_count).to eq(1)
    end

    it "is empty once the counterpart is there" do
      it_camt(savings, 800, thursday + 1, dbtr_iban: InternalTransferSpecHelpers::GIRO_IBAN)
      expect(detection.missing).to be_empty
    end

    it "also names an inflow from another own account without its outflow" do
      into = it_camt(savings, 50, day, dbtr_iban: InternalTransferSpecHelpers::NOTICE_IBAN)
      expect(detection.missing.map { |entry| entry.leg.record }).to include(into)
    end
  end
end
