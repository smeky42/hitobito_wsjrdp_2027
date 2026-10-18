# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The Sammler dataset (Fin::DirectDebitPaymentInfosController) for the generic
# CNF filter, over Fin::PaymentQueries.payment_infos. The quick filters: the
# Sammler with returns, and those without the bank's credit.
module Fin::DirectDebitPaymentInfosFilterSchema
  extend Wsjrdp::Filtering::FilterSchema

  YES_NO = Fin::PaymentOrdersFilterSchema::YES_NO

  ORDER_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    WsjrdpPaymentInitiation.where(id: WsjrdpDirectDebitPaymentInfo.select(:payment_initiation_id))
      .order(id: :desc).map { |order| [order.id, "##{order.id} vom #{order.created_at&.strftime("%d.%m.%Y")}"] }
  })

  SEQUENCE_OPTIONS = Fin::PaymentOrdersFilterSchema::SEQUENCE_OPTIONS

  SCHEMA = Wsjrdp::Filtering::Schema.define do |s|
    s.attribute key: :order, short_key: :o, label: "Auftrag",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: :payment_initiation_id, options: ORDER_OPTIONS
    s.attribute key: :sequence, short_key: :seq, label: "Sequenz",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: :debit_sequence_type, options: SEQUENCE_OPTIONS
    s.attribute key: :collection_date, short_key: :cd, label: "Einzug",
      type: Wsjrdp::Filtering::Types::DATE, operators: %i[gte lt between in_month in_year],
      column: :requested_collection_date
    s.attribute key: :returns, short_key: :ret, label: "Mit Retouren",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: ->(_t) { Fin::PaymentOrdersFilterSchema.yes_no("returns.return_count > 0") }, options: YES_NO
    s.attribute key: :bank, short_key: :bk, label: "Mit Bankbuchung",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: ->(_t) { Fin::PaymentOrdersFilterSchema.yes_no("credits.credit_count > 0") }, options: YES_NO
  end

  PRESETS = [
    {group: "returns", attribute: "returns", operator: "in", exclusive: true,
     members: [{key: "with_returns", label: "mit Retouren", value: "ja", icon: "undo"}]},
    {group: "bank", attribute: "bank", operator: "in", exclusive: true,
     members: [{key: "without_credit", label: "ohne Bankbuchung", value: "nein", icon: "exclamation-triangle"}]}
  ].freeze

  def self.bound(except: nil)
    SCHEMA.bind(Fin::PaymentQueries.payment_infos, except: except)
  end
end
