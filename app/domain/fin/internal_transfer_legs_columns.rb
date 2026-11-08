# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Column definitions of "Buchungen der Umbuchung", the legs table in the detail
# of one Umbuchung (fin/internal_transfers/_detail): one Fin::InternalTransferLeg
# per row, array-backed. The text is the column that grows; it wraps rather
# than being cut, as a bank's purpose is read in full.
module Fin::InternalTransferLegsColumns
  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "itlcol") do |c|
    c.column key: "account", abbr: "ac", label: "Konto", width: "12rem", target_width: "16rem", truncate: true,
      sort: ->(leg) { leg.account.to_s.downcase }, default: true
    c.column key: "date", abbr: "dt", label: "Datum", width: "6.5rem", tabular_nums: true,
      sort: ->(leg) { leg.date || Date.new(0) }, default: true
    c.column key: "text", abbr: "tx", label: "Text", width: "14rem", grow: 4,
      sort: ->(leg) { leg.text.downcase }, default: true
    c.column key: "amount", abbr: "am", label: "Betrag", numeric: true, width: "8.5rem",
      sort: ->(leg) { leg.amount }, default: true
  end

  def self.sort_lambdas = COLUMNS.sort_expressions
end
