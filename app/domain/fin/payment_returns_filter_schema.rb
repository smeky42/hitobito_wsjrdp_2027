# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The Rückläufer dataset (Fin::PaymentReturnsController) for the generic CNF
# filter, over Fin::PaymentQueries.returns (bank transactions). The quick
# filters: the returns no debit and no order can be assigned to, those that
# do not link their debit, and those without an accounting entry.
module Fin::PaymentReturnsFilterSchema
  extend Wsjrdp::Filtering::FilterSchema

  YES_NO = Fin::PaymentOrdersFilterSchema::YES_NO

  PERSON_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    Person.where(id: returns.where(subject_type: "Person").select(:subject_id))
      .includes(:roles).order(:last_name, :first_name, :id)
      .map { |person| [person.id, person.short_full_name_with_nickname, "#{person.short_payment_role} #{person.id}"] }
  }, id_search: true)

  REASON_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    Fin::ReturnReasons.options(returns.distinct.pluck(:return_reason))
  })

  STATUS_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    Settings.return_debit_status.to_h.except(:none).map { |value, label| [value.to_s, label] }
  })

  SCHEMA = Wsjrdp::Filtering::Schema.define do |s|
    s.attribute key: :search, short_key: :q, label: "Suche (Name, Verwendungszweck, End-to-End-ID, Mandat)",
      type: Wsjrdp::Filtering::Types::TEXT, operators: Fin::DatevBookingsFilterSchema::TEXT_OPERATORS,
      column: ->(t) {
        [Arel.sql("people.first_name"), Arel.sql("people.last_name"), Arel.sql("people.nickname"),
          t[:description], t[:endtoend_id], t[:mandate_id]]
      }
    s.attribute key: :person, short_key: :pid, label: "Person",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in],
      column: :subject_id, options: PERSON_OPTIONS,
      operator_labels: {in: {label_many: "ist eine von"}, not_in: {label_many: "ist keine von"}}
    s.attribute key: :reason, short_key: :rs, label: "Grund",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: :return_reason, options: REASON_OPTIONS
    s.attribute key: :date, short_key: :d, label: "Datum",
      type: Wsjrdp::Filtering::Types::DATE, operators: %i[gte lt between in_month in_year],
      column: ->(_t) { Arel.sql("COALESCE(wsjrdp_camt_transactions.booking_date, wsjrdp_camt_transactions.value_date)") }
    s.attribute key: :assigned, short_key: :as, label: "Zuordenbar",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: ->(_t) { Fin::PaymentOrdersFilterSchema.yes_no("#{Fin::PaymentQueries::RETURN_ORDER_SQL} IS NOT NULL") },
      options: YES_NO
    s.attribute key: :linked, short_key: :ln, label: "Mit Einzug verknüpft",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: ->(_t) {
        Fin::PaymentOrdersFilterSchema.yes_no("wsjrdp_camt_transactions.direct_debit_pre_notification_id IS NOT NULL")
      }, options: YES_NO
    s.attribute key: :entry, short_key: :en, label: "Beitragsbuchung",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: ->(_t) { Fin::PaymentOrdersFilterSchema.yes_no("entry.id IS NOT NULL") }, options: YES_NO
    s.attribute key: :status, short_key: :st, label: "Bearbeitung",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: ->(_t) { Arel.sql(Fin::PaymentReturnsColumns::STATUS_SQL) }, options: STATUS_OPTIONS
  end

  PRESETS = [
    {group: "assigned", attribute: "assigned", operator: "in", exclusive: true,
     members: [{key: "unassigned", label: "nicht zuordenbar", value: "nein", icon: "exclamation-triangle"}]},
    {group: "linked", attribute: "linked", operator: "in", exclusive: true,
     members: [{key: "unlinked", label: "nicht verknüpft", value: "nein", icon: "unlink"}]},
    {group: "entry", attribute: "entry", operator: "in", exclusive: true,
     members: [{key: "without_entry", label: "ohne Beitragsbuchung", value: "nein", icon: "exclamation-triangle"}]}
  ].freeze

  def self.returns
    WsjrdpCamtTransaction.where(Arel.sql(Fin::PaymentQueries.return_condition("wsjrdp_camt_transactions")))
  end

  def self.bound(except: nil)
    SCHEMA.bind(Fin::PaymentQueries.returns, except: except)
  end
end
