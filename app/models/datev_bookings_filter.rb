# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The DATEV bookings dataset for the generic CNF filter
# (doc/generic_filter_builder.md): attribute declarations, the hidden
# status=active condition, and the request-time binding. This file is the ONLY
# bookings-specific part of the filter -- everything else is Filtering::*.
module DatevBookingsFilter
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
  ACCOUNT_OPTIONS = Filtering::Options.merge(
    Filtering::Options.from(WsjrdpLedgerAccount.order(:number),
      value: :number, label: ->(a) { "#{a.number} #{a.name}" }),
    Filtering::Options.from(WsjrdpPersonalAccount.order(:number),
      value: :number, label: ->(s) { "#{s.number} #{s.name}" }),
    Filtering::Options.values(-> {
      names = WsjrdpLedgerAccount.pluck(:number, :name).to_h
        .merge(WsjrdpPersonalAccount.pluck(:number, :name).to_h)
      (DatevBooking.distinct.pluck(:account_number) +
        DatevBooking.distinct.pluck(:offsetting_account_number))
        .compact.uniq.sort
        .map { |n| [n, names[n].present? ? "#{n} #{names[n]}" : n] }
    })
  )

  COST_CENTER_OPTIONS = Filtering::Options.values(-> {
    names = WsjrdpCostCenter.pluck(:number, :name).to_h
    DatevBooking.where.not(cost_center_number: nil)
      .distinct.order(:cost_center_number).pluck(:cost_center_number)
      .map { |n| [n, names[n] ? "#{n} #{names[n]}" : n] }
  })

  SECONDARY_COST_CENTER_OPTIONS = Filtering::Options.values(-> {
    names = WsjrdpCostCenter.pluck(:number, :name).to_h
    DatevBooking.where.not(secondary_cost_center_number: nil)
      .distinct.order(:secondary_cost_center_number).pluck(:secondary_cost_center_number)
      .map { |n| [n, names[n] ? "#{n} #{names[n]}" : n] }
  })

  # The base currency is always EUR, so the meaningful filter is the transaction
  # currency each booking was made in (NOT NULL, EUR for the majority): EUR and
  # every foreign currency in the data are offered.
  TRANSACTION_CURRENCY_OPTIONS = Filtering::Options.values(-> {
    DatevBooking.distinct.order(:transaction_currency).pluck(:transaction_currency).map { |c| [c, c] }
  })

  SPHERE_OPTIONS = Filtering::Options.values(-> {
    DatevBooking.where.not(sphere_number: nil)
      .distinct.order(:sphere_number).pluck(:sphere_number).map { |n| [n, n] }
  })

  PERIOD_OPTIONS = Filtering::Options.values(-> {
    DatevBooking.where.not(primanota_period: nil)
      .distinct.order(primanota_period: :desc).pluck(:primanota_period)
      .map { |d| [d.iso8601, d.strftime("%Y-%m")] }
  })

  # All case variants of the text operators; the UI collapses each ci/cs pair
  # into one entry plus the "Groß-/Kleinschreibung" toggle.
  TEXT_OPERATORS = %i[
    contains contains_cs not_contains not_contains_cs eq eq_cs regex regex_cs
  ].freeze

  # Declaration order = picker order: Suche first, then Kostenrechnung, then
  # the rest. Sphäre and Periode stay declared but are excluded by the
  # bookings controller (see .bound / bind(except:)).
  SCHEMA = Filtering::Schema.define do |s|
    # Text search as one picker entry ("Textsuche") with three sub-variants
    # (variant_group, §2.2); the first member (Buchungstext) is the default.
    s.attribute key: :text, short_key: :q, label: "Buchungstext",
      variant_group: "Textsuche", type: Filtering::Types::TEXT, operators: TEXT_OPERATORS,
      column: ->(t) { [t[:description], t[:original_posting_text]] }
    s.attribute key: :text_document, short_key: :qb, label: "Belege",
      variant_group: "Textsuche", type: Filtering::Types::TEXT, operators: TEXT_OPERATORS,
      column: ->(t) { [t[:document_field_1], t[:document_field_2]] }
    s.attribute key: :text_any, short_key: :qa, label: "Buchungstext & Belege",
      variant_group: "Textsuche", type: Filtering::Types::TEXT, operators: TEXT_OPERATORS,
      column: ->(t) {
        [t[:description], t[:original_posting_text], t[:document_field_1], t[:document_field_2]]
      }
    s.attribute key: :cost_center, short_key: :cc, label: "Kostenstelle", group: "Kostenrechnung",
      type: Filtering::Types::REFERENCE, operators: %i[in not_in present blank],
      column: :cost_center_number, options: COST_CENTER_OPTIONS
    s.attribute key: :secondary_cost_center, short_key: :cc2, label: "Sekundäre Kostenstelle",
      group: "Kostenrechnung", type: Filtering::Types::REFERENCE,
      operators: %i[in not_in present blank],
      column: :secondary_cost_center_number, options: SECONDARY_COST_CENTER_OPTIONS
    s.attribute key: :sphere, short_key: :sph, label: "Sphäre", group: "Kostenrechnung",
      type: Filtering::Types::REFERENCE, operators: %i[in not_in present blank],
      column: :sphere_number, options: SPHERE_OPTIONS
    s.attribute key: :amount, short_key: :amt, label: "Betrag", group: "Beträge & Daten",
      type: Filtering::Types::DECIMAL, operators: %i[eq gte lt between], column: :amount
    # transaction_currency is the currency each booking was made in (NOT NULL,
    # EUR for the majority), so EUR and any foreign currency are both selectable.
    s.attribute key: :transaction_currency, short_key: :cur, label: "Transaktionswährung",
      group: "Beträge & Daten", type: Filtering::Types::REFERENCE, operators: %i[in not_in],
      column: :transaction_currency, options: TRANSACTION_CURRENCY_OPTIONS
    s.attribute key: :booking_date, short_key: :bd, label: "Buchungsdatum", group: "Beträge & Daten",
      type: Filtering::Types::DATE, operators: %i[gte lt between in_month in_year],
      column: :booking_date
    s.attribute key: :service_date, short_key: :sd, label: "Leistungsdatum", group: "Beträge & Daten",
      type: Filtering::Types::DATE, operators: %i[gte lt between in_month in_year present blank],
      column: :service_date
    # Konto/Gegenkonto are NOT NULL -> presence operators simply not listed.
    s.attribute key: :konto, short_key: :k, label: "Konto", group: "Konten",
      type: Filtering::Types::REFERENCE, operators: %i[in not_in],
      column: :account_number, options: ACCOUNT_OPTIONS
    s.attribute key: :offsetting_account, short_key: :gk, label: "Gegenkonto", group: "Konten",
      type: Filtering::Types::REFERENCE, operators: %i[in not_in],
      column: :offsetting_account_number, options: ACCOUNT_OPTIONS
    # Either side of the booking (multi-column reference: `ist` matches if
    # Konto OR Gegenkonto is in the set, `ist nicht` if neither is).
    s.attribute key: :any_account, short_key: :kgk, label: "Konto oder Gegenkonto", group: "Konten",
      type: Filtering::Types::REFERENCE, operators: %i[in not_in],
      column: ->(t) { [t[:account_number], t[:offsetting_account_number]] },
      options: ACCOUNT_OPTIONS
    s.attribute key: :period, short_key: :per, label: "Periode", group: "Sonstiges",
      type: Filtering::Types::REFERENCE, operators: %i[in not_in],
      column: :primanota_period, options: PERIOD_OPTIONS
    # Whether the booking is linked to a Beitragsbuchung (accounting entry).
    # Presence-only atom; by default NOT usable (the bookings page excludes it),
    # enabled on the reconciliation pages.
    s.attribute key: :accounting_entry, short_key: :ae, label: "Beitragsbuchung",
      group: "Sonstiges", type: Filtering::Types::REFERENCE,
      operators: %i[present blank], column: :accounting_entry_id
  end

  # No host-pinned hidden conditions: every booking row is shown (there is no
  # soft-delete status any more).
  HIDDEN = [].freeze

  # `except:` lets the host page hide attributes (see bookings controller,
  # which currently excludes Sphäre and Periode).
  def self.bound(except: nil)
    SCHEMA.bind(DatevBooking.all, except: except)
  end
end
