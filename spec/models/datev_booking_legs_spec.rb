# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Regression tests for the general-ledger "legs" scope and the generated
# offsetting_amount column (see doc/bookkeeping.md). The three bookings below are
# exactly the shapes that broke the old SUM(amount) grouping: a creditor invoice
# and its payment (which must net to zero) and a fee booked onto an income
# account via its Gegenkonto (which must show the full income).
describe DatevBooking do
  def booking(absolute_amount, attrs)
    DatevBooking.create!({buchungs_guid: SecureRandom.uuid,
                          absolute_base_amount: absolute_amount,
                          absolute_transaction_amount: absolute_amount}.merge(attrs))
  end

  # expense (Soll -> D) -> creditor (Haben): we owe 660 (amount: -660)
  let!(:invoice) do
    booking(660, account_number: "66600", account_type: "EXPENSE",
      offsetting_account_number: "700017", offsetting_account_type: "CREDITOR",
      debit_credit: "D")
  end
  # clearing (Haben -> C) -> creditor (Soll): settles the 660 (amount: -660)
  let!(:payment) do
    booking(660, account_number: "36100", account_type: "CLEARING",
      offsetting_account_number: "700017", offsetting_account_type: "CREDITOR",
      debit_credit: "C")
  end
  # bank (Soll -> D) -> income (Haben): +660 income (income sits on the Gegenkonto)
  let!(:fee) do
    booking(660, account_number: "18000", account_type: "BANK",
      offsetting_account_number: "41030", offsetting_account_type: "INCOME",
      debit_credit: "D")
  end

  def balance(account)
    DatevBooking.legs.where(leg_account: account).sum(:leg_amount)
  end

  describe "generated amount" do
    it "is the booking value from the Konto's perspective" do
      expect(invoice.reload.amount).to eq(-660) # expense: money out
      expect(payment.reload.amount).to eq(-660) # clearing: money out
      expect(fee.reload.amount).to eq(660)      # bank: money in
    end
  end

  describe "generated offsetting_amount" do
    it "is the booking value from the Gegenkonto's perspective" do
      expect(invoice.reload.offsetting_amount).to eq(-660) # creditor: we owe
      expect(payment.reload.offsetting_amount).to eq(660)  # creditor: settled
      expect(fee.reload.offsetting_amount).to eq(660)      # income: +660
    end
  end

  describe ".legs" do
    it "expands every booking into two account legs" do
      expect(DatevBooking.legs.count).to eq(DatevBooking.count * 2)
    end

    it "nets a fully settled creditor to zero" do
      expect(balance("700017")).to eq(0)
    end

    it "shows an income account's full total even though it sits on the Gegenkonto" do
      expect(balance("41030")).to eq(660)
    end

    it "keeps a bank account (always the Konto) equal to SUM(amount)" do
      expect(balance("18000")).to eq(DatevBooking.where(account_number: "18000").sum(:amount))
    end

    it "keeps the trial balance (account-centric Soll+/Haben-) at exactly zero" do
      account_centric = DatevBooking.legs.sum(
        Arel.sql("leg_amount * (CASE WHEN leg_account_type IN ('INCOME','EXPENSE') THEN -1 ELSE 1 END)")
      )
      expect(account_centric).to eq(0)
    end
  end
end
