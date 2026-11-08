# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The Umbuchungen list (Fin::InternalTransfersController) for the generic CNF
# filter: an array-backed dataset (doc/wsjrdp/generic_filter_builder.md,
# "Filtering arrays") over Fin::InternalTransfersColumns::Row, filtered in Ruby.
#
# The accounts of a side are one list field each (from_accounts, to_accounts:
# :integer_list, the account ids): "Von-Konto", "Nach-Konto" and "Konto"
# (either side) are references over them -- `ist` matches if any account of
# the side (or of either side) is one of the chosen, `ist nicht` if none is.
#
# The quick filters (PRESETS): the status as an exclusive group.
module Fin::InternalTransfersFilterSchema
  extend Wsjrdp::Filtering::ArrayFilterSchema

  STATUSES = {"complete" => "vollständig", "open" => "offen"}.freeze

  SOURCE = Wsjrdp::Filtering::ArraySource.define(:internal_transfers) do |s|
    s.field :date, :date
    s.field :amount, :numeric
    s.field :status, :text, ->(row) { row.status.to_s }
    s.field :purpose, :text, ->(row) { row.from_purpose }
    s.field :to_purpose, :text, ->(row) { row.to_purpose }
    s.field :comment, :text, ->(row) { row.transfer.comment }
    s.field :from_accounts, :integer_list, ->(row) { row.from_accounts.map(&:id) }
    s.field :to_accounts, :integer_list, ->(row) { row.to_accounts.map(&:id) }
  end

  ACCOUNT_OPTIONS = Wsjrdp::Filtering::Options.from(-> { WsjrdpFinAccount.display_order },
    value: :id, label: ->(account) { account.short_name.presence || account.to_s })

  STATUS_OPTIONS = Wsjrdp::Filtering::Options.values(-> { STATUSES.to_a })

  SCHEMA = Wsjrdp::Filtering::Schema.define do |s|
    s.attribute key: :account, short_key: :acc, label: "Konto (Von oder Nach)", group: "Konten",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in],
      column: ->(t) { [t[:from_accounts], t[:to_accounts]] }, options: ACCOUNT_OPTIONS
    s.attribute key: :from_account, short_key: :fra, label: "Von-Konto", group: "Konten",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in],
      column: :from_accounts, options: ACCOUNT_OPTIONS
    s.attribute key: :to_account, short_key: :toa, label: "Nach-Konto", group: "Konten",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in],
      column: :to_accounts, options: ACCOUNT_OPTIONS
    s.attribute key: :amount, short_key: :amt, label: "Betrag", group: "Betrag & Datum",
      type: Wsjrdp::Filtering::Types::DECIMAL, operators: Fin::DatevBookingsFilterSchema::AMOUNT_OPERATORS,
      operand_min: 0, column: :amount
    s.attribute key: :date, short_key: :dt, label: "Datum", group: "Betrag & Datum",
      type: Wsjrdp::Filtering::Types::DATE, operators: %i[gte lt between in_month in_year],
      column: :date
    s.attribute key: :status, short_key: :st, label: "Status",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: :status, options: STATUS_OPTIONS
    # Volltextsuche: either purpose or the comment (a multi-column text
    # attribute matches if any of its columns does).
    s.attribute key: :text, short_key: :q, label: "Volltextsuche", group: "Text",
      type: Wsjrdp::Filtering::Types::TEXT, operators: Fin::DatevBookingsFilterSchema::TEXT_OPERATORS,
      column: ->(t) { [t[:purpose], t[:to_purpose], t[:comment]] }
    s.attribute key: :purpose, short_key: :qv, label: "Verwendungszweck (Von)", group: "Text",
      type: Wsjrdp::Filtering::Types::TEXT, operators: Fin::DatevBookingsFilterSchema::TEXT_OPERATORS,
      column: :purpose
    s.attribute key: :to_purpose, short_key: :qn, label: "Verwendungszweck (Nach)", group: "Text",
      type: Wsjrdp::Filtering::Types::TEXT, operators: Fin::DatevBookingsFilterSchema::TEXT_OPERATORS,
      column: :to_purpose
    s.attribute key: :comment, short_key: :cm, label: "Kommentar", group: "Text",
      type: Wsjrdp::Filtering::Types::TEXT, operators: Fin::DatevBookingsFilterSchema::TEXT_OPERATORS,
      column: :comment
  end

  PRESETS = [
    {group: "status", attribute: "status", operator: "in", exclusive: true,
     members: STATUSES.map { |value, label| {key: value, label: label, value: value} }}
  ].freeze

  def self.bound(except: nil) = SCHEMA.bind(SOURCE, except: except)

  def self.array_strategy = :ruby
end
