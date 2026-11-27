# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Wsjrdp::Sync::MossApi::BankAccounts do
  include SyncSpecHelpers

  let(:admin) { people(:cmt_leader) }
  let(:key) { described_class.key }
  let(:uuid) { "b0000000-0000-4000-8000-000000000001" }

  before { WsjrdpFinAccount.moss_wallets.delete_all }

  def wallet(name, currency: "EUR", **attrs)
    WsjrdpFinAccount.create!(short_name: name, account_identification: "MOSS-#{name}", opening_balance_cents: 0,
      opening_balance_currency: currency, opening_balance_date: Date.new(2026, 1, 1),
      transaction_type: WsjrdpFinAccount::MOSS_WALLET_TYPE, **attrs)
  end

  def start(now = "2026-11-27 10:00:00 UTC", keys: [key])
    Wsjrdp::Sync::Start.new(source: :moss_api, selection: keys, client: client, actor: admin,
      now: Time.zone.parse(now)).call
  end

  def apply(run) = Wsjrdp::Sync::Apply.new(run.reload, actor: admin, confirmed: true, warnings_confirmed: true).call

  def plan(run) = run.parts.reload.find_by!(part_key: key).plan_object

  def part(run) = run.parts.reload.find_by!(part_key: key)

  it "links the one wallet without a UUID and keeps the Moss fields and balance" do
    account = wallet("Moss Wallet")

    apply(start)

    expect(account.reload).to have_attributes(moss_bank_account_uuid: uuid, moss_funding_type: "DEBIT",
      moss_account_status: "ACTIVE", moss_currency: "EUR", moss_balance: BigDecimal("1234.56"),
      moss_available_balance: BigDecimal("1200.5"), moss_balance_first_seen_at: Time.zone.parse("2026-11-27 10:00:00 UTC"))
  end

  it "keeps the balance's time while the amounts stay, so a second run changes nothing" do
    account = wallet("Moss Wallet")
    apply(start)

    expect(start("2026-11-28 10:00:00 UTC").status).to eq("unchanged")
    expect(account.reload.moss_balance_first_seen_at).to eq(Time.zone.parse("2026-11-27 10:00:00 UTC"))

    lists["bank-accounts/#{uuid}/balance"]["availableBalance"]["amount"] = "1100"
    apply(start("2026-11-29 10:00:00 UTC"))

    expect(account.reload.moss_balance_first_seen_at).to eq(Time.zone.parse("2026-11-29 10:00:00 UTC"))
  end

  it "reads no balance of a closed wallet and keeps the last one" do
    account = wallet("Moss Wallet", moss_bank_account_uuid: uuid, moss_balance: 5, status: "closed")
    lists["bank-accounts"].sole["accountStatus"] = "CLOSED"
    lists.delete("bank-accounts/#{uuid}/balance")

    apply(start)

    expect(account.reload).to have_attributes(moss_account_status: "CLOSED", moss_balance: 5)
  end

  it "fails only its part when the wallet fits not just one account, the others are written" do
    wallet("Moss Wallet")
    wallet("Zweite Wallet")
    run = start(keys: [key, Wsjrdp::Sync::MossApi::TaxRates.key])

    expect(run.status).to eq("planned")
    expect(part(run)).to have_attributes(status: "failed",
      error_message: include(uuid, "Moss Wallet", "Zweite Wallet"))

    apply(run)

    expect(run.reload.status).to eq("partly_applied")
    expect(MossTaxRate.count).to eq(1)
    expect(WsjrdpFinAccount.where.not(moss_bank_account_uuid: nil)).to be_empty
  end

  it "fails with several new wallets for one account" do
    wallet("Moss Wallet")
    lists["bank-accounts"] << lists["bank-accounts"].sole.merge("id" => "b0000000-0000-4000-8000-000000000002")
    lists["bank-accounts/b0000000-0000-4000-8000-000000000002/balance"] = lists["bank-accounts/#{uuid}/balance"]

    expect(part(start).status).to eq("failed")
  end

  it "leaves a deleted account alone and fails while it holds the wallet's UUID" do
    account = wallet("Alte Wallet", moss_bank_account_uuid: uuid, deleted_at: Time.zone.now)
    wallet("Moss Wallet")

    expect(part(start).error_message).to include(uuid, "Alte Wallet")
    expect(account.reload.moss_funding_type).to be_nil
  end

  it "fails when the balance comes in another currency" do
    wallet("Moss Wallet")
    lists["bank-accounts/#{uuid}/balance"]["balance"]["currency"] = "USD"

    expect(part(start).error_message).to include("USD")
  end

  it "takes no wallet account of another currency" do
    account = wallet("Moss Wallet", currency: "USD")

    expect(part(start).status).to eq("failed")
    expect(account.reload.moss_bank_account_uuid).to be_nil
  end

  it "marks an account Moss no longer returns, and warns when that is every account" do
    account = wallet("Moss Wallet", moss_bank_account_uuid: uuid)
    lists["bank-accounts"] = []
    run = start

    expect(plan(run).warnings.map(&:code)).to eq(["many_removed"])

    apply(run)

    expect(account.reload.moss_removed_at).to be_present
  end

  it "restores an account when Moss returns its wallet again" do
    account = wallet("Moss Wallet", moss_bank_account_uuid: uuid, moss_removed_at: Time.zone.now)
    run = start

    expect(plan(run).changes.map(&:action)).to eq(["restore"])

    apply(run)

    expect(account.reload.moss_removed_at).to be_nil
  end

  it "keeps Hitobito's status and says when Moss's differs" do
    account = wallet("Moss Wallet", moss_bank_account_uuid: uuid, status: "closed")

    run = start
    apply(run)

    expect(plan(run).warnings.sole).to have_attributes(level: "important", code: "status_differs")
    expect(account.reload).to have_attributes(status: "closed", moss_account_status: "ACTIVE")
  end
end
