# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # The participation fee ("Teilnahmebeitrag") of one person: what the person
  # pays and how. Reached through Person#participation_fee, which keeps one
  # object per loaded person and drops it on reload.
  #
  # Activating the planned installments: the planned fee rule becomes the active
  # one (the replaced rule is soft-deleted and becomes its prev_rule_id), and
  # the person's columns wsjrdp_raw_installments_eur / _issue / _comment get the
  # same plan -- in one transaction, so the fee rule and the person always say
  # the same. The person's columns are to become the source of the active plan;
  # until then both carry it.
  #
  # Activating the planned total fee reduction: the planned values
  # (additional_info) become the active ones (wsjrdp_total_fee_reduction*), the
  # plan is cleared.
  #
  # Controllers check the permission (:update_finance) and answer.
  class ParticipationFee
    # The planned reduction attributes, each with the active attribute
    # activating copies it to.
    PLANNED_TO_ACTIVE_REDUCTION = {
      planned_total_fee_reduction_issue: :active_total_fee_reduction_issue,
      planned_total_fee_reduction: :active_total_fee_reduction,
      planned_total_fee_reduction_hint: :active_total_fee_reduction_hint,
      planned_total_fee_reduction_comment: :active_total_fee_reduction_comment
    }.freeze

    PLANNED_REDUCTION_ATTRS = PLANNED_TO_ACTIVE_REDUCTION.keys.freeze

    attr_reader :person

    def initialize(person)
      @person = person
    end

    # The person's installment columns for a fee rule: the plan as
    # [starting year, euros per month from January] -- the format of
    # wsjrdp_payment_plans.raw_installments_eur --, its issue and comment. A
    # rule without custom installments clears them.
    def self.person_installments_attrs(rule)
      {wsjrdp_raw_installments_eur: raw_installments_eur(rule),
       wsjrdp_installments_issue: rule&.custom_installments_issue.presence,
       wsjrdp_installments_comment: rule&.custom_installments_comment.presence}
    end

    def self.raw_installments_eur(rule)
      year = rule&.custom_installments_starting_year
      cents = rule&.custom_installments_cents
      return nil if year.nil? || cents.nil?

      [BigDecimal(year), *cents.map { |c| BigDecimal(c.to_i) / 100 }]
    end

    # Activates the person's planned fee rule. Answers the activated rule, nil
    # without a plan.
    def activate_installments!
      planned = person.planned_fee_rule
      return if planned.nil? || planned.new_record?

      ActiveRecord::Base.transaction do
        previous = person.active_fee_rule
        previous&.soft_delete!
        planned.activate!(previous&.id)
        person.assign_attributes(self.class.person_installments_attrs(planned))
        person.save!
      end
      person.forget_fee_rules
      planned
    end

    # Activates the person's planned total fee reduction. Answers false without
    # a plan.
    def activate_reduction!
      return false if person.planned_total_fee_reduction.nil?

      PLANNED_TO_ACTIVE_REDUCTION.each { |from, to| person.public_send(:"#{to}=", person.public_send(from)) }
      clear_planned_reduction
      person.save!
      true
    end

    # Drops the person's planned total fee reduction.
    def discard_reduction!
      clear_planned_reduction
      person.save!
    end

    # A new plan from scratch, not saved.
    def clear_planned_reduction
      PLANNED_REDUCTION_ATTRS.each { |attr| person.public_send(:"#{attr}=", nil) }
    end

    # A new plan starting from the active reduction, not saved.
    def plan_reduction_from_active
      PLANNED_TO_ACTIVE_REDUCTION.each { |planned, active| person.public_send(:"#{planned}=", person.public_send(active)) }
    end
  end
end
