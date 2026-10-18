# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The Aufträge dataset (Fin::PaymentOrdersController) for the generic CNF
# filter (doc/wsjrdp/generic_filter_builder.md), over
# Fin::PaymentQueries.orders: its lateral joins (payment infos, returns, accounts)
# are ordinary columns here. The quick filters: the kind -- Lastschriften is
# where the Beiträge overview links to -- and the orders with returns.
module Fin::PaymentOrdersFilterSchema
  extend Wsjrdp::Filtering::FilterSchema

  KIND_LABELS = {
    WsjrdpPaymentInitiation::DIRECT_DEBIT => "Lastschrift",
    WsjrdpPaymentInitiation::CREDIT_TRANSFER => "Überweisung",
    WsjrdpPaymentInitiation::CONFLICT => "widersprüchlich",
    WsjrdpPaymentInitiation::UNKNOWN => "unbekannt"
  }.freeze

  KIND_OPTIONS = Wsjrdp::Filtering::Options.values(-> { KIND_LABELS.to_a })
  YES_NO = Wsjrdp::Filtering::Options.values(-> { [%w[ja ja], %w[nein nein]] })

  ACCOUNT_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    WsjrdpFinAccount.where(deleted_at: nil).order(:short_name, :id)
      .map { |account| [account.id, account.short_name.presence || account.account_identification] }
  })

  STATUS_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    WsjrdpPaymentInitiation.distinct.order(:status).pluck(:status).compact.map { |status| [status, status] }
  })

  SEQUENCE_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    WsjrdpDirectDebitPaymentInfo.distinct.order(:debit_sequence_type).pluck(:debit_sequence_type).compact
      .map { |type| [type, type] }
  })

  def self.yes_no(condition) = Arel.sql("CASE WHEN #{condition} THEN 'ja' ELSE 'nein' END")

  SCHEMA = Wsjrdp::Filtering::Schema.define do |s|
    s.attribute key: :kind, short_key: :kd, label: "Typ",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: ->(_t) { Arel.sql(WsjrdpPaymentInitiation.kind_sql) }, options: KIND_OPTIONS
    s.attribute key: :account, short_key: :acc, label: "Konto",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: ->(_t) { Arel.sql("accounts.id") }, options: ACCOUNT_OPTIONS
    s.attribute key: :status, short_key: :st, label: "Status",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: :status, options: STATUS_OPTIONS
    s.attribute key: :execution_date, short_key: :ex, label: "Ausführung",
      type: Wsjrdp::Filtering::Types::DATE, operators: %i[gte lt between in_month in_year present blank],
      column: ->(_t) { Arel.sql("infos.first_date") }
    s.attribute key: :created_at, short_key: :ca, label: "Erstellt",
      type: Wsjrdp::Filtering::Types::DATE, operators: %i[gte lt between in_month in_year],
      column: ->(_t) { Arel.sql("wsjrdp_payment_initiations.created_at::date") }
    s.attribute key: :sequence, short_key: :seq, label: "Sequenz",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: ->(_t) {
        Arel.sql("(SELECT MIN(seq.debit_sequence_type) FROM wsjrdp_direct_debit_payment_infos seq " \
          "WHERE seq.payment_initiation_id = wsjrdp_payment_initiations.id)")
      }, options: SEQUENCE_OPTIONS
    s.attribute key: :returns, short_key: :ret, label: "Mit Retouren",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: ->(_t) { yes_no("returns.return_count > 0") }, options: YES_NO
    s.attribute key: :bank, short_key: :bk, label: "Mit Bankbuchung",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: ->(_t) { yes_no("credits.credit_count > 0") }, options: YES_NO
    s.attribute key: :message_identification, short_key: :q, label: "Nachrichten-ID",
      type: Wsjrdp::Filtering::Types::TEXT, operators: Fin::DatevBookingsFilterSchema::TEXT_OPERATORS,
      column: :message_identification
  end

  PRESETS = [
    {group: "kind", attribute: "kind", operator: "in", exclusive: true,
     members: [{key: "direct_debits", label: "Lastschriften", value: WsjrdpPaymentInitiation::DIRECT_DEBIT,
                icon: "file-signature"},
       {key: "credit_transfers", label: "Überweisungen", value: WsjrdpPaymentInitiation::CREDIT_TRANSFER,
        icon: "landmark"}]},
    {group: "returns", attribute: "returns", operator: "in", exclusive: true,
     members: [{key: "with_returns", label: "mit Retouren", value: "ja", icon: "undo"}]}
  ].freeze

  def self.bound(except: nil)
    SCHEMA.bind(Fin::PaymentQueries.orders, except: except)
  end
end
