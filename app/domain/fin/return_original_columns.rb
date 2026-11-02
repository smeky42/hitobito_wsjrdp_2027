# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Columns of the candidates for the original of a return
# (fin/payment_returns/_original_candidates, Fin::ReturnOriginals): one
# candidate per row, the best first, a radio button of the return's edit form
# to choose it. The score orders them but does not show.
module Fin::ReturnOriginalColumns
  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "occol") do |c|
    c.column key: "choose", abbr: "ch", label: "Auswahl", header_label: "", width: "2rem", default: true
    c.column key: "score", abbr: "sc", label: "Treffer", numeric: true, width: "4.5rem",
      header_tooltip: "50 für den genau passenden Betrag, dazu End-to-End-ID, IBAN oder Mandat, Name und zeitliche Nähe",
      sort: ->(c) { c.score }, sort_first: "desc"
    c.column key: "date", abbr: "d", label: "Datum", width: "6.5rem", tabular_nums: true,
      sort: ->(c) { c.transaction.value_date }, sort_first: "desc", default: true
    c.column key: "amount", abbr: "a", label: "Betrag", numeric: true, width: "8rem", tabular_nums: true,
      default: true
    c.column key: "code", abbr: "co", label: "Code", width: "8rem", default: true
    c.column key: "party", abbr: "p", label: "Gegenpartei", width: "10rem", target_width: "16rem", grow: 1,
      default: true
    c.column key: "matches", abbr: "m", label: "Merkmale", width: "10rem", target_width: "14rem", grow: 1,
      header_tooltip: "Was außer dem Betrag passt; der Tooltip einer Zeile vergleicht jedes Merkmal", default: true
    c.column key: "description", abbr: "ds", label: "Verwendungszweck", width: "14rem"
    c.column key: "id", abbr: "id", label: "ID", numeric: true, width: "4.5rem",
      sort: ->(c) { c.id }, sort_first: "desc", default: true
  end
end
