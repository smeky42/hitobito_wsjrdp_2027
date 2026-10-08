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
  # Planning installments (the plan's form on the Beitrag page): the planned
  # fee rule, started blank, from the active plan or from the standard plan of
  # the person's role, then saved through the person (planned_custom_installments_*);
  # discarding soft-deletes it. Activating and discarding record who did it
  # (activated_by, deleted_by); the history lists the plans that were active.
  #
  # Activating the planned total fee reduction: the planned values
  # (additional_info) become the active ones (wsjrdp_total_fee_reduction*), the
  # plan is cleared.
  #
  # Controllers check the permission (:update_finance) and answer.
  class ParticipationFee
    # How an installment plan is paid: by SEPA direct debit, or by the
    # person's own credit transfers to the contingent's account. A plan
    # without one is paid by direct debit.
    PAYMENT_METHODS = %w[direct_debit credit_transfer].freeze
    DEFAULT_PAYMENT_METHOD = "direct_debit"

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

    # The payment methods as [value, label] for a select.
    def self.payment_method_options = PAYMENT_METHODS.map { |method| [method, payment_method_label(method)] }

    # "Lastschrift" / "Überweisung"; nil for none.
    def self.payment_method_label(method)
      I18n.t("people.payment_methods.#{method}", default: method.to_s) if method.present?
    end

    # The person's installment columns for a fee rule: the plan as
    # [starting year, euros per month from January] -- the format of
    # wsjrdp_payment_plans.raw_installments_eur --, its issue, comment and
    # payment method. A rule without custom installments clears them; the
    # payment method goes with the plan only.
    def self.person_installments_attrs(rule)
      raw = raw_installments_eur(rule)
      {wsjrdp_raw_installments_eur: raw,
       wsjrdp_installments_issue: rule&.custom_installments_issue.presence,
       wsjrdp_installments_comment: rule&.custom_installments_comment.presence,
       wsjrdp_installments_payment_method: raw && (rule.custom_installments_payment_method || DEFAULT_PAYMENT_METHOD)}
    end

    def self.raw_installments_eur(rule)
      year = rule&.custom_installments_starting_year
      cents = rule&.custom_installments_cents
      return nil if year.nil? || cents.nil?

      [BigDecimal(year), *cents.map { |c| BigDecimal(c.to_i) / 100 }]
    end

    # Activates the person's planned fee rule. Answers the activated rule, nil
    # without a plan. by: the person who activates it.
    def activate_installments!(by: nil)
      planned = person.planned_fee_rule
      return if planned.nil? || planned.new_record?

      ActiveRecord::Base.transaction do
        previous = person.active_fee_rule
        previous&.soft_delete!(by: by)
        planned.activate!(previous&.id, by: by)
        person.assign_attributes(self.class.person_installments_attrs(planned))
        person.save!
      end
      person.forget_fee_rules
      planned
    end

    # Drops the person's planned fee rule. Answers the dropped rule, nil
    # without one. by: the person who drops it.
    def discard_installments!(by: nil)
      planned = person.planned_fee_rule
      return if planned.nil? || planned.new_record?

      planned.soft_delete!(by: by)
      person.forget_fee_rules
      planned
    end

    # A new planned plan from scratch, not saved: the planned fee rule without
    # a plan, issue and comment, paid by direct debit.
    def clear_planned_installments
      plan_installments(year: nil, cents: nil, issue: nil, comment: nil, payment_method: nil)
    end

    # A new planned plan starting from the active plan, not saved.
    def plan_installments_from_active
      active = person.active_fee_rule
      plan_installments(year: active&.custom_installments_starting_year, cents: active&.custom_installments_cents,
        issue: active&.custom_installments_issue, comment: active&.custom_installments_comment,
        payment_method: active&.custom_installments_payment_method)
    end

    # A new planned plan starting from the standard plan of the person's role
    # (the plan Person#yme_list falls back to), not saved; no issue, no
    # comment.
    def plan_installments_from_standard
      raw = standard_payment_plan&.raw_installments_eur
      plan_installments(year: raw.presence && raw[0].to_i,
        cents: raw.presence && raw[1..].map { |eur| (BigDecimal(eur.to_s) * 100).round.to_i },
        issue: nil, comment: nil, payment_method: standard_payment_plan&.payment_method)
    end

    # The standard plan of the person's role, by direct debit.
    def standard_payment_plan
      @standard_payment_plan ||= WsjrdpPaymentPlan.kept.find_by(wsjrdp_role: person.wsjrdp_role,
        single_payment: person.early_payer || false, payment_method: DEFAULT_PAYMENT_METHOD)
    end

    # The plans that were active, newest activation first: the active rule
    # and the ones it replaced -- not the discarded plans, nor rules with a
    # reduction alone.
    def installments_history
      Wsj27RdpFeeRule.with_plan.where(people_id: person.id).where.not(activated_at: nil)
        .includes(:activated_by, :deleted_by).order(activated_at: :desc, id: :desc)
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

    private

    def plan_installments(year:, cents:, issue:, comment:, payment_method:)
      rule = person.ensure_planned_fee_rule
      rule.custom_installments_starting_year = year
      rule.custom_installments_cents = cents
      rule.custom_installments_issue = issue
      rule.custom_installments_comment = comment
      rule.custom_installments_payment_method = payment_method
      rule
    end
  end
end
