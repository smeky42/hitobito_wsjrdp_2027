# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Column definitions of the tab Nach Person und Art of the main section
# Dokumente (DocumentManagement::DocumentGroupsController): one
# DocumentManagement::DocumentGroups::Group per row, an Array, so every column
# sorts by a Ruby value.
module DocumentManagement::DocumentGroupsColumns
  UNKNOWN_LAST = "\u{10FFFF}"
  # Ascending: none first, the groups that need a look.
  CURRENT_ORDER = %i[none some all].freeze

  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "dgcol") do |c|
    c.column key: "subject", abbr: "sj", label: "Person", width: "13rem",
      sort: ->(group) { [group.subject&.to_s&.downcase || UNKNOWN_LAST, group.subject_id] }, default: true
    c.column key: "kind", abbr: "kd", label: "Art", width: "13rem",
      sort: ->(group) { group.label&.downcase || UNKNOWN_LAST }, default: true
    c.column key: "key", abbr: "k", label: "Schlüssel", width: "13rem",
      sort: ->(group) { group.key.to_s }
    c.column key: "secondary_key", abbr: "sk", label: "Unterschlüssel", width: "10rem",
      sort: ->(group) { group.secondary_key.to_s }
    c.column key: "count", abbr: "n", label: "Versionen", numeric: true, width: "6.5rem",
      header_tooltip: "Alle Dokumente der Gruppe: das aktuelle, die ersetzten und die gelöschten.",
      sort: ->(group) { group.count }, sort_first: "desc", default: true
    # How many of the group's combinations (numbers) have a current document,
    # with an icon for all, some or none.
    # 5.25rem: the header with sort arrow and rank (83px measured) is wider
    # than "12/12" and the mark.
    c.column key: "current", abbr: "cu", label: "aktuell", width: "5.25rem", numeric: true,
      header_tooltip: "Wie viele Kombinationen (Nummern) der Gruppe ein aktuelles Dokument haben.",
      sort: ->(group) { [CURRENT_ORDER.index(group.current_state), group.current] }, default: true
    c.column key: "superseded", abbr: "su", label: "ersetzt", numeric: true, width: "5.5rem",
      sort: ->(group) { group.superseded }, sort_first: "desc"
    c.column key: "deleted", abbr: "de", label: "gelöscht", numeric: true, width: "5.5rem",
      sort: ->(group) { group.deleted }, sort_first: "desc"
    # The missing files as a mark, their number in front when more than one;
    # 5rem: the header with sort arrow and rank (80px measured).
    c.column key: "missing", abbr: "mi", label: "Datei?", numeric: true, width: "5rem",
      sort: ->(group) { group.missing }, sort_first: "desc", default: true
    c.column key: "first_at", abbr: "fa", label: "Erstes", width: "8.5rem",
      tabular_nums: true, header_align: "center",
      header_tooltip: "Das früheste Hochgeladen der Gruppe.",
      sort: ->(group) { group.first_at }, sort_first: "desc"
    c.column key: "last_at", abbr: "la", label: "Letztes", width: "8.5rem",
      tabular_nums: true, header_align: "center",
      header_tooltip: "Das späteste Hochgeladen der Gruppe.",
      sort: ->(group) { group.last_at }, sort_first: "desc", default: true
    c.column key: "bytes", abbr: "b", label: "Größe", numeric: true, width: "6.5rem",
      sort: ->(group) { group.bytes }, sort_first: "desc"
  end
end
