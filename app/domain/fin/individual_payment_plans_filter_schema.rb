# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The Individuelle Ratenpläne dataset (Fin::IndividualPaymentPlansController) for
# the generic CNF filter (doc/wsjrdp/generic_filter_builder.md). It filters the
# PEOPLE before their rows are built, so every condition is SQL on `people`;
# the planned plan sits in wsj27_rdp_fee_rules and is reached by a subquery.
#
# A text search runs over names, issue and comment, of the active plan and of
# the planned one. Five attributes carry the quick filters (PRESETS): whether
# a plan is planned, whether the person is confirmed, the payment method of
# the active plan, whether the active plan's sum differs from the fee, and
# whether the person is behind (Fin::PaymentProgress, in SQL).
module Fin::IndividualPaymentPlansFilterSchema
  extend Wsjrdp::Filtering::FilterSchema

  YES_NO = Fin::FeeReductionsFilterSchema::YES_NO
  STATUS_OPTIONS = Fin::FeeReductionsFilterSchema::STATUS_OPTIONS
  PAYMENT_METHOD_OPTIONS = Wsjrdp::Filtering::Options.values(-> { Wsjrdp2027::ParticipationFee.payment_method_options })

  # The planned fee rule of the person, where it carries a plan.
  PLANNED_RULE = "FROM wsj27_rdp_fee_rules r WHERE r.people_id = people.id AND r.status = 'planned' " \
    "AND r.deleted_at IS NULL AND r.custom_installments_starting_year IS NOT NULL " \
    "AND r.custom_installments_cents IS NOT NULL"

  # The sum of the active plan's installments in cents; NULL without a plan.
  PLAN_SUM_CENTS = "(SELECT round(sum(x) * 100) FROM unnest(people.wsjrdp_raw_installments_eur[2:]) AS x)"

  # What came in: the person's accounting entries.
  PAID_CENTS = "(SELECT coalesce(sum(ae.amount_cents), 0) FROM accounting_entries ae " \
    "WHERE ae.subject_type = 'Person' AND ae.subject_id = people.id)"

  def self.yes_no(condition) = Fin::FeeReductionsFilterSchema.yes_no(condition)

  # What is due today, as Fin::PaymentProgress has it -- of the active plan
  # alone: by credit transfer its installments up to the last month due (its
  # due day passed); by direct debit those of the months before the current
  # one, and the current month's once the balance covers it already, once a
  # collection of the month exists (its SEPA file generated) or once one
  # announced for the month is a day or more past its date.
  def self.due_cents(today)
    "CASE WHEN people.wsjrdp_installments_payment_method = 'credit_transfer' THEN #{transfer_due_cents(today)} " \
      "ELSE #{debit_due_cents(today)} END"
  end

  def self.transfer_due_cents(today) = plan_cents_through(Fin::PaymentProgress.due_through(today))

  def self.debit_due_cents(today)
    current = Wsjrdp2027::YearMonth.new(today.year, today.month)
    through_current = plan_cents_through(current)
    "CASE WHEN #{PAID_CENTS} >= #{through_current} OR #{collection_in_month(today)} THEN #{through_current} " \
      "ELSE #{plan_cents_through(current + -1)} END"
  end

  # The active plan's installments up to a month: month i of the plan's
  # array (1 for January of its year) against the month's number.
  def self.plan_cents_through(year_month)
    "(SELECT coalesce(round(sum(x) * 100), 0) FROM unnest(people.wsjrdp_raw_installments_eur[2:]) " \
      "WITH ORDINALITY AS u(x, i) " \
      "WHERE people.wsjrdp_raw_installments_eur[1]::int * 12 + i - 1 <= #{year_month.year * 12 + year_month.month - 1})"
  end

  def self.collection_in_month(today)
    quote = ->(date) { "#{Person.connection.quote(date)}::date" }
    "EXISTS (SELECT 1 FROM wsjrdp_direct_debit_pre_notifications pn " \
      "WHERE pn.subject_type = 'Person' AND pn.subject_id = people.id AND pn.payment_status <> 'skipped' " \
      "AND pn.collection_date BETWEEN #{quote.call(today.beginning_of_month)} AND #{quote.call(today.end_of_month)} " \
      "AND (pn.payment_status = 'xml_generated' OR pn.collection_date < #{quote.call(today)}))"
  end

  def self.planned_rule(column) = Arel.sql("(SELECT r.#{column} #{PLANNED_RULE} LIMIT 1)")

  # The person's fee in cents, as Person#total_fee_cents reads it: the
  # generated column, rounded to cents.
  def self.fee_cents = "round(people.wsjrdp_total_fee * 100)"

  SCHEMA = Wsjrdp::Filtering::Schema.define do |s|
    s.attribute key: :search, short_key: :q, label: "Suche (Name, Vorgang, Kommentar)",
      type: Wsjrdp::Filtering::Types::TEXT, operators: Fin::DatevBookingsFilterSchema::TEXT_OPERATORS,
      column: ->(t) {
        [t[:first_name], t[:last_name], t[:nickname], t[:wsjrdp_installments_issue],
          t[:wsjrdp_installments_comment], planned_rule("custom_installments_issue"),
          planned_rule("custom_installments_comment")]
      }
    s.attribute key: :planned, short_key: :pl, label: "Geplanter Ratenplan",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: ->(_t) { yes_no("EXISTS (SELECT 1 #{PLANNED_RULE})") },
      options: YES_NO
    s.attribute key: :confirmed, short_key: :bs, label: "Bestätigt",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: ->(_t) { yes_no("people.status = 'confirmed'") },
      options: YES_NO
    s.attribute key: :status, short_key: :st, label: "Status",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: :status, options: STATUS_OPTIONS
    s.attribute key: :payment_method, short_key: :pm, label: "Zahlungsart",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: :wsjrdp_installments_payment_method, options: PAYMENT_METHOD_OPTIONS
    s.attribute key: :mismatch, short_key: :mm, label: "Plan ≠ Beitrag",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: ->(_t) { yes_no("#{PLAN_SUM_CENTS} IS NOT NULL AND #{PLAN_SUM_CENTS} <> #{fee_cents}") },
      options: YES_NO
    s.attribute key: :behind, short_key: :vz, label: "In Verzug",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: ->(_t) { yes_no("#{PAID_CENTS} < #{due_cents(Date.current)}") },
      options: YES_NO
  end

  # The quick filters: five exclusive groups, the unrestricted button (an
  # asterisk, "ohne Einschränkung") in front of each.
  PRESETS = [
    {group: "planned", attribute: "planned", operator: "in", exclusive: true,
     members: [{key: "planned", label: "geplant", value: "ja", icon: "clock"},
       {key: "not_planned", label: "ohne Plan", value: "nein"}]},
    {group: "confirmed", attribute: "confirmed", operator: "in", exclusive: true,
     members: [{key: "confirmed", label: "bestätigt", value: "ja"},
       {key: "not_confirmed", label: "nicht bestätigt", value: "nein"}]},
    {group: "payment_method", attribute: "payment_method", operator: "in", exclusive: true,
     members: [{key: "direct_debit", label: "Lastschrift", value: "direct_debit", icon: "file-signature"},
       {key: "credit_transfer", label: "Überweisung", value: "credit_transfer", icon: "landmark"}]},
    {group: "mismatch", attribute: "mismatch", operator: "in", exclusive: true,
     members: [{key: "mismatch", label: "Plan ≠ Beitrag", value: "ja", icon: "exclamation-triangle"}]},
    {group: "behind", attribute: "behind", operator: "in", exclusive: true,
     members: [{key: "behind", label: "in Verzug", value: "ja"}]}
  ].freeze

  def self.bound(except: nil)
    SCHEMA.bind(Person.all, except: except)
  end
end
