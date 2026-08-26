# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The Moss card transactions dataset for the generic CNF filter
# (doc/generic_filter_builder.md). Like DatevBookingsFilter this is the ONLY
# dataset-specific part -- everything else is Filtering::*.
#
# A card transaction (moss_card_transactions) has one or more bookings/splits
# (moss_card_transaction_bookings). So the schema is bound to a relation that
# LEFT JOINs the bookings; transaction-level attributes filter on
# moss_card_transactions columns, booking-level ones (Sachkonto, Kategorie,
# Betrag, ...) on moss_card_transaction_bookings columns. The query object then
# de-duplicates (a tx with two matching splits must appear once), see
# MossCardTransactionsQuery.
module MossCardTransactionsFilter
  BOOKINGS = MossCardTransactionBooking.arel_table

  # "Betrag" looks at ALL amounts of a transaction: the transaction total AND
  # every split's amount (user requirement). DECIMAL is single-column, so this
  # is a decimal type whose comparisons OR across the columns (like REFERENCE's
  # multi-column matching).
  AMOUNT_ANY = Filtering::Type.new(key: :decimal, control: "number_range", operators: [
    Filtering::Operator.new(key: :eq, label: "ist genau", arity: :one) { |c, v|
      Filtering::Types.wrap(c).map { |col| col.eq(v[0]) }.reduce(:or)
    },
    Filtering::Operator.new(key: :gte, label: "≥", arity: :one) { |c, v|
      Filtering::Types.wrap(c).map { |col| col.gteq(v[0]) }.reduce(:or)
    },
    Filtering::Operator.new(key: :lt, label: "<", arity: :one) { |c, v|
      Filtering::Types.wrap(c).map { |col| col.lt(v[0]) }.reduce(:or)
    },
    Filtering::Operator.new(key: :between, label: "im Bereich", arity: :two) { |c, v|
      Filtering::Types.wrap(c).map { |col| col.gteq(v[0]).and(col.lteq(v[1])) }.reduce(:or)
    }
  ])

  TEXT_OPERATORS = %i[
    contains contains_cs not_contains not_contains_cs eq eq_cs regex regex_cs
  ].freeze

  # --- option sources (lazy; computed when the catalog is rendered) ----------

  def self.distinct_pairs(model, column, &label)
    model.where.not(column => nil).distinct.order(column).pluck(column)
      .map { |v| [v, label ? label.call(v) : v] }
  end

  # Währung spans all three currency columns (Buchung / Basis / Original), so the
  # options merge the distinct values of all three.
  CURRENCY_OPTIONS = Filtering::Options.values(-> {
    (MossCardTransaction.distinct.pluck(:currency) +
      MossCardTransaction.distinct.pluck(:home_currency) +
      MossCardTransaction.distinct.pluck(:original_currency))
      .compact.uniq.sort.map { |c| [c, c] }
  })
  TRANSACTION_STATE_OPTIONS = Filtering::Options.values(-> {
    distinct_pairs(MossCardTransaction, :transaction_state)
  })
  APPROVAL_STATUS_OPTIONS = Filtering::Options.values(-> {
    distinct_pairs(MossCardTransaction, :post_spend_approval_status)
  })
  CARDHOLDER_OPTIONS = Filtering::Options.values(-> {
    distinct_pairs(MossCardTransaction, :cardholder)
  })
  TEAM_OPTIONS = Filtering::Options.values(-> {
    distinct_pairs(MossCardTransaction, :team_name)
  })
  APPROVER_OPTIONS = Filtering::Options.values(-> {
    distinct_pairs(MossCardTransaction, :approver_name)
  })
  # Booking-level (per split): Sachkonto, Kostenstelle, Sphäre.
  # Sachkonto reference like the bookings page: names from wsjrdp_ledger_accounts
  # merged with wsjrdp_personal_accounts (700xxx creditors), plus every account number
  # that actually occurs in the bookings (so all used values are selectable).
  ACCOUNT_OPTIONS = Filtering::Options.merge(
    Filtering::Options.from(WsjrdpLedgerAccount.order(:number),
      value: :number, label: ->(a) { "#{a.number} #{a.name}" }),
    Filtering::Options.from(WsjrdpPersonalAccount.order(:number),
      value: :number, label: ->(s) { "#{s.number} #{s.name}" }),
    Filtering::Options.values(-> {
      names = WsjrdpLedgerAccount.pluck(:number, :name).to_h
        .merge(WsjrdpPersonalAccount.pluck(:number, :name).to_h)
      MossCardTransactionBooking.where.not(account_number: nil)
        .distinct.pluck(:account_number).compact.uniq.sort
        .map { |n| [n, names[n].present? ? "#{n} #{names[n]}" : n] }
    })
  )
  COST_CENTER_OPTIONS = Filtering::Options.values(-> {
    names = WsjrdpCostCenter.pluck(:number, :name).to_h
    distinct_pairs(MossCardTransactionBooking, :cost_center_number) { |n| names[n] ? "#{n} #{names[n]}" : n }
  })
  SPHERE_OPTIONS = Filtering::Options.values(-> {
    distinct_pairs(MossCardTransactionBooking, :sphere_number)
  })

  # Declaration order = picker order.
  SCHEMA = Filtering::Schema.define do |s|
    # -- Textsuche (one picker entry with sub-variants) --
    s.attribute key: :text, short_key: :q, label: "Händler / Person",
      variant_group: "Textsuche", type: Filtering::Types::TEXT, operators: TEXT_OPERATORS,
      column: ->(t) { [t[:merchant_name], t[:supplier_name], t[:cardholder], t[:card_holder_name]] }
    s.attribute key: :text_purpose, short_key: :qz, label: "Zweck / Notiz",
      variant_group: "Textsuche", type: Filtering::Types::TEXT, operators: TEXT_OPERATORS,
      column: ->(t) { [t[:reason_for_purchase], t[:parent_booking_text], BOOKINGS[:description]] }
    s.attribute key: :text_ref, short_key: :qi, label: "Rechnungsnr / Moss-ID",
      variant_group: "Textsuche", type: Filtering::Types::TEXT, operators: TEXT_OPERATORS,
      column: ->(t) { [t[:invoice_number], t[:card_transaction_uuid]] }
    s.attribute key: :text_any, short_key: :qa, label: "Alles",
      variant_group: "Textsuche", type: Filtering::Types::TEXT, operators: TEXT_OPERATORS,
      column: ->(t) {
        [t[:merchant_name], t[:supplier_name], t[:cardholder], t[:card_holder_name],
          t[:reason_for_purchase], t[:parent_booking_text], t[:invoice_number],
          t[:card_transaction_uuid], BOOKINGS[:description], BOOKINGS[:name_of_expense_account]]
      }

    # -- Beträge & Daten --
    s.attribute key: :amount, short_key: :amt, label: "Betrag (alle)", group: "Beträge & Daten",
      type: AMOUNT_ANY, operators: %i[eq gte lt between],
      column: ->(t) { [t[:total_amount], BOOKINGS[:amount]] }
    s.attribute key: :booking_date, short_key: :bd, label: "Buchungsdatum", group: "Beträge & Daten",
      type: Filtering::Types::DATE, operators: %i[gte lt between in_month in_year], column: :booking_date
    s.attribute key: :payment_date, short_key: :pd, label: "Zahlungsdatum", group: "Beträge & Daten",
      type: Filtering::Types::DATE, operators: %i[gte lt between in_month in_year], column: :payment_date
    s.attribute key: :settlement_date, short_key: :sd, label: "Abrechnungsdatum",
      group: "Beträge & Daten", type: Filtering::Types::DATE,
      operators: %i[gte lt between in_month in_year present blank], column: :settlement_date
    s.attribute key: :currency, short_key: :cur, label: "Währung", group: "Beträge & Daten",
      type: Filtering::Types::REFERENCE, operators: %i[in not_in],
      column: ->(t) { [t[:currency], t[:home_currency], t[:original_currency]] },
      options: CURRENCY_OPTIONS

    # -- Konten & Kostenrechnung --
    s.attribute key: :account, short_key: :acc, label: "Sachkonto", group: "Konten & Kostenrechnung",
      type: Filtering::Types::REFERENCE, operators: %i[in not_in present blank],
      column: ->(_t) { BOOKINGS[:account_number] }, options: ACCOUNT_OPTIONS
    s.attribute key: :cost_center, short_key: :cc, label: "Kostenstelle",
      group: "Konten & Kostenrechnung", type: Filtering::Types::REFERENCE,
      operators: %i[in not_in present blank], column: ->(_t) { BOOKINGS[:cost_center_number] },
      options: COST_CENTER_OPTIONS
    # Sphäre: hidden from the picker for now (catalog: false) -- still compilable
    # from a shared URL, but not interactively selectable.
    s.attribute key: :sphere, short_key: :sph, label: "Sphäre",
      group: "Konten & Kostenrechnung", type: Filtering::Types::REFERENCE,
      operators: %i[in not_in], column: ->(_t) { BOOKINGS[:sphere_number] },
      options: SPHERE_OPTIONS, catalog: false

    # -- Karte & Person --
    s.attribute key: :cardholder, short_key: :ch, label: "Karteninhaber", group: "Karte & Person",
      type: Filtering::Types::REFERENCE, operators: %i[in not_in], column: :cardholder,
      options: CARDHOLDER_OPTIONS
    s.attribute key: :team, short_key: :tm, label: "Team", group: "Karte & Person",
      type: Filtering::Types::REFERENCE, operators: %i[in not_in present blank], column: :team_name,
      options: TEAM_OPTIONS
    s.attribute key: :approver, short_key: :apr, label: "Freigeber", group: "Karte & Person",
      type: Filtering::Types::REFERENCE, operators: %i[in not_in present blank], column: :approver_name,
      options: APPROVER_OPTIONS

    # -- Status & Sonstiges --
    s.attribute key: :transaction_state, short_key: :st, label: "Transaktionsstatus",
      group: "Status & Sonstiges", type: Filtering::Types::REFERENCE, operators: %i[in not_in],
      column: :transaction_state, options: TRANSACTION_STATE_OPTIONS
    s.attribute key: :approval_status, short_key: :ap, label: "Freigabe-Status",
      group: "Status & Sonstiges", type: Filtering::Types::REFERENCE, operators: %i[in not_in present blank],
      column: :post_spend_approval_status, options: APPROVAL_STATUS_OPTIONS
    s.attribute key: :receipt, short_key: :rc, label: "Beleg vorhanden",
      group: "Status & Sonstiges", type: Filtering::Types::REFERENCE, operators: %i[present blank],
      column: :invoice_file_name
    # Whether the split is linked to its DATEV bookings (booking-level).
    s.attribute key: :datev_linked, short_key: :dv, label: "DATEV-Buchung verknüpft",
      group: "Status & Sonstiges", type: Filtering::Types::REFERENCE, operators: %i[present blank],
      column: ->(_t) { BOOKINGS[:expense_datev_booking_id] }
  end

  HIDDEN = [].freeze

  def self.bound(except: nil)
    SCHEMA.bind(MossCardTransaction.left_joins(:bookings), except: except)
  end
end
