# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Column definitions of the Dokumente list (main section Dokumente, /documents):
# one WsjrdpDocument per row. The rows are a relation
# (DocumentManagement::DocumentsController#documents), so every column sorts
# by an SQL expression.
#
# Where the table would scroll sideways (a phone, a narrow window) ID, Datei?,
# Größe and Hochgeladen give way (narrow: false) -- a document's page and its
# row's detail show them -- and Person, Art and Status remain.
module DocumentManagement::DocumentsColumns
  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "dmcol") do |c|
    c.column key: "id", abbr: "id", label: "ID", numeric: true, width: "4rem", narrow: false,
      sort: "wsjrdp_documents.id", sort_first: "desc", default: true
    # Person and Art start narrow (wrapping) and widen first, to
    # their targets: Person to 17rem, where 95% of the people's names fit
    # (33 characters), Art to 16rem, where every real kind's label fits
    # ("Nachweis über ein Führungszeugnis", 251px with the padding). Then they
    # grow on by up to 5rem each (t.gaps in documents/index) for the longer
    # names, then the gaps grow.
    c.column key: "subject", abbr: "sj", label: "Person", width: "8rem", target_width: "17rem", grow: 1,
      sort: "wsjrdp_documents.subject_id", default: true
    c.column key: "kind", abbr: "kd", label: "Art", width: "7rem", target_width: "16rem", grow: 1,
      header_tooltip: "Die Bezeichnung der Dokument-Art; Schlüssel und Unterschlüssel stehen im Tooltip der Zelle.",
      sort: Arel.sql("LOWER(COALESCE(#{WsjrdpDocumentKind.document_column_sql("wsjrdp_document_kinds.label")}, 'unbekannt'))"),
      default: true
    c.column key: "key", abbr: "k", label: "Schlüssel", width: "13rem",
      sort: "wsjrdp_documents.key"
    c.column key: "secondary_key", abbr: "sk", label: "Unterschlüssel", width: "9rem",
      sort: "wsjrdp_documents.secondary_key"
    c.column key: "derivation_key", abbr: "dk", label: "Ableitung", width: "8rem",
      sort: "wsjrdp_documents.derivation_key"
    # 5.5rem: the header with sort arrow and rank (85px measured) is wider than
    # the widest value, "gelöscht" (56px).
    c.column key: "status", abbr: "st", label: "Status", width: "5.5rem", header_align: "center",
      sort: "wsjrdp_documents.status", default: true
    c.column key: "file_status", abbr: "fs", label: "Datei?", width: "4.5rem", numeric: true, narrow: false,
      sort: "wsjrdp_documents.file_status", default: true
    c.column key: "filename", abbr: "fn", label: "Dateiname", width: "16rem",
      sort: "LOWER(wsjrdp_documents.filename)"
    c.column key: "content_type", abbr: "ct", label: "Typ", width: "10rem",
      sort: "wsjrdp_documents.content_type"
    c.column key: "byte_size", abbr: "bs", label: "Größe", numeric: true, width: "6rem", narrow: false,
      sort: "wsjrdp_documents.byte_size", sort_first: "desc", default: true
    c.column key: "origin", abbr: "or", label: "Herkunft", width: "6rem",
      sort: "wsjrdp_documents.origin"
    c.column key: "created_at", abbr: "ca", label: "Hochgeladen", width: "8.5rem",
      tabular_nums: true, header_align: "center", narrow: false,
      sort: "wsjrdp_documents.created_at", sort_first: "desc", default: true
    c.column key: "author", abbr: "au", label: "Von", width: "11rem",
      sort: "wsjrdp_documents.author_id"
  end
end
