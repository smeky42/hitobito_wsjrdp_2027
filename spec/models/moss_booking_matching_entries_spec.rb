# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Which Beitragsbuchungen of a person a Moss booking may be linked to, and which
# count as already existing for it when a new one would be created in one step
# (doc/TODOs/TODO_moss_link_and_create_entry.md). All values are invented.
describe MossBooking do
  let(:person) { people(:cmt_leader) }
  let(:payment_date) { Date.new(2026, 6, 1) }

  def booking_with(booking_date:)
    uuid = SecureRandom.uuid
    transaction = MossTransaction.create!(type: "MossReimbursement", moss_transaction_uuid: uuid,
      signed_total_base_amount: -60, currency: "EUR", booking_date: booking_date)
    expense = MossExpense.create!(moss_transaction: transaction, moss_expense_uuid: uuid,
      type: "MossReimbursementExpense", expense_number: 1, signed_expense_base_amount: -60)
    MossBooking.create!(moss_transaction: transaction, moss_expense: expense, sub_row_number: 1,
      signed_base_amount: -60, booking_posting_text: "Erstattung")
  end

  let(:booking) { booking_with(booking_date: payment_date) }

  def entry(amount_cents: -6000, booking_date: payment_date, **links)
    AccountingEntry.create!(subject: person, author: person, amount_cents: amount_cents,
      description: "Beitrag", value_date: booking_date, booking_date: booking_date, **links)
  end

  def other_moss_booking = booking_with(booking_date: payment_date)

  def camt_transaction
    WsjrdpCamtTransaction.create!(camt_type: "CAMT053", account_identification: "DE-TEST",
      account_servicer_reference: SecureRandom.hex(8), credit_debit_indication: "DBIT",
      signed_base_amount: -60, base_currency: "EUR", value_date: payment_date,
      description: "Rückzahlung")
  end

  def datev_booking
    DatevBooking.create!(buchungs_guid: SecureRandom.uuid, booking_date: payment_date,
      base_amount: 60, transaction_amount: 60, debit_credit: "D",
      account_number: "18000", account_kind: "BANK",
      offsetting_account_number: "41030", offsetting_account_kind: "INCOME")
  end

  describe "#unlinked_accounting_entries_with_matching_amount" do
    subject(:matches) { booking.unlinked_accounting_entries_with_matching_amount(person) }

    it "finds an unlinked entry of the same amount, however far away in time" do
      far = entry(booking_date: payment_date - 2.years)
      expect(matches).to contain_exactly(far)
    end

    it "skips entries linked to a Moss booking or a camt transaction" do
      entry(moss_booking: other_moss_booking)
      entry(camt_transaction: camt_transaction)
      expect(matches).to be_empty
    end

    it "keeps an entry linked to a DATEV booking only" do
      datev_linked = entry(datev_booking: datev_booking)
      expect(matches).to contain_exactly(datev_linked)
    end

    it "requires the same amount, sign included" do
      entry(amount_cents: -5999)
      entry(amount_cents: 6000)
      expect(matches).to be_empty
    end

    it "finds nothing without a person" do
      entry
      expect(booking.unlinked_accounting_entries_with_matching_amount(nil)).to be_empty
    end
  end

  describe "#accounting_entries_matching_new_entry" do
    it "counts entries up to 3 months before and after the payment, both ends included" do
      before = entry(booking_date: payment_date - 3.months)
      after = entry(booking_date: payment_date + 3.months)
      expect(booking.accounting_entries_matching_new_entry(person)).to contain_exactly(before, after)
    end

    it "ignores entries further away than 3 months" do
      entry(booking_date: payment_date - 3.months - 1.day)
      entry(booking_date: payment_date + 3.months + 1.day)
      expect(booking.accounting_entries_matching_new_entry(person)).to be_empty
    end

    it "counts every unlinked entry of the amount when the payment has no booking date" do
      undated = booking_with(booking_date: nil)
      far = entry(booking_date: payment_date - 2.years)
      expect(undated.accounting_entries_matching_new_entry(person)).to contain_exactly(far)
    end
  end

  describe "#open_for_new_entry?" do
    it "is true without a person and without a Beitragsbuchung" do
      expect(booking.open_for_new_entry?).to be true
    end

    it "is false once a person is linked" do
      booking.update!(contribution_subject: person)
      expect(booking.open_for_new_entry?).to be false
    end

    it "is false once a Beitragsbuchung is linked" do
      entry(moss_booking: booking)
      expect(booking.reload.open_for_new_entry?).to be false
    end
  end
end
