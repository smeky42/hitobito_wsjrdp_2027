# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The Moss transactions dataset -- all four kinds (card payment, invoice,
# reimbursement, top-up) -- for the generic CNF filter
# (doc/wsjrdp/generic_filter_builder.md). Like Fin::DatevBookingsFilterSchema this is the
# ONLY dataset-specific part; everything else is Wsjrdp::Filtering::*.
#
# A transaction (moss_transactions, L1) has one or more expenses (moss_expenses,
# L2) and every expense one or more bookings (moss_bookings, L3 -- the grain
# DATEV books at). The schema is bound to a relation that LEFT JOINs the
# expenses and their bookings, so transaction-level attributes filter on
# moss_transactions columns, expense-level ones on moss_expenses and
# booking-level ones (Sachkonto, Kostenstelle, Sphäre, Betrag) on
# moss_bookings. A transaction with several matching bookings would appear
# more than once, so Fin::MossTransactionsController#distinct_transactions
# de-duplicates by id.
#
# Like Fin::DatevBookingsFilterSchema it is a FILTER SCHEMA
# (Wsjrdp::Filtering::FilterSchema): a table names it in its policy
# (`filter: {schema: Fin::MossTransactionsFilterSchema, ...}`) and the resolved state
# decodes, validates and compiles through it.
module Fin::MossTransactionsFilterSchema
  extend Wsjrdp::Filtering::FilterSchema

  EXPENSES = MossExpense.arel_table
  BOOKINGS = MossBooking.arel_table

  # The four kinds (STI types) in display order -- the filter picker, the
  # overview's cards and the kind tabs (Fin::MossTransactionsController::KIND_TABS)
  # all follow it; labels in fin.moss.kinds.
  KINDS = %w[MossCardTransaction MossReimbursement MossInvoice MossTopUp].freeze

  # "Betrag (alle Ebenen)" looks at every amount of a transaction: the total,
  # each expense and each booking. DECIMAL is single-column, so this is a
  # decimal type whose comparisons OR across the columns (like REFERENCE's
  # multi-column matching). Same keys and same labels as DECIMAL's comparisons,
  # so the two Betrag entries read alike in the editor and on a chip.
  AMOUNT_ANY = Wsjrdp::Filtering::Type.new(key: :decimal, control: "number_range", operators: [
    Wsjrdp::Filtering::Operator.new(key: :eq, label: "=", arity: :one) { |c, v|
      Wsjrdp::Filtering::Types.wrap(c).map { |col| col.eq(v[0]) }.reduce(:or)
    },
    Wsjrdp::Filtering::Operator.new(key: :gte, label: "≥", arity: :one) { |c, v|
      Wsjrdp::Filtering::Types.wrap(c).map { |col| col.gteq(v[0]) }.reduce(:or)
    },
    Wsjrdp::Filtering::Operator.new(key: :gt, label: ">", arity: :one) { |c, v|
      Wsjrdp::Filtering::Types.wrap(c).map { |col| col.gt(v[0]) }.reduce(:or)
    },
    Wsjrdp::Filtering::Operator.new(key: :lt, label: "<", arity: :one) { |c, v|
      Wsjrdp::Filtering::Types.wrap(c).map { |col| col.lt(v[0]) }.reduce(:or)
    },
    Wsjrdp::Filtering::Operator.new(key: :lte, label: "≤", arity: :one) { |c, v|
      Wsjrdp::Filtering::Types.wrap(c).map { |col| col.lteq(v[0]) }.reduce(:or)
    },
    Wsjrdp::Filtering::Operator.new(key: :between, label: "im Bereich", arity: :two) { |c, v|
      Wsjrdp::Filtering::Types.wrap(c).map { |col| col.gteq(v[0]).and(col.lteq(v[1])) }.reduce(:or)
    }
  ])

  # Both Betrag entries, signed and absolute alike: the range first, so a fresh
  # amount condition starts on "im Bereich".
  AMOUNT_OPERATORS = %i[between lte gte lt gt eq].freeze

  TEXT_OPERATORS = %i[
    contains contains_cs not_contains not_contains_cs eq eq_cs regex regex_cs
  ].freeze

  DATE_OPERATORS = %i[gte lt between in_month in_year].freeze
  NULLABLE_DATE_OPERATORS = (DATE_OPERATORS + %i[present blank]).freeze

  # --- option sources (lazy; computed when the catalog is rendered) ----------

  # ABS(column) -- the absolute member of a sign pair, one per amount column.
  def self.abs(column)
    Arel::Nodes::NamedFunction.new("ABS", [column])
  end

  # Distinct non-blank values of a string column, as [value, label] pairs.
  def self.distinct_pairs(model, column, &label)
    model.where.not(column => [nil, ""]).distinct.order(column).pluck(column)
      .map { |v| [v, label ? label.call(v) : v] }
  end

  KIND_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    KINDS.map { |kind| [kind, I18n.t("fin.moss.kinds.#{kind}")] }
  })
  CURRENCY_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    distinct_pairs(MossTransaction, :currency_original)
  })
  TRANSACTION_STATE_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    distinct_pairs(MossTransaction, :moss_transaction_state)
  })
  INVOICE_STATUS_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    distinct_pairs(MossTransaction, :invoice_status)
  })
  CARD_HOLDER_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    distinct_pairs(MossTransaction, :card_holder_name)
  })
  PAYOUT_USER_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    distinct_pairs(MossTransaction, :payout_user_name)
  })
  RECIPIENT_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    distinct_pairs(MossTransaction, :recipient_name)
  })
  APPROVER_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    distinct_pairs(MossTransaction, :approver_name)
  })
  SUBMITTED_BY_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    distinct_pairs(MossTransaction, :submitted_by)
  })

  # Kreditor: every supplier number that occurs on a transaction, labelled from
  # the personal accounts (standing data). Only used values are offered -- the
  # full chart would only pad the catalog with numbers no transaction carries.
  SUPPLIER_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    names = WsjrdpPersonalAccount.pluck(:number, :name).to_h
    distinct_pairs(MossTransaction, :supplier_account_number) { |n| names[n].present? ? "#{n} #{names[n]}" : n }
  })
  # Sachkonto (booking level): every account number that occurs on a booking,
  # labelled from the ledger accounts and suppliers (disjoint number ranges).
  ACCOUNT_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    names = WsjrdpLedgerAccount.pluck(:number, :name).to_h
      .merge(WsjrdpPersonalAccount.pluck(:number, :name).to_h)
    distinct_pairs(MossBooking, :account_number) { |n| names[n].present? ? "#{n} #{names[n]}" : n }
  })
  COST_CENTER_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    names = WsjrdpCostCenter.pluck(:number, :name).to_h
    distinct_pairs(MossBooking, :cost_center_number) { |n| names[n] ? "#{n} #{names[n]}" : n }
  })
  SPHERE_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    distinct_pairs(MossBooking, :sphere_number)
  })

  # Declaration order = picker order.
  SCHEMA = Wsjrdp::Filtering::Schema.define do |s|
    # -- Textsuche (one picker entry with sub-variants; the first is the default) --
    s.attribute key: :text, short_key: :q, label: "Name / Buchungstext",
      variant_group: "Textsuche", type: Wsjrdp::Filtering::Types::TEXT, operators: TEXT_OPERATORS,
      column: ->(t) {
        [t[:transaction_name], t[:transaction_posting_text],
          EXPENSES[:expense_name], EXPENSES[:expense_posting_text], BOOKINGS[:booking_posting_text]]
      }
    s.attribute key: :text_party, short_key: :qp, label: "Händler / Empfänger / Person",
      variant_group: "Textsuche", type: Wsjrdp::Filtering::Types::TEXT, operators: TEXT_OPERATORS,
      column: ->(t) {
        [t[:merchant_name], t[:recipient_name], t[:card_holder_name], t[:payout_user_name],
          t[:top_up_sender], t[:submitted_by], t[:approver_name]]
      }
    s.attribute key: :text_ref, short_key: :qr, label: "Belegnummer / Verwendungszweck",
      variant_group: "Textsuche", type: Wsjrdp::Filtering::Types::TEXT, operators: TEXT_OPERATORS,
      column: ->(t) { [t[:invoice_number], t[:payment_reference], t[:po_number], t[:pr_number]] }
    s.attribute key: :text_any, short_key: :qa, label: "Alles",
      variant_group: "Textsuche", type: Wsjrdp::Filtering::Types::TEXT, operators: TEXT_OPERATORS,
      column: ->(t) {
        [t[:transaction_name], t[:transaction_posting_text],
          EXPENSES[:expense_name], EXPENSES[:expense_posting_text], BOOKINGS[:booking_posting_text],
          t[:merchant_name], t[:recipient_name], t[:card_holder_name], t[:payout_user_name],
          t[:top_up_sender], t[:submitted_by], t[:approver_name],
          t[:invoice_number], t[:payment_reference], t[:po_number], t[:pr_number]]
      }

    # -- Art & Status --
    s.attribute key: :kind, short_key: :k, label: "Art", group: "Art & Status",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in],
      column: :type, options: KIND_OPTIONS
    s.attribute key: :transaction_state, short_key: :st, label: "Status (Moss)", group: "Art & Status",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in],
      column: :moss_transaction_state, options: TRANSACTION_STATE_OPTIONS
    s.attribute key: :invoice_status, short_key: :is, label: "Rechnungsstatus (Moss)", group: "Art & Status",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in present blank],
      column: :invoice_status, options: INVOICE_STATUS_OPTIONS

    # -- Beträge & Daten --
    # Both amounts are ONE picker entry each, with a sign toggle: the signed
    # value or its magnitude. Money leaving the wallet is negative, so
    # "|Betrag| ≥ 100" is how one asks for the big movements in either
    # direction.
    s.attribute key: :amount, short_key: :amt, label: "Betrag (Transaktion)", group: "Beträge & Daten",
      variant_group: "Betrag (Transaktion)", sign: :signed,
      type: Wsjrdp::Filtering::Types::DECIMAL, operators: AMOUNT_OPERATORS,
      column: :signed_total_base_amount
    s.attribute key: :amount_abs, short_key: :amta, label: "|Betrag (Transaktion)|",
      group: "Beträge & Daten", variant_group: "Betrag (Transaktion)", sign: :absolute,
      type: Wsjrdp::Filtering::Types::DECIMAL, operators: AMOUNT_OPERATORS, operand_min: 0,
      column: ->(t) { abs(t[:signed_total_base_amount]) }
    s.attribute key: :amount_any, short_key: :ama, label: "Betrag (alle Ebenen)", group: "Beträge & Daten",
      variant_group: "Betrag (alle Ebenen)", sign: :signed,
      type: AMOUNT_ANY, operators: AMOUNT_OPERATORS,
      column: ->(t) { [t[:signed_total_base_amount], EXPENSES[:signed_expense_base_amount], BOOKINGS[:signed_base_amount]] }
    # The magnitude of the same three levels: every column wrapped in ABS(),
    # the comparison still an OR across them.
    s.attribute key: :amount_any_abs, short_key: :amaa, label: "|Betrag (alle Ebenen)|",
      group: "Beträge & Daten", variant_group: "Betrag (alle Ebenen)", sign: :absolute,
      type: AMOUNT_ANY, operators: AMOUNT_OPERATORS, operand_min: 0,
      column: ->(t) {
        [abs(t[:signed_total_base_amount]), abs(EXPENSES[:signed_expense_base_amount]),
          abs(BOOKINGS[:signed_base_amount])]
      }
    s.attribute key: :currency, short_key: :cur, label: "Original-Währung", group: "Beträge & Daten",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in],
      column: :currency_original, options: CURRENCY_OPTIONS
    s.attribute key: :payment_date, short_key: :pd, label: "Zahlungsdatum", group: "Beträge & Daten",
      type: Wsjrdp::Filtering::Types::DATE, operators: NULLABLE_DATE_OPERATORS, column: :payment_date
    s.attribute key: :booking_date, short_key: :bd, label: "Buchungsdatum", group: "Beträge & Daten",
      type: Wsjrdp::Filtering::Types::DATE, operators: NULLABLE_DATE_OPERATORS, column: :booking_date
    s.attribute key: :approval_date, short_key: :ad, label: "Freigegeben am", group: "Beträge & Daten",
      type: Wsjrdp::Filtering::Types::DATE, operators: NULLABLE_DATE_OPERATORS, column: :approval_date
    s.attribute key: :invoice_date, short_key: :ivd, label: "Rechnungsdatum", group: "Beträge & Daten",
      type: Wsjrdp::Filtering::Types::DATE, operators: NULLABLE_DATE_OPERATORS, column: :invoice_date
    s.attribute key: :submitted_on, short_key: :so, label: "Beantragt am", group: "Beträge & Daten",
      type: Wsjrdp::Filtering::Types::DATE, operators: NULLABLE_DATE_OPERATORS, column: :submitted_on
    s.attribute key: :purchased_on, short_key: :po, label: "Kaufdatum (Ausgabe)", group: "Beträge & Daten",
      type: Wsjrdp::Filtering::Types::DATE, operators: NULLABLE_DATE_OPERATORS,
      column: ->(_t) { EXPENSES[:purchased_on] }

    # -- Konten & Kostenrechnung --
    s.attribute key: :supplier, short_key: :sup, label: "Kreditor", group: "Konten & Kostenrechnung",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in present blank],
      column: :supplier_account_number, options: SUPPLIER_OPTIONS
    s.attribute key: :account, short_key: :acc, label: "Sachkonto (Buchung)", group: "Konten & Kostenrechnung",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in present blank],
      column: ->(_t) { BOOKINGS[:account_number] }, options: ACCOUNT_OPTIONS
    s.attribute key: :cost_center, short_key: :cc, label: "Kostenstelle (Buchung)", group: "Konten & Kostenrechnung",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in present blank],
      column: ->(_t) { BOOKINGS[:cost_center_number] }, options: COST_CENTER_OPTIONS
    s.attribute key: :sphere, short_key: :sph, label: "Sphäre (Buchung)", group: "Konten & Kostenrechnung",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in present blank],
      column: ->(_t) { BOOKINGS[:sphere_number] }, options: SPHERE_OPTIONS

    # -- Personen --
    s.attribute key: :card_holder, short_key: :ch, label: "Karteninhaber", group: "Personen",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in present blank],
      column: :card_holder_name, options: CARD_HOLDER_OPTIONS
    s.attribute key: :payout_user, short_key: :pu, label: "Auszahlung durch", group: "Personen",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in present blank],
      column: :payout_user_name, options: PAYOUT_USER_OPTIONS
    s.attribute key: :recipient, short_key: :rcp, label: "Empfänger", group: "Personen",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in present blank],
      column: :recipient_name, options: RECIPIENT_OPTIONS
    s.attribute key: :approver, short_key: :apr, label: "Freigeber", group: "Personen",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in present blank],
      column: :approver_name, options: APPROVER_OPTIONS
    s.attribute key: :submitted_by, short_key: :sb, label: "Eingereicht von", group: "Personen",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in present blank],
      column: :submitted_by, options: SUBMITTED_BY_OPTIONS

    # -- Verknüpfungen --
    s.attribute key: :clearing_linked, short_key: :dvc, label: "DATEV-Ausgleich verknüpft",
      group: "Verknüpfungen", type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[present blank],
      column: :clearing_datev_booking_id
    s.attribute key: :expense_linked, short_key: :dvb, label: "DATEV-Aufwand verknüpft (Buchung)",
      group: "Verknüpfungen", type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[present blank],
      column: ->(_t) { BOOKINGS[:expense_datev_booking_id] }
    # Whether a booking is linked to a Beitragsbuchung (accounting entry). The
    # link lives on the entry; a correlated subquery keeps this a plain
    # present/blank atom without joining accounting_entries into every query.
    s.attribute key: :contribution, short_key: :ae, label: "Beitragsbuchung verknüpft (Buchung)",
      group: "Verknüpfungen", type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[present blank],
      column: ->(_t) {
        ae = AccountingEntry.arel_table
        Arel::Nodes::Grouping.new(
          ae.project(ae[:id]).where(ae[:moss_booking_id].eq(BOOKINGS[:id])).take(1)
        )
      }
  end

  # `except:` lets a host page hide attributes (the table's `exclude:`). The base
  # joins the expenses and their bookings so the expense- and booking-level
  # attributes compile; FilterSchema#compile merges it into whatever relation a
  # host hands in, so no host repeats the joins.
  def self.bound(except: nil)
    SCHEMA.bind(MossTransaction.left_joins(expenses: :bookings), except: except)
  end
end
