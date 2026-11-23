# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The filter of a bank account's statement (doc/wsjrdp/generic_filter_builder.md):
# the camt transactions of one account.
module Fin::CamtTransactionsFilterSchema
  extend Wsjrdp::Filtering::FilterSchema

  # The operator lists and ABS() of the Moss filter, shared.
  SHARED = Fin::MossTransactionsFilterSchema

  # The bank kinds (Fin::AccountKinds::BANK_KINDS), worked out in SQL.
  KIND_OPTIONS = Wsjrdp::Filtering::Options.values(-> { Fin::AccountKinds.options(Fin::AccountKinds::BANK_KINDS) })

  COLUMNS = Fin::CamtTransactionsColumns
  RETURN_KIND_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    I18n.t("fin.payments.return_kinds").map { |kind, label| [kind.to_s, label] }
  })
  STATUS_OPTIONS = Wsjrdp::Filtering::Options.values(-> { SHARED.distinct_pairs(WsjrdpCamtTransaction, :status) })
  REASON_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    Fin::ReturnReasons.options(WsjrdpCamtTransaction.where.not(return_reason: [nil, ""]).distinct.pluck(:return_reason))
  })
  RETURN_STATE_OPTIONS = Fin::PaymentReturnsFilterSchema::STATUS_OPTIONS

  # A text attribute over one column or SQL expression.
  def self.text(s, key, short_key, label, column, group: nil)
    s.attribute key: key, short_key: short_key, label: label, variant_group: group,
      type: Wsjrdp::Filtering::Types::TEXT, operators: SHARED::TEXT_OPERATORS, column: column
  end

  def self.sql(expression) = ->(_t) { Arel.sql("(#{expression})") }

  SCHEMA = Wsjrdp::Filtering::Schema.define do |s|
    s.attribute key: :kind, short_key: :k, label: "Art",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in], options: KIND_OPTIONS,
      column: sql(COLUMNS::KIND_SQL)
    s.attribute key: :value_date, short_key: :vd, label: "Valuta",
      type: Wsjrdp::Filtering::Types::DATE, operators: SHARED::DATE_OPERATORS, column: :value_date
    s.attribute key: :booking_date, short_key: :bd, label: "Buchungstag",
      type: Wsjrdp::Filtering::Types::DATE, operators: SHARED::NULLABLE_DATE_OPERATORS, column: :booking_date
    s.attribute key: :amount, short_key: :amt, label: "Betrag",
      variant_group: "Betrag", sign: :signed, type: Wsjrdp::Filtering::Types::DECIMAL,
      operators: SHARED::AMOUNT_OPERATORS, column: :signed_base_amount
    s.attribute key: :amount_abs, short_key: :amta, label: "|Betrag|",
      variant_group: "Betrag", sign: :absolute, type: Wsjrdp::Filtering::Types::DECIMAL,
      operators: SHARED::AMOUNT_OPERATORS, operand_min: 0,
      column: ->(t) { SHARED.abs(t[:signed_base_amount]) }
    # -- Textsuche: the free text first (the default), then single texts --
    text(s, :text, :q, "Alle Texte",
      ->(t) { [t[:description], Arel.sql("(#{COLUMNS::PARTY_SQL})"), t[:comment], t[:cdtr_name], t[:dbtr_name]] },
      group: "Textsuche")
    text(s, :description, :qd, "Beschreibung", :description, group: "Textsuche")
    text(s, :party, :qp, "Gegenseite", sql(COLUMNS::PARTY_SQL), group: "Textsuche")
    text(s, :comment, :qc, "Kommentar", :comment, group: "Textsuche")
    text(s, :person, :per, "Person", sql(COLUMNS::PERSONS_SQL))
    # -- Kreditor and Debitor: name, IBAN, BIC --
    text(s, :cdtr_name, :cn, "Kreditor Name", :cdtr_name, group: "Kreditor")
    text(s, :cdtr_iban, :ci, "Kreditor IBAN", :cdtr_iban, group: "Kreditor")
    text(s, :cdtr_bic, :cb, "Kreditor BIC", :cdtr_bic, group: "Kreditor")
    text(s, :dbtr_name, :dn, "Debitor Name", :dbtr_name, group: "Debitor")
    text(s, :dbtr_iban, :di, "Debitor IBAN", :dbtr_iban, group: "Debitor")
    text(s, :dbtr_bic, :db, "Debitor BIC", :dbtr_bic, group: "Debitor")
    text(s, :endtoend_id, :e2e, "Kundenreferenz", :endtoend_id)
    text(s, :mandate_id, :mdt, "Mandatsreferenz", :mandate_id)
    text(s, :bank_transaction_code, :btc, "ISO-Buchungscode", :bank_transaction_code)
    text(s, :bank_transaction_code_dk, :dk, "DK-Buchungscode", :bank_transaction_code_dk)
    s.attribute key: :status, short_key: :st, label: "Status",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in], column: :status, options: STATUS_OPTIONS
    s.attribute key: :return_kind, short_key: :rk, label: "Rückläufer-Art",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in], column: :return_kind,
      options: RETURN_KIND_OPTIONS
    s.attribute key: :return_reason, short_key: :rr, label: "Rückgabe-Grund",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in], column: :return_reason,
      options: REASON_OPTIONS
    s.attribute key: :return_state, short_key: :rs, label: "Retoure-Status",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in], column: sql(COLUMNS::RETURN_STATE_SQL),
      options: RETURN_STATE_OPTIONS
  end

  def self.bound(except: nil)
    SCHEMA.bind(WsjrdpCamtTransaction.all, except: except)
  end
end
