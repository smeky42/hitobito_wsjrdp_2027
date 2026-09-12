# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe MossTransaction do
  describe "#description" do
    it "joins the kind's name and the Buchungstext with an en dash" do
      tx = MossReimbursement.new(transaction_name: "Fahrt nach Mainz", transaction_posting_text: "RK Unit A1")
      expect(tx.description).to eq("Fahrt nach Mainz – RK Unit A1")
      expect(MossCardTransaction.new(merchant_name: "Supermarkt", transaction_posting_text: "Verpflegung").description)
        .to eq("Supermarkt – Verpflegung")
      expect(MossTopUp.new(top_up_sender: "Vereinskonto").description).to eq("Einzahlung – Vereinskonto")
    end

    it "falls back to the SEPA reference and never returns nil" do
      expect(MossInvoice.new(payment_reference: "RE 4711").description).to eq("RE 4711")
      expect(MossInvoice.new.description).to eq("")
    end

    it "truncates to the given length" do
      tx = MossReimbursement.new(transaction_name: "A" * 60, transaction_posting_text: "B" * 60)
      expect(tx.description(length: 100).length).to eq(100)
      expect(tx.description(length: 100)).to end_with("…")
      expect(tx.description(length: 200)).to eq(tx.description)
    end
  end

  # THE date of a transaction: the day the movement was booked in the Moss
  # wallet. All dates below are invented.
  describe "#value_date" do
    # A card payment is the one kind that carries both dates, and its payout day
    # is the earlier one -- the row is dated by the booking day all the same.
    it "is the booking date, not the payout day of the export" do
      tx = MossCardTransaction.new(payment_date: Date.new(2026, 5, 3),
        booking_date: Date.new(2026, 5, 6))
      expect(tx.value_date).to eq(Date.new(2026, 5, 6))
    end

    # The kinds whose export carries no payout day at all are dated by the same
    # column as every other row.
    it "dates a payment without a payout day by the same column" do
      tx = MossReimbursement.new(booking_date: Date.new(2026, 6, 15))
      expect(tx.value_date).to eq(Date.new(2026, 6, 15))
      expect(tx.payment_date).to be_nil
    end

    it "is nil while the row carries no booking date" do
      expect(MossInvoice.new(payment_date: Date.new(2026, 7, 1)).value_date).to be_nil
    end

    # A booking has no date of its own; it is dated by its payment.
    it "dates every booking of the payment" do
      tx = MossReimbursement.new(booking_date: Date.new(2026, 6, 15))
      expect(MossBooking.new(moss_transaction: tx).value_date).to eq(Date.new(2026, 6, 15))
      expect(MossBooking.new.value_date).to be_nil
    end
  end

  # Every URL is derived from a stored uuid -- except a top-up's, which Moss
  # addresses by an internal id no export carries. All uuids below are invented.
  describe "#moss_record_url / #moss_export_url" do
    let(:uuid) { "11111111-2222-3333-4444-555555555555" }
    let(:kind_uuid) { "66666666-7777-8888-9999-000000000000" }

    it "derives the card payment's record and export pages from the transaction uuid" do
      tx = MossCardTransaction.new(moss_transaction_uuid: uuid)
      expect(tx.moss_record_url).to eq("https://getmoss.com/app/transactions/all/#{uuid}")
      expect(tx.moss_export_url).to eq("https://getmoss.com/app/export/card-transactions/#{uuid}")
    end

    it "derives an invoice's and a reimbursement's pages from their own uuid" do
      invoice = MossInvoice.new(moss_transaction_uuid: uuid, moss_invoice_uuid: kind_uuid)
      expect(invoice.moss_record_url).to eq("https://getmoss.com/app/invoices/all/#{kind_uuid}")
      expect(invoice.moss_export_url).to eq("https://getmoss.com/app/export/invoices/#{kind_uuid}")

      payout = MossReimbursement.new(moss_transaction_uuid: uuid, moss_reimbursement_uuid: kind_uuid)
      expect(payout.moss_record_url).to eq("https://getmoss.com/app/reimbursements/all/#{kind_uuid}")
      expect(payout.moss_export_url).to eq("https://getmoss.com/app/export/reimbursements/#{kind_uuid}")
    end

    it "falls back to the base URLs when the kind's own uuid is missing" do
      invoice = MossInvoice.new(moss_transaction_uuid: uuid)
      expect(invoice.moss_record_url).to eq("https://getmoss.com/app/transactions/all/#{uuid}")
      expect(invoice.moss_export_url).to eq("https://getmoss.com/app/export/balance-movements/#{uuid}")
    end

    it "gives a top-up no URL at all" do
      tx = MossTopUp.new(moss_transaction_uuid: uuid)
      expect(tx.moss_record_url).to be_nil
      expect(tx.moss_export_url).to be_nil
    end
  end

  # The uuid ARRAY holding every Moss id a row stands for. All uuids below are
  # invented.
  describe "#all_moss_transaction_uuids" do
    let(:uuids) { ["aaaaaaaa-1111-2222-3333-444444444444", "bbbbbbbb-5555-6666-7777-888888888888"] }

    def top_up(**attrs)
      MossTopUp.new(moss_transaction_uuid: "cccccccc-9999-0000-1111-222222222222",
        signed_total_base_amount: 500, currency: "EUR",
        payment_date: Date.new(2026, 5, 3), **attrs)
    end

    it "defaults to an empty array" do
      expect(MossTopUp.new.all_moss_transaction_uuids).to eq([])
      expect(MossCardTransaction.new.all_moss_transaction_uuids).to eq([])
    end

    it "round-trips a list of uuids as strings" do
      tx = top_up(all_moss_transaction_uuids: uuids)
      tx.save!
      expect(tx.reload.all_moss_transaction_uuids).to eq(uuids)
    end

    it "round-trips back to an empty array" do
      tx = top_up(all_moss_transaction_uuids: uuids)
      tx.save!
      tx.update!(all_moss_transaction_uuids: [])
      expect(tx.reload.all_moss_transaction_uuids).to eq([])
    end

    it "finds a row by any of its uuids" do
      tx = top_up(all_moss_transaction_uuids: uuids)
      tx.save!
      expect(MossTransaction.where("? = ANY(all_moss_transaction_uuids)", uuids.last).pluck(:id))
        .to eq([tx.id])
    end

    it "is backed by a GIN index for those lookups" do
      expect(ActiveRecord::Base.connection.index_exists?(:moss_transactions,
        :all_moss_transaction_uuids, name: "index_moss_transactions_all_uuids")).to be(true)
    end
  end

  # The generated identity of a row: the id of the Moss object it stands for --
  # the reimbursement's or the invoice's where the kind has one, else the first
  # seen Transaction ID. All uuids below are invented.
  describe "#moss_object_uuid" do
    let(:transaction_uuid) { "dddddddd-1111-2222-3333-444444444444" }
    let(:kind_uuid) { "eeeeeeee-5555-6666-7777-888888888888" }

    def transaction(klass, **attrs)
      klass.create!(signed_total_base_amount: 500, currency: "EUR",
        payment_date: Date.new(2026, 5, 3), **attrs)
    end

    it "is a reimbursement's own uuid" do
      row = transaction(MossReimbursement, moss_transaction_uuid: transaction_uuid,
        moss_reimbursement_uuid: kind_uuid)
      expect(row.reload.moss_object_uuid).to eq(kind_uuid)
    end

    it "is an invoice's own uuid" do
      row = transaction(MossInvoice, moss_transaction_uuid: transaction_uuid,
        moss_invoice_uuid: kind_uuid)
      expect(row.reload.moss_object_uuid).to eq(kind_uuid)
    end

    it "is the transaction uuid of a top-up and of a card payment" do
      top_up = transaction(MossTopUp, moss_transaction_uuid: transaction_uuid)
      card = transaction(MossCardTransaction, moss_transaction_uuid: kind_uuid)
      expect(top_up.reload.moss_object_uuid).to eq(transaction_uuid)
      expect(card.reload.moss_object_uuid).to eq(kind_uuid)
    end

    # A reimbursement's uuid and another row's Transaction ID name the same Moss
    # object; only the unique index over the generated column catches that.
    it "is unique across the kinds" do
      transaction(MossReimbursement, moss_transaction_uuid: transaction_uuid,
        moss_reimbursement_uuid: kind_uuid)
      expect { transaction(MossTopUp, moss_transaction_uuid: kind_uuid) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  # L3 is keyed on (moss_expense_id, sub_row_number). The key is a unique
  # CONSTRAINT rather than a plain unique index, and it is DEFERRABLE INITIALLY
  # DEFERRED: Postgres checks it at COMMIT, so an import that renumbers the
  # splits of an expense may leave the numbering ambiguous between its
  # statements and only has to end on a unique assignment. All uuids below are
  # invented.
  describe "MossExpense (moss_transaction_id, expense_number)" do
    let(:connection) { ActiveRecord::Base.connection }

    let(:constraint_name) { "unq_moss_expenses_transaction_expense_number" }

    let(:key) do
      connection.unique_constraints("moss_expenses")
        .find { |constraint| constraint.name == constraint_name }
    end

    # One reimbursement whose two expenses are numbered 1 and 2. All uuids below
    # are invented.
    let(:reimbursement) do
      MossReimbursement.create!(moss_transaction_uuid: "eeeeeeee-1111-2222-3333-444444444444",
        signed_total_base_amount: 500, currency: "EUR",
        booking_date: Date.new(2026, 5, 3)).tap do |tx|
          [1, 2].each do |number|
            MossReimbursementExpense.create!(moss_transaction: tx,
              moss_expense_uuid: "eeeeeeee-1111-2222-3333-00000000000#{number}",
              expense_number: number, signed_expense_base_amount: 250)
          end
        end
    end

    # In creation order -- the association reads in expense-number order, which
    # is the very thing the reorder changes.
    def expenses = MossExpense.where(moss_transaction: reimbursement).order(:id)

    it "is a deferrable, initially deferred unique constraint" do
      expect(key).to be_present
      expect(key.column).to eq(["moss_transaction_id", "expense_number"])
      expect(key.deferrable).to eq(:deferred)
    end

    it "has replaced the plain unique index" do
      expect(connection.index_exists?(:moss_expenses, [:moss_transaction_id, :expense_number],
        name: "index_moss_expenses_transaction_expense_number")).to be(false)
    end

    it "exchanges two expense numbers over two statements" do
      expect(expenses.pluck(:expense_number)).to eq([1, 2])
      first, second = expenses.to_a
      MossExpense.where(id: first.id).update_all(expense_number: 2)
      expect(expenses.pluck(:expense_number)).to eq([2, 2])
      MossExpense.where(id: second.id).update_all(expense_number: 1)
      expect(expenses.pluck(:expense_number)).to eq([2, 1])
    end

    # An example runs inside a transaction that RSpec rolls back, so the check
    # a deferred constraint runs at COMMIT never happens here. SET CONSTRAINTS
    # ... IMMEDIATE makes Postgres evaluate the pending rows on the spot, which
    # is that very check; issuing it inside a savepoint keeps the example's own
    # transaction usable after the error. The expenses are read before the
    # savepoint opens, so its rollback undoes only the renumbering.
    it "still rejects two expenses under the same number" do
      expect(expenses.pluck(:expense_number)).to eq([1, 2])
      expect do
        MossExpense.transaction(requires_new: true) do
          expenses.update_all(expense_number: 1)
          connection.execute("SET CONSTRAINTS #{constraint_name} IMMEDIATE")
        end
      end.to raise_error(ActiveRecord::RecordNotUnique)
      expect(expenses.pluck(:expense_number)).to eq([1, 2])
    end
  end

  describe "MossBooking (moss_expense_id, sub_row_number)" do
    let(:connection) { ActiveRecord::Base.connection }

    let(:constraint_name) { "unq_moss_bookings_expense_sub_row" }

    let(:key) do
      connection.unique_constraints("moss_bookings")
        .find { |constraint| constraint.name == constraint_name }
    end

    # One expense whose two splits are numbered 1 and 2.
    let(:expense) do
      tx = MossTopUp.create!(moss_transaction_uuid: "ffffffff-1111-2222-3333-444444444444",
        signed_total_base_amount: 500, currency: "EUR", payment_date: Date.new(2026, 5, 3))
      MossTopUpExpense.create!(moss_transaction: tx, moss_expense_uuid: tx.reload.moss_object_uuid,
        signed_expense_base_amount: 500).tap do |shell|
          [1, 2].each do |number|
            MossBooking.create!(moss_transaction: tx, moss_expense: shell,
              signed_base_amount: 250, sub_row_number: number)
          end
        end
    end

    # In creation order -- the association reads in sub-row order, which is the
    # very thing the reorder changes.
    def splits = MossBooking.where(moss_expense: expense).order(:id)

    it "is a deferrable, initially deferred unique constraint" do
      expect(key).to be_present
      expect(key.column).to eq(["moss_expense_id", "sub_row_number"])
      expect(key.deferrable).to eq(:deferred)
    end

    it "has replaced the plain unique index" do
      expect(connection.index_exists?(:moss_bookings, [:moss_expense_id, :sub_row_number],
        name: "index_moss_bookings_expense_sub_row")).to be(false)
    end

    it "exchanges two sub-row numbers over two statements" do
      expect(splits.pluck(:sub_row_number)).to eq([1, 2])
      first, second = splits.to_a
      MossBooking.where(id: first.id).update_all(sub_row_number: 2)
      expect(splits.pluck(:sub_row_number)).to eq([2, 2])
      MossBooking.where(id: second.id).update_all(sub_row_number: 1)
      expect(splits.pluck(:sub_row_number)).to eq([2, 1])
    end

    # An example runs inside a transaction that RSpec rolls back, so the check
    # a deferred constraint runs at COMMIT never happens here. SET CONSTRAINTS
    # ... IMMEDIATE makes Postgres evaluate the pending rows on the spot, which
    # is that very check; issuing it inside a savepoint keeps the example's own
    # transaction usable after the error. The splits are read before the
    # savepoint opens, so its rollback undoes only the renumbering.
    it "still rejects two splits under the same number" do
      expect(splits.pluck(:sub_row_number)).to eq([1, 2])
      expect do
        MossBooking.transaction(requires_new: true) do
          splits.update_all(sub_row_number: 1)
          connection.execute("SET CONSTRAINTS #{constraint_name} IMMEDIATE")
        end
      end.to raise_error(ActiveRecord::RecordNotUnique)
      expect(splits.pluck(:sub_row_number)).to eq([1, 2])
    end
  end
end
