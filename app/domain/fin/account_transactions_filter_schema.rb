# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The filter of the all-transactions page (doc/wsjrdp/generic_filter_builder.md): every
# account's transactions, Fin::AccountTransaction.
module Fin::AccountTransactionsFilterSchema
  extend Wsjrdp::Filtering::FilterSchema

  # The operator lists and ABS() of the Moss filter, shared.
  SHARED = Fin::MossTransactionsFilterSchema

  # The bank kinds, then the Moss kinds (Fin::AccountKinds).
  KIND_OPTIONS = Wsjrdp::Filtering::Options.values(-> { Fin::AccountKinds.options })

  SCHEMA = Wsjrdp::Filtering::Schema.define do |s|
    s.attribute key: :kind, short_key: :k, label: "Art",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in], column: :kind, options: KIND_OPTIONS
    s.attribute key: :account, short_key: :acc, label: "Konto",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in], column: :fin_account_id,
      options: Fin::InternalTransfersFilterSchema::ACCOUNT_OPTIONS
    s.attribute key: :date, short_key: :d, label: "Buchungstag",
      type: Wsjrdp::Filtering::Types::DATE, operators: SHARED::DATE_OPERATORS, column: :booking_date
    s.attribute key: :amount, short_key: :amt, label: "Betrag",
      variant_group: "Betrag", sign: :signed, type: Wsjrdp::Filtering::Types::DECIMAL,
      operators: SHARED::AMOUNT_OPERATORS, column: :signed_base_amount
    s.attribute key: :amount_abs, short_key: :amta, label: "|Betrag|",
      variant_group: "Betrag", sign: :absolute, type: Wsjrdp::Filtering::Types::DECIMAL,
      operators: SHARED::AMOUNT_OPERATORS, operand_min: 0,
      column: ->(t) { SHARED.abs(t[:signed_base_amount]) }
    # -- Textsuche: the free text first (the default), then single texts --
    s.attribute key: :text, short_key: :q, label: "Alle Texte",
      variant_group: "Textsuche", type: Wsjrdp::Filtering::Types::TEXT, operators: SHARED::TEXT_OPERATORS,
      column: ->(t) { [t[:description], t[:account_name], t[:party], t[:comment]] }
    s.attribute key: :description, short_key: :qd, label: "Beschreibung",
      variant_group: "Textsuche", type: Wsjrdp::Filtering::Types::TEXT, operators: SHARED::TEXT_OPERATORS,
      column: :description
    s.attribute key: :party, short_key: :qp, label: "Gegenseite",
      variant_group: "Textsuche", type: Wsjrdp::Filtering::Types::TEXT, operators: SHARED::TEXT_OPERATORS,
      column: :party
    s.attribute key: :person, short_key: :per, label: "Person",
      type: Wsjrdp::Filtering::Types::TEXT, operators: SHARED::TEXT_OPERATORS, column: :persons
  end

  def self.bound(except: nil)
    SCHEMA.bind(Fin::AccountTransaction.all, except: except)
  end
end
