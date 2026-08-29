# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The DATEV bookings dataset for the generic CNF filter
# (doc/wsjrdp/generic_filter_builder.md): attribute declarations and the
# request-time binding. This file is the ONLY bookings-specific part of the
# filter -- everything else is Wsjrdp::Filtering::*.
#
# It is a FILTER SCHEMA (Wsjrdp::Filtering::FilterSchema): a table names it once in
# its policy (`filter: {schema: Fin::DatevBookingsFilterSchema, ...}`) and the resolved
# state does all decoding, strict fixed-slot parsing and compiling through it.
module Fin::DatevBookingsFilterSchema
  extend Wsjrdp::Filtering::FilterSchema

  # Konto and Gegenkonto can each hold a ledger account OR a supplier
  # (700xxx), so both label sources are merged for both attributes. All option
  # sets are small enough to ship inline in the catalog (lazy: computed when
  # the catalog is rendered, never at boot).
  #
  # The picker only accepts values it actually renders (no free-text entry), so
  # a third source is unioned in: every account/Gegenkonto number that OCCURS in
  # the bookings. Otherwise a creditor used in a booking but not (yet) seeded
  # into wsjrdp_personal_accounts -- and barred from wsjrdp_ledger_accounts by the
  # 7xxxxx CHECK constraint -- would have no option row and be unselectable.
  ACCOUNT_OPTIONS = Wsjrdp::Filtering::Options.merge(
    Wsjrdp::Filtering::Options.from(-> { WsjrdpLedgerAccount.order(:number) },
      value: :number, label: ->(a) { "#{a.number} #{a.name}" }),
    Wsjrdp::Filtering::Options.from(-> { WsjrdpPersonalAccount.order(:number) },
      value: :number, label: ->(s) { "#{s.number} #{s.name}" }),
    Wsjrdp::Filtering::Options.values(-> {
      names = WsjrdpLedgerAccount.pluck(:number, :name).to_h
        .merge(WsjrdpPersonalAccount.pluck(:number, :name).to_h)
      (DatevBooking.distinct.pluck(:account_number) +
        DatevBooking.distinct.pluck(:offsetting_account_number))
        .compact.uniq.sort
        .map { |n| [n, names[n].present? ? "#{n} #{names[n]}" : n] }
    })
  )

  # ONE option list for both cost-center attributes: every cost center of the
  # master data (with its name), plus any number that occurs in a booking's
  # primary or secondary cost center without being in the master data -- so the
  # two pickers offer the same list and no booked value is unselectable.
  COST_CENTER_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    names = WsjrdpCostCenter.order(:number).pluck(:number, :name).to_h
    booked = DatevBooking.where.not(cost_center_number: nil).distinct.pluck(:cost_center_number) +
      DatevBooking.where.not(secondary_cost_center_number: nil).distinct.pluck(:secondary_cost_center_number)
    names.map { |n, name| [n, name.present? ? "#{n} #{name}" : n] } +
      (booked.uniq - names.keys).sort.map { |n| [n, n] }
  })

  # The base currency is always EUR, so the meaningful filter is the transaction
  # currency each booking was made in (NOT NULL, EUR for the majority): EUR and
  # every foreign currency in the data are offered.
  TRANSACTION_CURRENCY_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    DatevBooking.distinct.order(:transaction_currency).pluck(:transaction_currency).map { |c| [c, c] }
  })

  SPHERE_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    DatevBooking.where.not(sphere_number: nil)
      .distinct.order(:sphere_number).pluck(:sphere_number).map { |n| [n, n] }
  })

  FINANCIAL_YEAR_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    DatevBookingBatch.where.not(financial_year_start: nil)
      .distinct.pluck(Arel.sql("EXTRACT(YEAR FROM financial_year_start)::int"))
      .compact.sort.reverse.map { |y| [y.to_s, y.to_s] }
  })

  BATCH_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    DatevBookingBatch.order(period_to: :desc, label: :asc)
      .map { |b| [b.id.to_s, [b.primanota_number, b.label].compact.join(" · ")] }
  })

  # All case variants of the text operators; the UI collapses each ci/cs pair
  # into one entry plus the "Groß-/Kleinschreibung" toggle.
  TEXT_OPERATORS = %i[
    contains contains_cs not_contains not_contains_cs glob glob_cs eq eq_cs regex regex_cs
  ].freeze

  # The amount attributes accept and offer the whole comparison set; the range
  # comes first, so a fresh Betrag condition starts on "im Bereich".
  AMOUNT_OPERATORS = %i[between lte gte lt gt eq].freeze

  # Declaration order = picker order: Suche first, then Kostenrechnung, then
  # the rest. Sphäre and Beitragsbuchung stay declared but are excluded by the
  # bookings controller (see .bound / bind(except:)).
  #
  # Batch-backed attributes (Geschäftsjahr, Buchungsstapel) live on
  # datev_booking_batches; their column lambdas return the JOINED table's
  # columns, so every relation the compiler runs over must carry
  # left_joins(:batch) -- see .bound, which is where that join lives, and
  # Wsjrdp::Filtering::FilterSchema#compile, which merges it in.
  SCHEMA = Wsjrdp::Filtering::Schema.define do |s|
    # Text search as one picker entry ("Textsuche") with three sub-variants
    # (variant_group, §2.2); the first member (Buchungstext & Belege, the widest
    # one) is the default.
    s.attribute key: :text_any, short_key: :qa, label: "Buchungstext & Belege",
      variant_group: "Textsuche", type: Wsjrdp::Filtering::Types::TEXT, operators: TEXT_OPERATORS,
      column: ->(t) {
        [t[:posting_text], t[:original_posting_text], t[:document_field_1], t[:document_field_2]]
      }
    s.attribute key: :text, short_key: :q, label: "Buchungstext",
      variant_group: "Textsuche", type: Wsjrdp::Filtering::Types::TEXT, operators: TEXT_OPERATORS,
      column: ->(t) { [t[:posting_text], t[:original_posting_text]] }
    s.attribute key: :text_document, short_key: :qb, label: "Belege",
      variant_group: "Textsuche", type: Wsjrdp::Filtering::Types::TEXT, operators: TEXT_OPERATORS,
      column: ->(t) { [t[:document_field_1], t[:document_field_2]] }
    s.attribute key: :cost_center, short_key: :cc, label: "Kostenstelle", group: "Kostenrechnung",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in present blank],
      column: :cost_center_number, options: COST_CENTER_OPTIONS
    s.attribute key: :secondary_cost_center, short_key: :cc2, label: "Sekundäre Kostenstelle",
      group: "Kostenrechnung", type: Wsjrdp::Filtering::Types::REFERENCE,
      operators: %i[in not_in present blank],
      column: :secondary_cost_center_number, options: COST_CENTER_OPTIONS
    s.attribute key: :sphere, short_key: :sph, label: "Sphäre", group: "Kostenrechnung",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in present blank],
      column: :sphere_number, options: SPHERE_OPTIONS
    # The amount as ONE picker entry ("Betrag") with a sign toggle: the signed
    # booking value (default) or its magnitude. A signed base amount is
    # negative for outgoing money, so "|Betrag| ≥ 1000" is how one asks for big
    # bookings in either direction.
    s.attribute key: :amount, short_key: :amt, label: "Betrag", group: "Beträge & Daten",
      variant_group: "Betrag", sign: :signed, type: Wsjrdp::Filtering::Types::DECIMAL,
      operators: AMOUNT_OPERATORS,
      column: :signed_base_amount
    s.attribute key: :amount_abs, short_key: :amta, label: "|Betrag|", group: "Beträge & Daten",
      variant_group: "Betrag", sign: :absolute, type: Wsjrdp::Filtering::Types::DECIMAL,
      operators: AMOUNT_OPERATORS, operand_min: 0,
      column: ->(t) { Arel::Nodes::NamedFunction.new("ABS", [t[:signed_base_amount]]) }
    # The same picker entry over the amount AS BOOKED, in the booking's own
    # currency: a PLN invoice is found by its PLN figure, whereas "Betrag"
    # answers in EUR (the base currency) for every booking. Both pairs carry the
    # same value on an EUR booking, so this one is what the foreign-currency
    # bookings are asked about.
    s.attribute key: :amount_original, short_key: :amo, label: "Betrag (Original-Währung)",
      group: "Beträge & Daten", variant_group: "Betrag (Original-Währung)", sign: :signed,
      type: Wsjrdp::Filtering::Types::DECIMAL, operators: AMOUNT_OPERATORS,
      column: :signed_transaction_amount
    s.attribute key: :amount_original_abs, short_key: :amoa, label: "|Betrag (Original-Währung)|",
      group: "Beträge & Daten", variant_group: "Betrag (Original-Währung)", sign: :absolute,
      type: Wsjrdp::Filtering::Types::DECIMAL, operators: AMOUNT_OPERATORS, operand_min: 0,
      column: ->(t) { Arel::Nodes::NamedFunction.new("ABS", [t[:signed_transaction_amount]]) }
    # transaction_currency is the currency each booking was made in (NOT NULL,
    # EUR for the majority), so EUR and any foreign currency are both selectable.
    # It names the currency the "Betrag (Original-Währung)" pair counts in.
    s.attribute key: :transaction_currency, short_key: :cur, label: "Original-Währung",
      group: "Beträge & Daten", type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in],
      column: :transaction_currency, options: TRANSACTION_CURRENCY_OPTIONS
    s.attribute key: :booking_date, short_key: :bd, label: "Buchungsdatum", group: "Beträge & Daten",
      type: Wsjrdp::Filtering::Types::DATE, operators: %i[gte lt between in_month in_year],
      column: :booking_date
    s.attribute key: :service_date, short_key: :sd, label: "Leistungsdatum", group: "Beträge & Daten",
      type: Wsjrdp::Filtering::Types::DATE, operators: %i[gte lt between in_month in_year present blank],
      column: :service_date
    # Konto/Gegenkonto are NOT NULL -> presence operators simply not listed.
    s.attribute key: :konto, short_key: :k, label: "Konto", group: "Konten",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in],
      column: :account_number, options: ACCOUNT_OPTIONS
    s.attribute key: :offsetting_account, short_key: :gk, label: "Gegenkonto", group: "Konten",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in],
      column: :offsetting_account_number, options: ACCOUNT_OPTIONS
    # Either side of the booking (multi-column reference: `ist` matches if
    # Konto OR Gegenkonto is in the set, `ist nicht` if neither is).
    s.attribute key: :any_account, short_key: :kgk, label: "Konto oder Gegenkonto", group: "Konten",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in],
      column: ->(t) { [t[:account_number], t[:offsetting_account_number]] },
      options: ACCOUNT_OPTIONS
    s.attribute key: :financial_year, short_key: :fy, label: "Geschäftsjahr", group: "Sonstiges",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in],
      column: ->(_t) { DatevBookingBatch.arel_table[:financial_year_start].extract("year") },
      options: FINANCIAL_YEAR_OPTIONS
    s.attribute key: :batch, short_key: :st, label: "Buchungsstapel", group: "Sonstiges",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in],
      column: :datev_booking_batch_id, options: BATCH_OPTIONS
    # Whether the booking is linked to a Beitragsbuchung (accounting entry).
    # Presence-only atom; by default NOT usable (the bookings page excludes it),
    # enabled on the reconciliation pages.
    # The link lives on the entry now; a correlated subquery keeps this a plain
    # present/blank atom without joining accounting_entries into every query.
    s.attribute key: :accounting_entry, short_key: :ae, label: "Beitragsbuchung",
      group: "Sonstiges", type: Wsjrdp::Filtering::Types::REFERENCE,
      operators: %i[present blank],
      column: ->(t) {
        ae = AccountingEntry.arel_table
        Arel::Nodes::Grouping.new(
          ae.project(ae[:id]).where(ae[:datev_booking_id].eq(t[:id])).take(1)
        )
      }
  end

  # `except:` lets the host page hide attributes (the table's `exclude:`).
  # The base carries the batch join so the batch-backed attributes
  # (financial_year / batch) are filterable on any relation derived
  # from it -- FilterSchema#compile merges this base into whatever relation a host
  # hands in, so no host repeats the join.
  def self.bound(except: nil)
    SCHEMA.bind(DatevBooking.left_joins(:batch), except: except)
  end
end
