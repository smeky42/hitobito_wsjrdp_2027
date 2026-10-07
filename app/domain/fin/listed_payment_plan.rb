# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# One installment plan as the Individuelle Ratenpläne list shows it
# (Fin::IndividualPaymentPlanRow): the ACTIVE plan of a person -- the person's
# own columns wsjrdp_raw_installments_eur, _issue, _comment and
# _payment_method --, a PLANNED one (a planned fee rule that carries a plan),
# or the STANDARD plan of the person's role (WsjrdpPaymentPlan), which applies
# while no individual plan is active.
class Fin::ListedPaymentPlan < Data.define(:kind, :yme_list, :payment_method, :issue, :comment)
  # The months of a plan's strip in the list: December 2025 to May 2027 -- the
  # span of the standard plans -- as long as the plan lies within it
  # (#strip_range).
  STRIP_FROM = Wsjrdp2027::YearMonth.new(2025, 12)
  STRIP_TO = Wsjrdp2027::YearMonth.new(2027, 5)
  STRIP_LENGTH = STRIP_FROM.distance_in_months_to(STRIP_TO) + 1

  # The person's active plan; nil without one.
  def self.active_of(person)
    raw = person.wsjrdp_raw_installments_eur
    return if raw.blank?

    new(kind: :active,
      yme_list: Wsjrdp2027::PaymentPlanConversionHelper.year_and_eur_a_to_yme_list(raw[0].to_i, raw[1..]),
      payment_method: person.wsjrdp_installments_payment_method,
      issue: person.wsjrdp_installments_issue, comment: person.wsjrdp_installments_comment)
  end

  # The plan of a planned fee rule; nil for a rule without one (a reduction).
  def self.planned_of(rule)
    return unless rule&.custom_installments_plan?

    new(kind: :planned, yme_list: rule.yme_list, payment_method: rule.custom_installments_payment_method,
      issue: rule.custom_installments_issue, comment: rule.custom_installments_comment)
  end

  # A standard plan (WsjrdpPaymentPlan); nil without one.
  def self.standard_of(plan)
    return if plan.nil?

    new(kind: :standard, yme_list: plan.yme_list, payment_method: plan.payment_method, issue: nil, comment: nil)
  end

  def active? = kind == :active

  def planned? = kind == :planned

  def standard? = kind == :standard

  # The months that carry an installment, in order.
  def installments = yme_list.reject { |installment| installment.cents.zero? }

  def count = installments.size

  def first_month = installments.first&.year_month

  def last_month = installments.last&.year_month

  def total_cents = yme_list.sum(&:cents)

  # The installment of one month; 0 for a month without one.
  def cents_in(year_month)
    yme_list.find { |installment| installment.year_month == year_month }&.cents || 0
  end

  # How far the plan misses the fee: positive when it brings in more than
  # fee_cents, negative when less (as the check on the person's Beitrag page).
  def gap_cents(fee_cents) = total_cents - fee_cents

  # The first and the last month of the plan's strip: the standard span
  # (STRIP_FROM to STRIP_TO) for a plan within it. A plan that reaches beyond
  # its end stretches the strip to its last month, and to its first where that
  # comes earlier; a plan that starts earlier and ends within the span shows
  # from its start on, for at least the span's length.
  def strip_range
    first = first_month
    last = last_month
    return [STRIP_FROM, STRIP_TO] if first.nil? || (first >= STRIP_FROM && last <= STRIP_TO)

    if last > STRIP_TO
      [[STRIP_FROM, first].min, last]
    else
      [first, [last, first + (STRIP_LENGTH - 1)].max]
    end
  end

  # The strip's months, one bar each.
  def strip_months
    from, to = strip_range
    (0..from.distance_in_months_to(to)).map { |offset| from + offset }
  end

  def strip_length = strip_months.size
end
