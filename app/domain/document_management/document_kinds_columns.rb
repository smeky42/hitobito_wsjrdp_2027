# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Column definitions of the Dokument-Arten list (main section Dokumente,
# /document_management/document_kinds): one WsjrdpDocumentKind per row, from a
# relation, so a sortable column sorts by an SQL expression.
#
# Label, key and secondary key are three columns with a header each (each
# sorts) that share ONE cell -- the label above the keys; in the columns
# menu they are one block, NAME, shown or hidden part by part. The label's
# header stands over the keys', which follow one another; on a narrow table
# the headers wrap (merge_header). The subject type is a column of
# its own, hidden by default. The rights stand in one column, the files as
# type families, the role rules written out; the kind's page is the
# widget's page link column (t.detail_page column: true in the view).
#
# The widths (measured at 14px) are what a narrow screen gets: the merged
# column 8rem, its headers then wrapped ("Schlüs-sel", "Unter-schlüs-sel"),
# the label hyphenated, a long key broken anywhere; the rights as wide as
# their widest entry (117px), the role rules as their widest word (119px).
# With room to spare the columns widen first to their targets -- the merged
# column until every real kind's label takes one line ("Nachweis über ein
# Führungszeugnis", 251px with the cell's padding) and its lower headers
# fit ("Schlüssel" 91px, "Unterschlüssel" 128px -- the secondary key widens
# twice as fast), the rights until a list takes one line (SEPA's, 270px),
# the role rules, twice as fast, to 24rem -- then past them by `grow` (up to t.gaps' grow_max per unit): the role
# rules until each takes one line (772px), the rights and the merged column
# for long lists and labels (456px, a label of 411px over keys of 605px);
# then the gaps grow and the table stops widening. On a phone files and
# documents give way (mobile: false); where the table would scroll sideways
# the documents and the page links (narrow: false), the kind's page is then
# the double button in the detail.
module DocumentManagement::DocumentKindsColumns
  # The merge key of label and keys -- also the name of their block in the
  # columns menu.
  NAME = "Bezeichnung / Schlüssel / Unterschlüssel"

  # The documents of a kind (its subject type and keys).
  DOCUMENT_COUNT_SQL = <<~SQL.squish
    (SELECT COUNT(*) FROM wsjrdp_documents d WHERE d.subject_type = wsjrdp_document_kinds.subject_type
      AND d.key = wsjrdp_document_kinds.key AND d.secondary_key = wsjrdp_document_kinds.secondary_key)
  SQL

  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "dkcol") do |c|
    c.column key: "position", abbr: "po", label: "Reihenfolge", numeric: true, width: "6rem",
      sort: "wsjrdp_document_kinds.position"
    c.column key: "label", abbr: "lb", label: "Bezeichnung", merge: NAME, width: "3rem", target_width: "7.5rem",
      grow: 0.5, sort: "LOWER(wsjrdp_document_kinds.label)", default: true
    # Soft hyphens: the wrapping header layout breaks "Schlüs-sel" and
    # "Unter-schlüs-sel".
    c.column key: "key", abbr: "k", label: "Schlüssel", header_label: "Schlüs\u00ADsel", merge: NAME,
      width: "1rem", target_width: "5.75rem", grow: 0.25, sort: "wsjrdp_document_kinds.key", default: true
    c.column key: "secondary_key", abbr: "sk", label: "Unterschlüssel", header_label: "Unter\u00ADschlüs\u00ADsel",
      merge: NAME, width: "4rem", target_width: "8rem", target_grow: 2, grow: 0.25, sort: "wsjrdp_document_kinds.secondary_key",
      default: true
    # The label over the keys, the keys one after the other; on a narrow
    # table the headers wrap.
    name_rows = [%w[label], {cells: %w[key secondary_key], flow: true}]
    c.merge_header NAME, layouts: [name_rows, {rows: name_rows, wrap: true}]
    c.column key: "subject_type", abbr: "st", label: "Gehört zu", width: "5.5rem",
      sort: "wsjrdp_document_kinds.subject_type"
    c.column key: "rights", abbr: "ri", label: "Zugriffsrechte", width: "8rem", target_width: "17.5rem",
      grow: 0.5, default: true
    c.column key: "files", abbr: "f", label: "Dateien", width: "4rem", header_align: "center", mobile: false,
      default: true
    c.column key: "role_rules", abbr: "rr", label: "Regeln je Rolle", width: "8.5rem", target_width: "24rem",
      target_grow: 2, grow: 1, default: true
    c.column key: "documents", abbr: "dc", label: "Dokumente", header_label: "Dok.", numeric: true,
      width: "3.75rem", mobile: false, narrow: false, sort: DOCUMENT_COUNT_SQL, sort_first: "desc", default: true
  end
end
