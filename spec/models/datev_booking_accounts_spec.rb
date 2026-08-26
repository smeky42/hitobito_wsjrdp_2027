# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The polymorphic account / offsetting_account associations
# (doc/bookkeeping_schema_review.md §4): *_ref_type is STORED GENERATED from
# the DATEV Kontenart, targets are matched on their unique `number`.
describe DatevBooking do
  def booking(attrs = {})
    defaults = {buchungs_guid: SecureRandom.uuid,
                absolute_base_amount: 10, absolute_transaction_amount: 10,
                debit_credit: "D",
                account_number: "18000", offsetting_account_number: "66500",
                account_type: "BANK", offsetting_account_type: "EXPENSE"}
    described_class.create!(defaults.merge(attrs))
  end

  let!(:bank) { WsjrdpLedgerAccount.create!(number: "18000", name: "PAX", account_type: "BANK") }
  let!(:expense) { WsjrdpLedgerAccount.create!(number: "66500", name: "Reise", account_type: "EXPENSE") }
  let!(:supplier) { WsjrdpPersonalAccount.create!(number: "700019", name: "Förderkreis") }

  it "derives the ref types from the Kontenart" do
    b = booking(offsetting_account_number: "700019", offsetting_account_type: "CREDITOR")
    expect(b.reload.account_ref_type).to eq("WsjrdpLedgerAccount")
    expect(b.offsetting_account_ref_type).to eq("WsjrdpPersonalAccount")
  end

  it "navigates to the ledger account and the supplier" do
    b = booking(offsetting_account_number: "700019", offsetting_account_type: "CREDITOR").reload
    expect(b.account).to eq(bank)
    expect(b.offsetting_account).to eq(supplier)
  end

  it "keeps account_type as the Kontenart, not as the association type" do
    expect(booking.reload.account_type).to eq("BANK")
  end

  it "builds where(offsetting_account: record) on ref_type + number" do
    hit = booking(offsetting_account_number: "700019", offsetting_account_type: "CREDITOR")
    booking # non-matching
    sql = described_class.where(offsetting_account: supplier).to_sql
    expect(sql).to include(%("offsetting_account_ref_type" = 'WsjrdpPersonalAccount'))
    expect(sql).to include(%("offsetting_account_number" = '700019'))
    expect(described_class.where(offsetting_account: supplier).pluck(:id)).to eq([hit.id])
  end

  it "preloads mixed targets without N+1" do
    booking
    booking(offsetting_account_number: "700019", offsetting_account_type: "CREDITOR")
    loaded = described_class.includes(:account, :offsetting_account).order(:id).to_a
    expect(loaded.map { |b| b.offsetting_account.class }.uniq)
      .to match_array([WsjrdpLedgerAccount, WsjrdpPersonalAccount])
    queries = 0
    callback = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      loaded.each { |b| [b.account, b.offsetting_account] }
    end
    expect(queries).to eq(0)
  end

  it "returns nil (not an error) for numbers missing from the reference tables" do
    b = booking(account_number: "99999", account_type: "UNKNOWN").reload
    expect(b.account).to be_nil
  end

  it "raises EagerLoadPolymorphicError for joins, by design" do
    expect { described_class.joins(:account).to_a }
      .to raise_error(ActiveRecord::EagerLoadPolymorphicError)
  end
end
