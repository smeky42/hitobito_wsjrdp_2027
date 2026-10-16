# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Column definitions of the chains of the tab Anmelde-Dokumente
# (DocumentManagement::RegistrationDocumentsController): one
# Wsjrdp2027::RegistrationDocuments::Chain per row, an Array, so every column
# sorts by a Ruby value.
module DocumentManagement::RegistrationChainsColumns
  STATE_ORDER = DocumentManagement::RegistrationChainsFilterSchema::STATES

  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "rccol") do |c|
    c.column key: "person", abbr: "p", label: "Person", width: "15rem",
      sort: ->(chain) { chain.person_name.to_s.downcase }, default: true
    c.column key: "person_id", abbr: "pid", label: "ID", numeric: true, width: "5rem",
      sort: ->(chain) { chain.person_id }
    c.column key: "key", abbr: "k", label: "Art",
      header_tooltip: "Die Dokument-Art der Spalte des Tabs „Dokumente hochladen“; ihr Schlüssel, so wie die Dateinamen ihn nennen, steht im Tooltip.", width: "12rem",
      sort: ->(chain) { Wsjrdp2027::RegistrationDocuments::KEYS.index(chain.key) }, default: true
    c.column key: "files", abbr: "f", label: "Dateien",
      header_tooltip: "Jede Datei, die die Spalte je hatte, auch ältere, ersetzte Versionen.", numeric: true, width: "6rem",
      sort: ->(chain) { chain.entries.size }, sort_first: "desc", default: true
    c.column key: "registered", abbr: "r", label: "registriert",
      header_tooltip: "Dateien, die schon eine Zeile in den Dokumenten haben.", numeric: true, width: "6.5rem",
      sort: ->(chain) { chain.registered_count }, sort_first: "desc", default: true
    c.column key: "missing", abbr: "m", label: "fehlen",
      header_tooltip: "In den Versionen oder der Spalte genannt, aber nicht mehr im Ordner. Sie bekommen eine Zeile ohne Datei.", numeric: true, width: "5.5rem",
      sort: ->(chain) { chain.missing_count }, sort_first: "desc", default: true
    c.column key: "state", abbr: "st", label: "Stand",
      header_tooltip: "nicht registriert, unvollständig (nicht mehr auf dem Stand) oder vollständig", width: "9rem",
      sort: ->(chain) { STATE_ORDER.index(chain.state.to_s) }, default: true
  end
end
