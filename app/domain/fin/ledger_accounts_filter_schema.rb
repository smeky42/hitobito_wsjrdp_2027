# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The Sachkonten dataset for the generic CNF filter
# (doc/wsjrdp/generic_filter_builder.md): attribute declarations and the
# request-time binding, one consumer of the filter-schema protocol next to
# Fin::DatevBookingsFilterSchema, Fin::MossTransactionsFilterSchema,
# Fin::CostCentersFilterSchema and Fin::PersonalAccountsFilterSchema.
#
# The base relation is WsjrdpLedgerAccount.with_booking_summary, so the booking
# totals are ordinary columns the compiler can filter on -- the page never
# filters an Array in Ruby.
module Fin::LedgerAccountsFilterSchema
  extend Wsjrdp::Filtering::FilterSchema

  # The Kontoart values that actually occur in the master data, each with its
  # German label (the same fin.account_kind.* translation the table cell and the
  # detail view show; an untranslated code falls back to itself). Read when the
  # catalog is rendered, so a chart import that brings a new kind offers it
  # without a code change.
  ACCOUNT_KIND_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    WsjrdpLedgerAccount.distinct.order(:account_kind).pluck(:account_kind)
      .map { |kind| [kind, I18n.t("fin.account_kind.#{kind}", default: kind)] }
  })

  # Moss knows an account as active or deactivated; one it does not know at all
  # has moss_status NULL. NULL counts as INAKTIV here (the column's own comment
  # says the same), which is why the attribute filters on
  # COALESCE(moss_status, 'deactivated') rather than on the raw column -- the
  # same expression the table's "Moss Status" cell and its sort use.
  MOSS_STATUS_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    [[WsjrdpLedgerAccount::STATUS_ACTIVE, I18n.t("fin.moss_status.active")],
      [WsjrdpLedgerAccount::STATUS_DEACTIVATED, I18n.t("fin.moss_status.deactivated")]]
  })

  # All case variants of the text operators, the same list the Buchungen page
  # offers (Fin::DatevBookingsFilterSchema::TEXT_OPERATORS), glob pair included:
  # an account name is exactly the kind of value one wants to match with
  # `Bank*` or `*Erlöse`. The UI collapses each ci/cs pair into one entry plus
  # the "Groß-/Kleinschreibung" toggle.
  TEXT_OPERATORS = Fin::DatevBookingsFilterSchema::TEXT_OPERATORS

  # Declaration order = picker order. The long keys are the COLUMN keys of
  # Fin::BookkeepingSummaryColumns::LEDGER_ACCOUNTS, so a condition and a sorted
  # header speak of the same thing.
  SCHEMA = Wsjrdp::Filtering::Schema.define do |s|
    # One text search over both name columns (the multi-column form of the text
    # type: a positive predicate matches in EITHER, "enthält nicht" in neither),
    # so a search for a Kurzbezeichnung finds its account as readily as a search
    # for the long Bezeichnung does.
    s.attribute key: :name, short_key: :q, label: "Name",
      type: Wsjrdp::Filtering::Types::TEXT, operators: TEXT_OPERATORS,
      column: ->(t) { [t[:name], t[:short_name]] }
    # The DATEV Kontenart, stored as its short code (BANK, EXPENSE, ...) and
    # offered as the German label. A plain column, not a COALESCE: account_kind
    # is NOT NULL and defaults to UNKNOWN.
    s.attribute key: :account_kind, short_key: :ak, label: "Kontoart",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: :account_kind, options: ACCOUNT_KIND_OPTIONS
    s.attribute key: :moss_status, short_key: :ms, label: "Moss Status",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: ->(t) {
        Arel::Nodes::NamedFunction.new("COALESCE",
          [t[:moss_status], Arel::Nodes.build_quoted(WsjrdpLedgerAccount::STATUS_DEACTIVATED)])
      },
      options: MOSS_STATUS_OPTIONS
  end

  # `except:` lets the host page hide attributes (the table's `exclude:`). The
  # base carries the booking summary, so every relation the compiler runs over
  # has the two aggregate columns -- Wsjrdp::Filtering::FilterSchema#compile
  # merges this base into whatever relation a host hands in.
  def self.bound(except: nil)
    SCHEMA.bind(WsjrdpLedgerAccount.with_booking_summary, except: except)
  end
end
