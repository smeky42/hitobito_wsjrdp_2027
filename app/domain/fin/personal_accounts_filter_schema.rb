# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The Kreditoren (personal accounts) dataset for the generic CNF filter
# (doc/wsjrdp/generic_filter_builder.md): attribute declarations and the
# request-time binding, the second consumer of the filter-schema protocol next
# to Fin::DatevBookingsFilterSchema.
#
# The base relation is WsjrdpPersonalAccount.with_booking_summary, so `Saldo`
# and `Buchungen` are ordinary columns the compiler can filter on -- the page
# never filters an Array in Ruby.
module Fin::PersonalAccountsFilterSchema
  extend Wsjrdp::Filtering::FilterSchema

  # Moss knows an account as active or deactivated; an account it does not know
  # at all has moss_status NULL. NULL counts as INAKTIV here (the column's own
  # comment says the same), which is why the attribute filters on
  # COALESCE(moss_status, 'deactivated') rather than on the raw column -- the
  # same expression the table's "Moss Status" cell and its sort use.
  MOSS_STATUS_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    [[WsjrdpPersonalAccount::STATUS_ACTIVE, I18n.t("fin.moss_status.active")],
      [WsjrdpPersonalAccount::STATUS_DEACTIVATED, I18n.t("fin.moss_status.deactivated")]]
  })

  # All case variants of the text operators; the UI collapses each ci/cs pair
  # into one entry plus the "Groß-/Kleinschreibung" toggle.
  TEXT_OPERATORS = %i[
    contains contains_cs not_contains not_contains_cs eq eq_cs regex regex_cs
  ].freeze

  # What both Saldo variants accept and offer, in the editor's order. `≠ 0` is
  # what the "Nur mit Saldo ≠ 0" preset is made of and the first entry a user
  # sees, so a fresh Saldo condition starts on "has a balance at all"; the
  # comparisons follow.
  BALANCE_OPERATORS = %i[nonzero between lte gte lt gt eq].freeze

  # Declaration order = picker order. The long keys are the COLUMN keys of
  # Fin::BookkeepingSummaryColumns::PERSONAL_ACCOUNTS, so a condition and a
  # sorted header speak of the same thing.
  SCHEMA = Wsjrdp::Filtering::Schema.define do |s|
    # One text search over both name columns (the multi-column form of the text
    # type: a positive predicate matches in EITHER, "enthält nicht" in neither).
    s.attribute key: :name, short_key: :q, label: "Name",
      type: Wsjrdp::Filtering::Types::TEXT, operators: TEXT_OPERATORS,
      column: ->(t) { [t[:name], t[:short_name]] }
    # The Saldo as ONE picker entry with a sign toggle. The MAGNITUDE is the
    # default: a creditor's balance is negative as often as positive, so
    # "|Saldo| ≠ 0" ("has a balance at all") and "|Saldo| ≥ 100" are the
    # questions actually asked -- the signed variant answers "which side".
    s.attribute key: :booking_balance_abs, short_key: :bba, label: "|Saldo|",
      variant_group: "Saldo", sign: :absolute, type: Wsjrdp::Filtering::Types::DECIMAL,
      operators: BALANCE_OPERATORS, operand_min: 0,
      column: ->(t) { Arel::Nodes::NamedFunction.new("ABS", [t[:booking_balance]]) }
    s.attribute key: :booking_balance, short_key: :bb, label: "Saldo",
      variant_group: "Saldo", sign: :signed, type: Wsjrdp::Filtering::Types::DECIMAL,
      operators: BALANCE_OPERATORS,
      column: :booking_balance
    # A count, but the decimal type is the right one: its operand cast
    # (BigDecimal) compares exactly against an integer column, and the UI's
    # number input is what a count wants anyway. `≠ 0` leads for the same
    # reason as on the Saldo ("has bookings at all"); no sign toggle, a count
    # has no negative side.
    s.attribute key: :booking_count, short_key: :bc, label: "Buchungen",
      type: Wsjrdp::Filtering::Types::DECIMAL,
      operators: %i[nonzero between lte gte lt gt eq],
      column: :booking_count
    s.attribute key: :moss_status, short_key: :ms, label: "Moss Status",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: ->(t) {
        Arel::Nodes::NamedFunction.new("COALESCE",
          [t[:moss_status], Arel::Nodes.build_quoted(WsjrdpPersonalAccount::STATUS_DEACTIVATED)])
      },
      options: MOSS_STATUS_OPTIONS
  end

  # `except:` lets the host page hide attributes (the table's `exclude:`). The
  # base carries the booking summary, so every relation the compiler runs over
  # has the two aggregate columns -- Wsjrdp::Filtering::FilterSchema#compile
  # merges this base into whatever relation a host hands in.
  def self.bound(except: nil)
    SCHEMA.bind(WsjrdpPersonalAccount.with_booking_summary, except: except)
  end
end
