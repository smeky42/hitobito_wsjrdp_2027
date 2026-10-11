# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The Zahlungscodes dataset (Fin::PaymentReferencesController) for the generic
# CNF filter (doc/wsjrdp/generic_filter_builder.md): plain SQL on
# wsjrdp_payment_references, the notice count a correlated subquery
# (Fin::PaymentReferencesColumns::NOTICE_COUNT_SQL).
#
# The code is searched in its electronic AND its printed form, so a code typed
# with or without the spaces between its groups is found. The two timestamps
# are filtered as local dates: "im Bereich" and "im Monat" then include their
# last day.
#
# The quick filters (PRESETS): the status as an exclusive group -- one status
# or all of them, as the page's counts read -- and the codes some payment
# notice uses.
module Fin::PaymentReferencesFilterSchema
  extend Wsjrdp::Filtering::FilterSchema

  STATUS_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    WsjrdpPaymentReference::STATUSES.map { |status| [status, I18n.t("fin.payment_references.counts.#{status}")] }
  })

  ORIGIN_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    WsjrdpPaymentReference::ORIGINS.map { |origin| [origin, I18n.t("fin.payment_references.origins.#{origin}")] }
  })

  # The count is a number; "≠ 0" comes first, "has notices at all".
  COUNT_OPERATORS = %i[nonzero between lte gte lt gt eq].freeze

  DATE_OPERATORS = %i[gte lt between in_month in_year].freeze

  # The printed form of the code (Wsjrdp2027::PaymentCode.format_code): groups
  # of four, separated by a space.
  def self.printed_code_sql
    Arel.sql("TRIM(REGEXP_REPLACE(wsjrdp_payment_references.payment_code, '(.{4})', '\\1 ', 'g'))")
  end

  # A timestamp column as the date it falls on in the application's time zone.
  def self.local_date(column)
    zone = WsjrdpPaymentReference.connection.quote(Time.zone.tzinfo.name)
    Arel.sql("((wsjrdp_payment_references.#{column} AT TIME ZONE 'UTC') AT TIME ZONE #{zone})::date")
  end

  SCHEMA = Wsjrdp::Filtering::Schema.define do |s|
    s.attribute key: :payment_code, short_key: :q, label: "Code",
      type: Wsjrdp::Filtering::Types::TEXT, operators: Fin::DatevBookingsFilterSchema::TEXT_OPERATORS,
      column: ->(t) { [t[:payment_code], printed_code_sql] }
    s.attribute key: :status, short_key: :st, label: "Status",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: :status, options: STATUS_OPTIONS
    s.attribute key: :origin, short_key: :or, label: "Herkunft",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: :origin, options: ORIGIN_OPTIONS
    s.attribute key: :created_at, short_key: :ca, label: "Erzeugt",
      type: Wsjrdp::Filtering::Types::DATE, operators: DATE_OPERATORS,
      column: ->(_t) { local_date(:created_at) }
    # NULL until the code is handed out.
    s.attribute key: :assigned_at, short_key: :aa, label: "Vergeben",
      type: Wsjrdp::Filtering::Types::DATE, operators: DATE_OPERATORS + %i[present blank],
      column: ->(_t) { local_date(:assigned_at) }
    s.attribute key: :notice_count, short_key: :nc, label: "Zahlungsankündigungen",
      type: Wsjrdp::Filtering::Types::DECIMAL, operators: COUNT_OPERATORS,
      column: ->(_t) { Arel.sql(Fin::PaymentReferencesColumns::NOTICE_COUNT_SQL) }
  end

  # The members' labels are fin.payment_references.counts.* -- written out,
  # because the constant is built when the class loads.
  PRESETS = [
    {group: "status", attribute: "status", operator: "in", exclusive: true,
     members: [{key: "available", label: "verfügbar", value: "available"},
       {key: "assigned", label: "vergeben", value: "assigned"},
       {key: "void", label: "ungültig", value: "void"}]},
    {key: "with_notices", label: "mit Zahlungsankündigung", slots: [[["notice_count", "nonzero"]]]}
  ].freeze

  def self.bound(except: nil)
    SCHEMA.bind(WsjrdpPaymentReference.all, except: except)
  end
end
