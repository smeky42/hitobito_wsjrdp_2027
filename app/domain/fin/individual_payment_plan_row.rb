# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# One row of the Individuelle Ratenpläne list (Fin::IndividualPaymentPlansController):
# a person with an active individual installment plan, a planned one, or both
# (Fin::ListedPaymentPlan). The active plan is the person's own
# (people.wsjrdp_raw_installments_eur ...); the active fee rule it came from
# dates its activation. A person with a plan only shows the standard plan of
# their role in the row, the planned plan below it (Fin::IndividualPaymentPlanDraft).
# How the person's payments stand against the active plan:
# Fin::PaymentProgress, as of `today`.
Fin::IndividualPaymentPlanRow = Data.define(:person, :active_plan, :planned_plan, :standard_plan, :activated_at,
  :progress) do
  # The people with an active or a planned fee rule that carries a plan --
  # what the list shows; a rule with a reduction alone does not count.
  def self.people_with_plan(people = Person.all)
    people.where(id: Wsj27RdpFeeRule.with_plan.where(status: %w[active planned], deleted_at: nil).select(:people_id))
  end

  # The rows of the given people (one query for their fee rules, one for the
  # standard plans; the pre-notifications come with the people).
  def self.for(people, today: Date.current)
    people = people.to_a
    rules = Wsj27RdpFeeRule.where(people_id: people.map(&:id), status: %w[active planned], deleted_at: nil)
      .group_by(&:people_id)
    standard = WsjrdpPaymentPlan.kept.index_by { |plan| [plan.wsjrdp_role, plan.single_payment, plan.payment_method] }
    people.map do |person|
      own = rules.fetch(person.id, [])
      active_rule = own.find { |rule| rule.status == "active" }
      standard_plan = standard[[person.wsjrdp_role, person.early_payer || false,
        Wsjrdp2027::ParticipationFee::DEFAULT_PAYMENT_METHOD]]
      active_plan = Fin::ListedPaymentPlan.active_of(person)
      standard_plan = Fin::ListedPaymentPlan.standard_of(standard_plan)
      new(person: person,
        active_plan: active_plan,
        planned_plan: Fin::ListedPaymentPlan.planned_of(own.find { |rule| rule.status == "planned" }),
        standard_plan: standard_plan,
        activated_at: active_rule && (active_rule.activated_at || active_rule.created_at),
        progress: Fin::PaymentProgress.new(person: person, plan: active_plan,
          pre_notifications: person.direct_debit_pre_notifications, today: today))
    end
  end

  def id = person.id

  def planned? = !planned_plan.nil?

  # The plan the row shows: the active one, else the standard plan in effect.
  def shown_plan = active_plan || standard_plan

  # The planned plan as the row's sub-row.
  def plans = planned? ? [Fin::IndividualPaymentPlanDraft.new(row: self)] : []

  # The longest strip of the row's plans (the shown one, the planned one);
  # nil without any.
  def strip_length = [shown_plan, planned_plan].compact.map(&:strip_length).max

  # The fee the plan has to bring in (Person#total_fee_cents), what came in
  # so far and what is still open.
  def fee_cents = progress.fee_cents

  def paid_cents = progress.paid_cents

  def open_cents = fee_cents - paid_cents
end

# A planned installment plan as the sub-row of its Fin::IndividualPaymentPlanRow: its
# values under the cells they would replace
# (Fin::IndividualPaymentPlansHelper#individual_plan_draft_cell).
Fin::IndividualPaymentPlanDraft = Data.define(:row) do
  def person = row.person

  def plan = row.planned_plan

  def fee_cents = row.fee_cents
end
