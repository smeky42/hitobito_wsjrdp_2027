# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Column definitions of the versions of a document or a document group
# (documents/_versions_table, DocumentManagement::VersionsTable): one
# WsjrdpDocument per row, an Array that comes newest first and keeps that
# order while nothing is sorted. L and R pick what the comparison sets side by side;
# the numbers show only for a group of several combinations. Replaced and
# deleted share one cell -- an arrow up (the replacing version stands above
# it) and a ban sign, each with its time -- and sort one by one. Von, who
# uploaded it, is a tristate column, by default shown where there is room
# (auto), and widens to fit a long name; the columns menu adds the file's name, type,
# size and origin. The table fills the width (t.gaps in _versions_table).
module DocumentManagement::DocumentVersionsColumns
  ENDED = "Ersetzt / gelöscht"

  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "dvcol") do |c|
    c.column key: "compare_left", abbr: "l", label: "L", header_tooltip: "Links im Vergleich", width: "2rem",
      header_align: "center", default: true
    c.column key: "compare_right", abbr: "r", label: "R", header_tooltip: "Rechts im Vergleich", width: "2rem",
      header_align: "center", default: true
    c.column key: "id", abbr: "id", label: "ID", numeric: true, width: "4rem",
      sort: ->(document) { document.id }, sort_first: "desc", default: true
    c.column key: "numbers", abbr: "nr", label: "Nummern", width: "8rem",
      sort: ->(document) { [document.key_number.to_i, document.secondary_key_number.to_i] }, default: true
    c.column key: "created_at", abbr: "ca", label: "Hochgeladen", width: "8.5rem", tabular_nums: true,
      sort: ->(document) { document.created_at }, sort_first: "desc", default: true
    c.column key: "author", abbr: "au", label: "Von", width: "8rem", target_width: "15rem", grow: 1,
      visibility: :tristate, default: :auto, sort: ->(document) { [document.author_type.to_s, document.author_id.to_i] }
    c.column key: "status", abbr: "st", label: "Status", width: "5.5rem",
      sort: ->(document) { document.status }, default: true
    c.column key: "superseded_at", abbr: "sa", label: "Ersetzt", merge: ENDED, width: "4.5rem",
      target_width: "5.5rem", tabular_nums: true, sort: ->(document) { document.superseded_at },
      sort_first: "desc", default: true
    c.column key: "deleted_at", abbr: "da", label: "gelöscht", merge: ENDED, width: "4.5rem",
      target_width: "5.5rem", tabular_nums: true, sort: ->(document) { document.deleted_at },
      sort_first: "desc", default: true
    c.merge_header ENDED, [{cells: %w[superseded_at deleted_at], flow: true, separator: "/"}]
    c.column key: "file_status", abbr: "fs", label: "Datei?", width: "4.5rem", header_align: "center",
      sort: ->(document) { document.file_status }, default: true
    c.column key: "filename", abbr: "fn", label: "Dateiname", width: "10rem", target_width: "18rem", grow: 1,
      sort: ->(document) { document.filename.to_s.downcase }
    c.column key: "content_type", abbr: "ct", label: "Typ", width: "9rem",
      sort: ->(document) { document.content_type.to_s }
    c.column key: "byte_size", abbr: "bs", label: "Größe", numeric: true, width: "5.5rem",
      sort: ->(document) { document.byte_size }, sort_first: "desc"
    c.column key: "origin", abbr: "or", label: "Herkunft", width: "6rem",
      sort: ->(document) { document.origin.to_s }
  end
end
