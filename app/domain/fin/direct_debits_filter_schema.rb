# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The Einzüge dataset (Fin::DirectDebitsController, the Einzüge section of an
# order's page) for the generic CNF filter, over Fin::PaymentQueries.debits.
# The quick filters: the debits with returns, the skipped ones and those
# whose amount differs from the announced one.
module Fin::DirectDebitsFilterSchema
  extend Wsjrdp::Filtering::FilterSchema

  TABLE = "wsjrdp_direct_debit_pre_notifications"
  YES_NO = Fin::PaymentOrdersFilterSchema::YES_NO

  PERSON_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    Person.where(id: WsjrdpDirectDebitPreNotification.where(subject_type: "Person").select(:subject_id))
      .includes(:roles).order(:last_name, :first_name, :id)
      .map { |person| [person.id, person.short_full_name_with_nickname, "#{person.short_payment_role} #{person.id}"] }
  }, id_search: true)

  ORDER_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    WsjrdpPaymentInitiation.where(id: WsjrdpDirectDebitPreNotification.select(:payment_initiation_id))
      .order(id: :desc).map { |order| [order.id, "##{order.id} vom #{order.created_at&.strftime("%d.%m.%Y")}"] }
  })

  # The statuses a debit passes through; the presets need "skipped" offered
  # even before a debit was skipped.
  STATUSES = %w[pre_notified xml_generated skipped].freeze

  # The values of a column that occur, after `known` ones.
  def self.distinct_options(column, known: [])
    Wsjrdp::Filtering::Options.values(-> {
      values = known + WsjrdpDirectDebitPreNotification.distinct.order(column).pluck(column).compact
      values.uniq.map { |value| [value, I18n.t("fin.payments.statuses.#{value}", default: value.to_s)] }
    })
  end

  def self.yes_no(condition) = Fin::PaymentOrdersFilterSchema.yes_no(condition)

  SCHEMA = Wsjrdp::Filtering::Schema.define do |s|
    s.attribute key: :search, short_key: :q, label: "Suche (Name, Kontoinhaber, Verwendungszweck, Mandat)",
      type: Wsjrdp::Filtering::Types::TEXT, operators: Fin::DatevBookingsFilterSchema::TEXT_OPERATORS,
      column: ->(t) {
        [Arel.sql("people.first_name"), Arel.sql("people.last_name"), Arel.sql("people.nickname"),
          t[:dbtr_name], t[:description], t[:mandate_id], t[:endtoend_id]]
      }
    s.attribute key: :person, short_key: :pid, label: "Person",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in],
      column: :subject_id, options: PERSON_OPTIONS,
      operator_labels: {in: {label_many: "ist eine von"}, not_in: {label_many: "ist keine von"}}
    s.attribute key: :order, short_key: :o, label: "Auftrag",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: :payment_initiation_id, options: ORDER_OPTIONS
    s.attribute key: :status, short_key: :st, label: "Status",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: :payment_status, options: distinct_options(:payment_status, known: STATUSES)
    s.attribute key: :role, short_key: :rl, label: "Bezahlungs-Rolle",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: :payment_role, options: Wsjrdp::Filtering::Options.values(-> {
        WsjrdpDirectDebitPreNotification.distinct.order(:payment_role).pluck(:payment_role).compact
          .map { |role| [role, Fin::PaymentRoles.label(role)] }
      })
    s.attribute key: :sequence, short_key: :seq, label: "Sequenz",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: :debit_sequence_type, options: distinct_options(:debit_sequence_type)
    s.attribute key: :collection_date, short_key: :cd, label: "Einzug",
      type: Wsjrdp::Filtering::Types::DATE, operators: %i[gte lt between in_month in_year],
      column: :collection_date
    s.attribute key: :amount, short_key: :a, label: "Betrag (€)",
      type: Wsjrdp::Filtering::Types::DECIMAL, operators: %i[eq gte gt lt lte between],
      column: ->(_t) { Arel.sql("(#{TABLE}.amount_cents / 100.0)") }
    s.attribute key: :returned, short_key: :ret, label: "Rücklastschrift",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: ->(_t) { yes_no("returns.return_count > 0") }, options: YES_NO
    s.attribute key: :differs, short_key: :dif, label: "Betrag ≠ angekündigt",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: ->(_t) {
        yes_no("#{TABLE}.pre_notified_amount_cents IS NOT NULL AND " \
          "#{TABLE}.pre_notified_amount_cents <> #{TABLE}.amount_cents")
      }, options: YES_NO
  end

  PRESETS = [
    {group: "returned", attribute: "returned", operator: "in", exclusive: true,
     members: [{key: "returned", label: "Rückläufer", value: "ja", icon: "undo"}]},
    {group: "skipped", attribute: "status", operator: "in", exclusive: true,
     members: [{key: "skipped", label: "Übersprungen", value: "skipped"}]},
    {group: "differs", attribute: "differs", operator: "in", exclusive: true,
     members: [{key: "differs", label: "Betrag ≠ angekündigt", value: "ja", icon: "exclamation-triangle"}]}
  ].freeze

  def self.bound(except: nil)
    SCHEMA.bind(Fin::PaymentQueries.debits, except: except)
  end
end
