# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

describe Fin::PaymentQueries do
  include_context "payment area"

  describe "WsjrdpPaymentInitiation#kind" do
    it "says in Ruby what kind_sql says in SQL" do
      conflict = WsjrdpPaymentInitiation.create!(sepa_schema: "pain.001.001.09")
      WsjrdpDirectDebitPaymentInfo.create!(payment_initiation: conflict)
      unknown = WsjrdpPaymentInitiation.create!
      orders = [debit_order, transfer_order, conflict, unknown]

      sql = WsjrdpPaymentInitiation.where(id: orders).pluck(:id, Arel.sql(WsjrdpPaymentInitiation.kind_sql)).to_h
      expect(orders.map { |order| [order.reload.kind, sql[order.id]] }).to eq(
        [%w[direct_debit direct_debit], %w[credit_transfer credit_transfer], %w[conflict conflict],
          %w[unknown unknown]]
      )
    end

    it "takes an order with direct debit Sammler but no schema for a direct debit" do
      order = WsjrdpPaymentInitiation.create!
      WsjrdpDirectDebitPaymentInfo.create!(payment_initiation: order)

      expect(order.kind).to eq("direct_debit")
    end
  end

  it "assigns a return to its debit and order by the end-to-end id" do
    orders = described_class.orders.where(id: [debit_order, transfer_order]).index_by(&:id)
    expect(orders[debit_order.id]).to have_attributes(kind: "direct_debit", return_count: 1,
      return_sum_cents: -20_000, sequence_types: "RCUR", fin_account_id: account.id)
    expect(orders[transfer_order.id]).to have_attributes(kind: "credit_transfer", return_count: 0,
      fin_account_id: nil)

    returns = described_class.returns.where(id: [returned, unassigned_return]).index_by(&:id)
    expect(returns[returned.id]).to have_attributes(notice_id: returned_debit.id, notice_matched_by: "endtoend",
      order_id: debit_order.id, info_id: payment_info.id, return_entry_id: return_entry.id, amount_cents: -20_000)
    expect(returns[unassigned_return.id]).to have_attributes(notice_id: nil, order_id: nil, return_entry_id: nil)
  end

  it "finds the debit by the mandate where the bank sent an end-to-end id of its own" do
    paid_debit.update!(mandate_id: "wsjrdp-test-2")
    by_mandate = camt_return(-100, endtoend_id: "2512181044-0000002", mandate_id: "wsjrdp-test-2",
      return_reason: "MS03", value_date: Date.new(2026, 5, 8))
    too_late = camt_return(-100, endtoend_id: "2512181044-0000003", mandate_id: "wsjrdp-test-2",
      return_reason: "MS03", value_date: Date.new(2026, 5, 20))

    returns = described_class.returns.where(id: [by_mandate, too_late]).index_by(&:id)
    expect(returns[by_mandate.id]).to have_attributes(notice_id: paid_debit.id, notice_matched_by: "mandate",
      order_id: debit_order.id)
    expect(returns[too_late.id]).to have_attributes(notice_id: nil, order_id: nil)
    expect(described_class.debits.find(paid_debit.id)).to have_attributes(return_count: 1,
      return_sum_cents: -10_000)
  end

  it "takes the debit a return links over any it would match" do
    returned.update!(direct_debit_pre_notification: paid_debit)

    ret = described_class.returns.find(returned.id)
    expect(ret).to have_attributes(notice_id: paid_debit.id, notice_matched_by: "link")
    expect(described_class.debits.find(returned_debit.id)).to have_attributes(return_count: 0)
    expect(paid_debit.return_camt_transactions).to eq([returned])
    expect(paid_debit.collection_camt_transactions).to be_empty
  end

  it "sums the bank's collective credits of a Sammler and its order" do
    expect(described_class.payment_info(payment_info.id)).to have_attributes(credit_count: 0,
      order_status: "xml_generated")
    credit = camt_credit(300, payment_info)

    expect(described_class.payment_info(payment_info.id)).to have_attributes(credit_count: 1,
      credit_sum_cents: 30_000, credit_id: credit.id, credit_date: Date.new(2026, 5, 5))
    expect(described_class.orders.find(debit_order.id)).to have_attributes(credit_count: 1,
      credit_sum_cents: 30_000)
    expect(payment_info.camt_transactions).to eq([credit])
  end

  it "takes the bank statement, not the accounting entries, as the record of a return" do
    payment_entry(-3_000, endtoend_id: "E2E-2", return_reason: "MS03")

    expect(described_class.returns.count(:all)).to eq(2)
    expect(described_class.debits.find(paid_debit.id)).to have_attributes(return_count: 0)
  end

  it "keeps a returned credit transfer out of the returned direct debits" do
    transfer = returned_transfer(cdtr_name: "Beispiel GmbH")

    expect(transfer.reload).to have_attributes(return_kind: "credit_transfer", gvc: "159",
      bank_transaction_family: "ICDT", bank_transaction_sub_family: "RRTN")
    expect(described_class.returns.where(id: transfer.id)).to be_empty
    expect(described_class.other_returns.find(transfer.id).amount_cents).to eq(15_000)
  end

  it "sums a list of orders" do
    totals = described_class.order_totals(described_class.orders.where(id: [debit_order, transfer_order]))
    expect(totals).to eq(count: 3, sum_cents: 35_000, pre_notified_count: 2, pre_notified_sum_cents: 30_000,
      return_count: 1, return_sum_cents: -20_000)
  end

  it "sums a list of debits by status, skipped ones at their announced amount" do
    paid_debit.update!(pre_notified_amount_cents: 12_000)
    payment_debit("E2E-3", 5_000).update!(payment_status: "skipped")

    expect(described_class.debit_totals(described_class.debits)).to include(count: 3, announced_cents: 37_000,
      collected_count: 2, collected_cents: 30_000, skipped_count: 1, skipped_cents: 5_000, return_count: 1)
  end

  it "groups what an order did not collect by amount, the most frequent first" do
    [5_000, 7_000, 5_000].each_with_index do |cents, i|
      payment_debit("E2E-S#{i}", cents).update!(payment_status: "skipped")
    end

    expect(described_class.order_not_collected_amounts(debit_order.id)).to eq([[5_000, 2], [7_000, 1]])
  end

  it "puts only the collected debits that name it into a Sammler" do
    other = WsjrdpDirectDebitPaymentInfo.create!(payment_initiation: debit_order, debit_sequence_type: "FRST")
    paid_debit.update!(direct_debit_payment_info: other)
    payment_debit("E2E-3", 5_000).update!(payment_status: "skipped")

    expect(described_class.payment_info_debits(payment_info).map(&:id)).to eq([returned_debit.id])
  end

  it "reads the collection entry's amount beside the debit's" do
    AccountingEntry.create!(subject: person, author: person, amount_cents: 15_000, description: "Einzug",
      direct_debit_pre_notification: returned_debit)

    expect(described_class.debits.find(returned_debit.id)).to have_attributes(entry_amount_cents: 15_000,
      amount_cents: 20_000)
  end

  describe Fin::PaymentsOverview do
    it "counts the open work, the next collection, the months and the reasons" do
      travel_to(Date.new(2026, 6, 1)) do
        paid_debit.update!(payment_status: "pre_notified", collection_date: Date.new(2026, 6, 4))
        overview = described_class.new(person_level: true)

        expect(overview).to have_attributes(returns_in_review_count: 2, other_returns_unlinked_count: 0)
        expect(overview.next_collection).to have_attributes(date: Date.new(2026, 6, 4), count: 1, sum_cents: 10_000,
          overdue_count: 0)
        expect(overview.months).to eq([described_class::Month.new(month: Date.new(2026, 5, 1), count: 2,
          sum_cents: 30_000, return_count: 1)])
        expect(overview.return_reasons.map(&:code)).to eq(%w[MD06 MS03])
      end
    end
  end
end
