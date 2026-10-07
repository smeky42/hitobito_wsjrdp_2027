# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# How far a person's payments have come: what came in (the accounting
# entries, Person#amount_paid_cents -- the balance the Beitrag page shows,
# whatever an entry's value date) against the fee, and against what is due
# today -- the ACTIVE plan's installments (Fin::ListedPaymentPlan) up to a
# month that depends on how the plan is paid. A person without an active plan
# (a planned one alone) gets no judgement: the state is :none.
#
# Credit transfer: the person pays each installment themselves. An
# installment is due from the second bank day (Wsjrdp2027::Target2) of the
# month after its own.
#
# Direct debit: the contingent collects. The installments of the months
# before the current one are due. The current month's is due as well once
# the balance covers it already (the person transferred it instead of waiting
# for the collection), once a collection of the month exists (its SEPA file
# generated, whatever its date), or once a collection announced for the month
# is a day or more past its date; until then the month is still open.
class Fin::PaymentProgress
  STATES = %i[none overpaid paid behind on_plan].freeze

  attr_reader :person, :plan, :pre_notifications, :today

  def initialize(person:, plan:, pre_notifications:, today: Date.current)
    @person = person
    @plan = plan
    @pre_notifications = pre_notifications.to_a
    @today = today
  end

  # The day an installment of a month is due by credit transfer.
  def self.due_day(year_month)
    following = year_month + 1
    Wsjrdp2027::Target2.nth_bank_day_of_month(following.year, following.month, 2)
  end

  # The last month whose installment is due by credit transfer on `today`.
  def self.due_through(today)
    year_month = Wsjrdp2027::YearMonth.new(today.year, today.month) + -1
    year_month += -1 while due_day(year_month) > today
    year_month
  end

  def paid_cents = @paid_cents ||= person.amount_paid_cents

  def fee_cents = @fee_cents ||= person.total_fee_cents

  # The entries counted in paid_cents whose value date lies after the end of
  # the current month: money that is not there yet.
  def late_entries
    @late_entries ||= person.accounting_entries.select { |entry| entry.value_date > today.end_of_month }
  end

  def credit_transfer? = plan&.payment_method == "credit_transfer"

  def current_month = Wsjrdp2027::YearMonth.new(today.year, today.month)

  # none: no active plan to judge by; overpaid: more came in than the fee;
  # paid: the fee exactly; behind: less than is due today; on_plan: the rest.
  def state
    if plan.nil?
      :none
    elsif paid_cents > fee_cents
      :overpaid
    elsif paid_cents == fee_cents
      :paid
    elsif paid_cents < due_cents
      :behind
    else
      :on_plan
    end
  end

  def due_cents = due_installments.sum(&:cents)

  # What is missing against what is due (positive), or what is ahead.
  def gap_cents = due_cents - paid_cents

  # The installments due today.
  def due_installments
    return [] if plan.nil?
    return plan.installments.select { |i| self.class.due_day(i.year_month) <= today } if credit_transfer?

    earlier = plan.installments.select { |installment| installment.year_month < current_month }
    current = current_installment
    return earlier if current.nil? || !current_month_counts?(earlier.sum(&:cents) + current.cents)

    earlier + [current]
  end

  # The current month's installment, where the plan has one.
  def current_installment
    return if plan.nil?

    plan.installments.find { |installment| installment.year_month == current_month }
  end

  # Whether the current month's installment is due already -- never by
  # credit transfer, its due day lies in the following month.
  def current_month_due?
    current = current_installment
    !current.nil? && due_installments.include?(current)
  end

  private

  # Direct debit: whether the current month's installment counts already,
  # given what the plan asks for through the current month.
  def current_month_counts?(through_current_cents)
    paid_cents >= through_current_cents || collection_in_current_month?
  end

  def announcements
    @announcements ||= pre_notifications.reject { |notification| notification.skipped? || notification.collection_date.nil? }
  end

  # A collection of the current month that exists (the SEPA file generated)
  # or that is announced and a day or more past its date.
  def collection_in_current_month?
    announcements.any? do |notification|
      date = notification.collection_date
      Wsjrdp2027::YearMonth.new(date.year, date.month) == current_month &&
        (notification.payment_status == "xml_generated" || date < today)
    end
  end
end
