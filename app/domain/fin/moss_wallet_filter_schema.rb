# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The Moss WALLET statement for the generic CNF filter
# (doc/wsjrdp/generic_filter_builder.md, Part 4): the dataset behind the table on
# fin/wsjrdp_fin_accounts#show of the Moss wallet.
#
# WHY A SCHEMA OF ITS OWN, next to Fin::MossTransactionsFilterSchema: a filter
# schema is bound to ONE base relation, and that relation decides what a row is.
# The Moss section lists PAYMENTS (moss_transactions, L1); the wallet lists the
# BOOKINGS of those payments (moss_bookings, L3) -- one row per split, because
# that is the row the wallet's statement shows, the row DATEV books and the only
# one with a detail page of its own. Binding the transactions schema here would
# therefore filter the wrong grain (and drag its expenses/bookings LEFT JOINs,
# and with them duplicate rows, into a list that already IS at booking level).
#
# It stays DELIBERATELY SMALL -- four attributes for the four things a wallet
# statement is scanned for. The one that matters, `kind`, reuses
# Fin::MossTransactionsFilterSchema::KIND_OPTIONS, so the values and the words
# are literally the Moss section's: what "Rechnung" means in the filter of
# /fin/moss/transactions it means here, and a fifth STI subclass appears in both
# pickers at once. The four kind PRESETS of the wallet
# (Fin::WsjrdpFinAccountsController#wallet_presets) are built on this attribute.
#
# The base joins the transaction, so the transaction-level attributes compile;
# Wsjrdp::Filtering::FilterSchema#compile merges that base into whatever
# relation the host hands in, so the host never repeats the join.
module Fin::MossWalletFilterSchema
  extend Wsjrdp::Filtering::FilterSchema

  TRANSACTIONS = MossTransaction.arel_table

  # Declaration order = picker order.
  SCHEMA = Wsjrdp::Filtering::Schema.define do |s|
    # The kind is the transaction's STI type -- the same discriminator, the same
    # options and the same operators as the Moss section's "Art".
    s.attribute key: :kind, short_key: :k, label: "Art",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in],
      column: ->(_t) { TRANSACTIONS[:type] },
      options: Fin::MossTransactionsFilterSchema::KIND_OPTIONS
    # Buchungsdatum: the booking has no date of its own (MossBooking#value_date
    # delegates), so this reaches through the join to the transaction's column
    # -- the one the statement shows and sorts by. Same key, same words and the
    # same nullable operators as the Moss section's "Buchungsdatum".
    s.attribute key: :booking_date, short_key: :bd, label: "Buchungsdatum",
      type: Wsjrdp::Filtering::Types::DATE,
      operators: Fin::MossTransactionsFilterSchema::NULLABLE_DATE_OPERATORS,
      column: ->(_t) { TRANSACTIONS[:booking_date] }
    # Betrag: the SPLIT's signed EUR share (not the payment total) -- what the
    # row shows and what the wallet balance is the sum of. ONE picker entry
    # with a sign toggle, like the Moss section's two amounts: a payment out of
    # the wallet is negative, so the magnitude is what finds the big rows on
    # either side.
    s.attribute key: :amount, short_key: :amt, label: "Betrag",
      variant_group: "Betrag", sign: :signed, type: Wsjrdp::Filtering::Types::DECIMAL,
      operators: Fin::MossTransactionsFilterSchema::AMOUNT_OPERATORS,
      column: :signed_base_amount
    s.attribute key: :amount_abs, short_key: :amta, label: "|Betrag|",
      variant_group: "Betrag", sign: :absolute, type: Wsjrdp::Filtering::Types::DECIMAL,
      operators: Fin::MossTransactionsFilterSchema::AMOUNT_OPERATORS, operand_min: 0,
      column: ->(t) { Fin::MossTransactionsFilterSchema.abs(t[:signed_base_amount]) }
    # One text search over the two Buchungstexte the row renders (the split's
    # own and the payment's); a positive predicate matches in EITHER.
    s.attribute key: :text, short_key: :q, label: "Buchungstext",
      type: Wsjrdp::Filtering::Types::TEXT,
      operators: Fin::MossTransactionsFilterSchema::TEXT_OPERATORS,
      column: ->(t) { [t[:booking_posting_text], TRANSACTIONS[:transaction_posting_text]] }
  end

  # `except:` lets a host page hide attributes (the table's `exclude:`).
  def self.bound(except: nil)
    SCHEMA.bind(MossBooking.joins(:moss_transaction), except: except)
  end
end
