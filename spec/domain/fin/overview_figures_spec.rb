# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The key figures of the Finanzen entry page (Fin::OverviewFigures): every
# method against a handful of rows built here, one per area, plus the two
# maxima that carry a card's "Stand" date. All names, numbers, dates and
# account numbers below are invented.
describe Fin::OverviewFigures do
  subject(:figures) { described_class.new }

  # Row counts as the database ARRIVES: every figure counts a whole table, and
  # a test database may already hold rows of its own, so every count is
  # asserted RELATIVE to this baseline.
  let!(:before_counts) do
    [WsjrdpFinAccount, WsjrdpCamtTransaction, AccountingEntry,
      MossTransaction, MossBooking, DatevBooking, DatevBookingBatch,
      WsjrdpCostCenter, WsjrdpPersonalAccount].to_h { |model| [model, model.count] }
  end

  # What the table holds after this spec added `added` rows to it.
  def total(model, added) = before_counts.fetch(model) + added

  # --- Konten & Wallets: two accounts, two bank transactions ---

  let!(:wallet) do
    WsjrdpFinAccount.create!(short_name: "Moss-Wallet", account_identification: "WALLET-FIG",
      transaction_type: "MossBalanceMovement", opening_balance_cents: 0,
      opening_balance_currency: "EUR", opening_balance_date: Date.new(2026, 1, 1))
  end

  let!(:bank) do
    WsjrdpFinAccount.create!(short_name: "Vereinskonto", account_identification: "BANK-FIG",
      opening_balance_cents: 0, opening_balance_currency: "EUR",
      opening_balance_date: Date.new(2026, 1, 1))
  end

  def camt_transaction(reference, value_date, amount)
    WsjrdpCamtTransaction.create!(fin_account: bank, camt_type: "CAMT053",
      account_identification: bank.account_identification, account_servicer_reference: reference,
      credit_debit_indication: amount.negative? ? "DBIT" : "CRDT",
      signed_base_amount: amount, base_currency: "EUR", value_date: value_date,
      description: "Beispielbuchung #{reference}")
  end

  # The later Valuta is the one the card shows, whichever row was inserted first.
  let!(:camt_late) { camt_transaction("REF-1", Date.new(2026, 5, 20), 100) }
  let!(:camt_early) { camt_transaction("REF-2", Date.new(2026, 4, 2), -25) }

  # --- Buchhaltung: one batch with one booking, a cost center, a creditor ---

  let!(:datev_batch) do
    DatevBookingBatch.create!(consultant_number: "1", client_number: "2",
      label: "Beispielstapel", period_from: Date.new(2026, 1, 1),
      period_to: Date.new(2026, 1, 31), financial_year_start: Date.new(2026, 1, 1),
      import_export: "import")
  end

  let!(:datev_booking) do
    DatevBooking.create!(batch: datev_batch, buchungs_guid: SecureRandom.uuid,
      account_number: "18000", account_kind: "BANK",
      offsetting_account_number: "66500", offsetting_account_kind: "EXPENSE",
      base_amount: 10, transaction_amount: 10, debit_credit: "D",
      base_currency: "EUR", booking_date: Date.new(2026, 1, 15))
  end

  let!(:cost_center) { WsjrdpCostCenter.create!(number: "3100", short_name: "Vortreffen") }

  let!(:personal_account) do
    WsjrdpPersonalAccount.create!(number: "700111", account_kind: "CREDITOR",
      short_name: "Musterlieferant")
  end

  # --- Beiträge: two contribution bookings, one of them reconciled ---

  let(:person) { Fabricate(:person) }

  def accounting_entry(value_date, **attrs)
    AccountingEntry.create!(subject: person, author: person, amount_eur: 50,
      description: "Beitragsrate", value_date: value_date, booking_date: value_date, **attrs)
  end

  let!(:entry_linked) { accounting_entry(Date.new(2026, 2, 1), datev_booking: datev_booking) }
  let!(:entry_unlinked) { accounting_entry(Date.new(2026, 3, 1)) }

  # --- Moss: one top-up with its (shell) expense and one booking ---

  let!(:moss_transaction) do
    uuid = SecureRandom.uuid
    transaction = MossTransaction.create!(type: "MossTopUp", moss_transaction_uuid: uuid,
      fin_account: wallet, signed_total_base_amount: 500, currency: "EUR",
      payment_date: Date.new(2026, 3, 4), booking_date: Date.new(2026, 3, 6))
    expense = MossExpense.create!(moss_transaction: transaction, moss_expense_uuid: uuid,
      type: "MossTopUpExpense", expense_number: 1, signed_expense_base_amount: 500)
    MossBooking.create!(moss_transaction: transaction, moss_expense: expense,
      sub_row_number: 1, signed_base_amount: 500)
    transaction
  end

  it "counts the accounts and dates the bank statements" do
    expect(figures.accounts_count).to eq total(WsjrdpFinAccount, 2)
    expect(figures.camt_transactions_count).to eq total(WsjrdpCamtTransaction, 2)
    expect(figures.camt_last_value_date).to eq Date.new(2026, 5, 20)
  end

  it "counts the contribution bookings and the unreconciled ones" do
    expect(figures.accounting_entries_count).to eq total(AccountingEntry, 2)
    expect(figures.accounting_entries_unlinked_count).to eq total(AccountingEntry, 1)
  end

  # The Abstimmung card has no figures of its own: it shows these two again.
  it "reports the unreconciled entry and the unreconciled Moss booking for Abstimmung" do
    expect(figures.accounting_entries_unlinked_count).to eq total(AccountingEntry, 1)
    expect(figures.moss_expense_unlinked_count).to eq 1
  end

  it "takes every Moss figure from Fin::MossOverview" do
    overview = Fin::MossOverview.new
    expect(figures.moss_transactions_count).to eq overview.total_count
    expect(figures.moss_bookings_count).to eq overview.bookings_count
    expect(figures.moss_last_booking_date).to eq overview.last_booking_date
    expect(figures.moss_clearing_unlinked_count).to eq overview.clearing_unlinked_count
    expect(figures.moss_expense_unlinked_count).to eq overview.expense_unlinked_count

    expect(figures.moss_transactions_count).to eq total(MossTransaction, 1)
    expect(figures.moss_bookings_count).to eq total(MossBooking, 1)
    expect(figures.moss_last_booking_date).to eq Date.new(2026, 3, 6)
    expect(figures.moss_clearing_unlinked_count).to eq 1
  end

  it "counts the bookkeeping tables and dates the last booking" do
    expect(figures.datev_bookings_count).to eq total(DatevBooking, 1)
    expect(figures.datev_batches_count).to eq total(DatevBookingBatch, 1)
    expect(figures.datev_last_booking_date).to eq Date.new(2026, 1, 15)
    expect(figures.cost_centers_count).to eq total(WsjrdpCostCenter, 1)
    expect(figures.personal_accounts_count).to eq total(WsjrdpPersonalAccount, 1)
  end

  # A card's "Stand" line has to survive a table nobody has imported into yet.
  it "reports no date for a table without rows" do
    WsjrdpCamtTransaction.delete_all
    DatevBooking.delete_all

    expect(figures.camt_last_value_date).to be_nil
    expect(figures.datev_last_booking_date).to be_nil
  end

  it "asks the database once per figure, however often the page reads it" do
    expect(WsjrdpFinAccount).to receive(:count).once.and_call_original
    2.times { figures.accounts_count }

    expect(figures.moss).to be_a(Fin::MossOverview).and equal(figures.moss)
  end

  # The public surface, spelled out: Abstimmung reuses two of the counts and
  # Controlling has no figures at all, so neither adds a method here.
  it "exposes exactly the figures the entry page needs" do
    expect(described_class.public_instance_methods(false).sort).to eq(%i[
      accounts_count camt_transactions_count camt_last_value_date
      accounting_entries_count accounting_entries_unlinked_count
      moss moss_transactions_count moss_bookings_count moss_last_booking_date
      moss_clearing_unlinked_count moss_expense_unlinked_count
      datev_bookings_count datev_batches_count datev_last_booking_date
      cost_centers_count personal_accounts_count
    ].sort)
  end
end
