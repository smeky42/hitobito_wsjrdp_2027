# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# What came in against the fee and against what is due today: for a credit
# transfer by the plan's installments and their due days, for a direct debit
# by the announced collections.
describe Fin::PaymentProgress do
  let(:person) { people(:yp_a_1) }
  let(:admin) { people(:admin) }
  let(:today) { Date.new(2026, 10, 8) }

  def month(year, month) = Wsjrdp2027::YearMonth.new(year, month)

  # 17 x 200 € from January 2026: the fee of 3.400 €.
  def plan(payment_method, months = (1..17).map { |i| [2026 + (i - 1) / 12, (i - 1) % 12 + 1] })
    Fin::ListedPaymentPlan.new(kind: :active, payment_method: payment_method, issue: nil, comment: nil,
      yme_list: months.map { |year, mon| Wsjrdp2027::YearMonthEur.new(year_month: [year, mon], eur: 200) })
  end

  def paid(cents)
    AccountingEntry.create!(subject: person, author: admin, amount_cents: cents, description: "Beitrag",
      value_date: Date.new(2026, 2, 1), booking_date: Date.new(2026, 2, 1))
  end

  # A pre-notification needs a payment initiation; nothing here is written.
  def notification(collection_date, cents: 20_000, payment_status: "xml_generated")
    WsjrdpDirectDebitPreNotification.new(subject: person, author: admin, amount_cents: cents,
      description: "Einzug", payment_status: payment_status, dbtr_name: "Muster",
      dbtr_iban: "DE02120300000000202051", collection_date: collection_date)
  end

  def progress(plan, notifications = [], today: self.today)
    described_class.new(person: person.reload, plan: plan, pre_notifications: notifications, today: today)
  end

  describe "the due days" do
    it "makes an installment due on the second bank day of the following month" do
      expect(described_class.due_day(month(2026, 9))).to eq Date.new(2026, 10, 2)
      expect(described_class.due_day(month(2026, 10))).to eq Date.new(2026, 11, 3)
      expect(described_class.due_day(month(2025, 12))).to eq Date.new(2026, 1, 5)
    end

    it "names the last month due on a day" do
      expect(described_class.due_through(Date.new(2026, 10, 8))).to eq month(2026, 9)
      expect(described_class.due_through(Date.new(2026, 10, 1))).to eq month(2026, 8)
      expect(described_class.due_through(Date.new(2026, 11, 3))).to eq month(2026, 10)
      expect(described_class.due_through(Date.new(2026, 11, 2))).to eq month(2026, 9)
    end
  end

  describe "a plan paid by credit transfer" do
    let(:transfer) { plan("credit_transfer") }

    it "is due up to the month whose due day has passed; the current month's installment never" do
      expect(progress(transfer).due_cents).to eq 180_000
      expect(progress(transfer).due_installments.last.year_month).to eq month(2026, 9)
      expect(progress(transfer).current_installment.year_month).to eq month(2026, 10)
      expect(progress(transfer).current_month_due?).to be false
      expect(progress(transfer, today: Date.new(2026, 10, 1)).due_cents).to eq 160_000
      expect(progress(transfer, today: Date.new(2026, 1, 1)).due_cents).to eq 0
    end

    it "is behind with less than due, on plan with it, paid with the fee, overpaid beyond" do
      paid(170_000)
      expect(progress(transfer)).to have_attributes(state: :behind, gap_cents: 10_000)
      paid(10_000)
      expect(progress(transfer)).to have_attributes(state: :on_plan, gap_cents: 0)
      paid(160_000)
      expect(progress(transfer).state).to eq :paid
      paid(1)
      expect(progress(transfer).state).to eq :overpaid
    end

    it "takes no notice of pre-notifications" do
      expect(progress(transfer, [notification(Date.new(2026, 9, 7))]).due_cents).to eq 180_000
      expect(progress(transfer, [notification(Date.new(2026, 10, 5))]).due_cents).to eq 180_000
    end
  end

  describe "a plan paid by direct debit" do
    let(:debit) { plan("direct_debit") }

    it "is due the installments of the months before the current one; the current month's not yet" do
      expect(progress(debit).due_cents).to eq 180_000
      expect(progress(debit).due_installments.last.year_month).to eq month(2026, 9)
      expect(progress(debit, today: Date.new(2026, 1, 1)).due_cents).to eq 0
    end

    it "counts the current month once a collection of it exists, is a day past its date, or is covered already" do
      expect(progress(debit).current_installment.year_month).to eq month(2026, 10)
      expect(progress(debit).current_month_due?).to be false
      expect(progress(debit, [notification(Date.new(2026, 10, 5))]).current_month_due?).to be true
      expect(progress(debit, [notification(Date.new(2026, 10, 5))]).due_cents).to eq 200_000
      # The SEPA file generated ahead of its date.
      expect(progress(debit, [notification(Date.new(2026, 10, 12))]).due_cents).to eq 200_000
      expect(progress(debit, [notification(Date.new(2026, 10, 7), payment_status: "pre_notified")]).due_cents).to eq 200_000
      expect(progress(debit, [notification(Date.new(2026, 10, 8), payment_status: "pre_notified")]).due_cents).to eq 180_000
      expect(progress(debit, [notification(Date.new(2026, 10, 12), payment_status: "pre_notified")]).due_cents).to eq 180_000
      expect(progress(debit, [notification(Date.new(2026, 10, 5), payment_status: "skipped")]).due_cents).to eq 180_000
      expect(progress(debit, [notification(Date.new(2026, 9, 7))]).due_cents).to eq 180_000
      paid(200_000)
      expect(progress(debit)).to have_attributes(due_cents: 200_000, state: :on_plan)
      expect(progress(debit).current_month_due?).to be true
    end

    it "has no current month's installment where the plan has none" do
      ended = progress(plan("direct_debit", [[2026, 1]]), [notification(Date.new(2026, 10, 5))])

      expect(ended.current_installment).to be_nil
      expect(ended.current_month_due?).to be false
      expect(ended.due_cents).to eq 20_000
    end

    it "is behind with less than due, after a returned debit too" do
      paid(170_000)
      expect(progress(debit)).to have_attributes(state: :behind, gap_cents: 10_000)
      paid(10_000)
      expect(progress(debit).state).to eq :on_plan
      paid(-20_300) # a returned debit, with the bank's fee
      expect(progress(debit)).to have_attributes(state: :behind, gap_cents: 20_300)
    end

    it "judges a person without an active plan not at all" do
      paid(340_000)

      expect(progress(nil, [notification(Date.new(2026, 10, 5))])).to have_attributes(due_cents: 0, state: :none)
    end
  end

  describe "entries with a value date after the end of the month" do
    it "count as paid and are named" do
      paid(10_000)
      late = AccountingEntry.create!(subject: person, author: admin, amount_cents: 30_000, description: "Beitrag",
        value_date: Date.new(2026, 11, 3), booking_date: Date.new(2026, 11, 3))

      current = progress(plan("direct_debit"))
      expect(current.paid_cents).to eq 40_000
      expect(current.late_entries).to eq [late]
      expect(progress(plan("direct_debit"), today: Date.new(2026, 11, 3)).late_entries).to eq []
    end
  end
end
