# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The Dokumente dataset (DocumentManagement::DocumentsController) for the
# generic CNF filter (doc/wsjrdp/generic_filter_builder.md): plain SQL on
# wsjrdp_documents.
#
# The quick filters (PRESETS): the status as an exclusive group, the documents
# whose file is missing, and the origin.
module DocumentManagement::DocumentsFilterSchema
  extend Wsjrdp::Filtering::FilterSchema

  STATUS_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    [WsjrdpDocument::CURRENT, WsjrdpDocument::SUPERSEDED, WsjrdpDocument::DELETED]
      .map { |status| [status, I18n.t("document_management.statuses.#{status}")] }
  })

  FILE_STATUS_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    WsjrdpDocument::FILE_STATUSES.map { |status| [status, I18n.t("document_management.file_statuses.#{status}")] }
  })

  ORIGIN_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    %w[ui api import].map { |origin| [origin, I18n.t("document_management.origins.#{origin}")] }
  })

  KEY_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    WsjrdpDocument.distinct.order(:key).pluck(:key).map { |key| [key, key] }
  })

  # "" (no secondary key) as "_none", which no key can be, labelled "(leer)".
  NO_SECONDARY_KEY = "_none"
  SECONDARY_KEY_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    WsjrdpDocument.distinct.order(:secondary_key).pluck(:secondary_key).map do |key|
      key.present? ? [key, key] : [NO_SECONDARY_KEY, I18n.t("document_management.empty_key")]
    end
  })

  # The kinds by their keys ("<key>" or "<key>/<secondary_key>",
  # WsjrdpDocumentKind#keys_path), so a filter reads alike in every database;
  # "_unknown", which no key can be, for the documents without one.
  UNKNOWN_KIND = "_unknown"
  KIND_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    WsjrdpDocumentKind.ordered.map { |kind| [kind.keys_path, kind.label] }.uniq(&:first) +
      [[UNKNOWN_KIND, I18n.t("document_management.unknown_kind")]]
  })

  DATE_OPERATORS = %i[gte lt between in_month in_year].freeze

  # The people documents are for: the short name with the nickname, the
  # role and the id ("YP 123") as its muted prefix. The picker's search finds
  # a name or a role; digits only look for the id, that id first, "#7" for
  # just that one (shared/wsjrdp/_chips_combobox_js).
  PERSON_OPTIONS = Wsjrdp::Filtering::Options.values(-> {
    Person.where(id: WsjrdpDocument.where(subject_type: "Person").select(:subject_id))
      .includes(:roles).order(:last_name, :first_name, :id)
      .map { |person| [person.id, person.short_full_name_with_nickname, "#{person.short_payment_role} #{person.id}"] }
  }, id_search: true)

  # A timestamp column as the date it falls on in the application's time zone.
  def self.local_date(column)
    zone = WsjrdpDocument.connection.quote(Time.zone.tzinfo.name)
    Arel.sql("((wsjrdp_documents.#{column} AT TIME ZONE 'UTC') AT TIME ZONE #{zone})::date")
  end

  SCHEMA = Wsjrdp::Filtering::Schema.define do |s|
    s.attribute key: :filename, short_key: :q, label: "Dateiname",
      type: Wsjrdp::Filtering::Types::TEXT, operators: Fin::DatevBookingsFilterSchema::TEXT_OPERATORS,
      column: ->(t) { [t[:filename], t[:relative_storage_file_path]] }
    s.attribute key: :subject_id, short_key: :sid, label: "Person",
      type: Wsjrdp::Filtering::Types::REFERENCE, operators: %i[in not_in],
      column: :subject_id, options: PERSON_OPTIONS,
      operator_labels: {in: {label_many: "ist eine von"}, not_in: {label_many: "ist keine von"}}
    s.attribute key: :kind, short_key: :kd, label: "Art",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: ->(_t) {
        Arel.sql("COALESCE(#{WsjrdpDocumentKind.document_column_sql(WsjrdpDocumentKind::KEYS_PATH_SQL)}, " \
          "'#{UNKNOWN_KIND}')")
      },
      options: KIND_OPTIONS
    s.attribute key: :key, short_key: :k, label: "Schlüssel",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: :key, options: KEY_OPTIONS
    s.attribute key: :key_number, short_key: :kn, label: "Schlüssel-Nr.",
      type: Wsjrdp::Filtering::Types::DECIMAL, operators: %i[eq between],
      column: :key_number
    s.attribute key: :secondary_key, short_key: :sk, label: "Unterschlüssel",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: ->(_t) {
        Arel.sql("COALESCE(NULLIF(wsjrdp_documents.secondary_key, ''), '#{NO_SECONDARY_KEY}')")
      },
      options: SECONDARY_KEY_OPTIONS
    s.attribute key: :secondary_key_number, short_key: :skn, label: "Unterschlüssel-Nr.",
      type: Wsjrdp::Filtering::Types::DECIMAL, operators: %i[eq between],
      column: :secondary_key_number
    s.attribute key: :status, short_key: :st, label: "Status",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: :status, options: STATUS_OPTIONS
    s.attribute key: :file_status, short_key: :fs, label: "Datei",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: :file_status, options: FILE_STATUS_OPTIONS
    s.attribute key: :origin, short_key: :or, label: "Herkunft",
      type: Wsjrdp::Filtering::Types::ENUM, operators: %i[in not_in],
      column: :origin, options: ORIGIN_OPTIONS
    s.attribute key: :created_at, short_key: :ca, label: "Hochgeladen",
      type: Wsjrdp::Filtering::Types::DATE, operators: DATE_OPERATORS,
      column: ->(_t) { local_date(:created_at) }
  end

  # The members' labels are document_management.statuses.* /
  # .file_statuses.* / .origins.* -- written out, because the constant is
  # built when the class loads.
  PRESETS = [
    {group: "status", attribute: "status", operator: "in", exclusive: true,
     members: [{key: "current", label: "aktuell", value: "current"},
       {key: "superseded", label: "ersetzt", value: "superseded"},
       {key: "deleted", label: "gelöscht", value: "deleted"}]},
    {key: "file_missing", label: "Datei fehlt", slots: [[["file_status", "in", "missing"]]]},
    {group: "origin", attribute: "origin", operator: "in", exclusive: true,
     members: [{key: "ui", label: "Oberfläche", value: "ui"},
       {key: "api", label: "API", value: "api"},
       {key: "import", label: "Import", value: "import"}]}
  ].freeze

  # The tab Nach Person und Art (DocumentManagement::DocumentGroupsController):
  # a group gathers every status and origin, so only Datei fehlt.
  GROUP_PRESETS = PRESETS.select { |preset| preset[:key] == "file_missing" }.freeze

  def self.bound(except: nil)
    SCHEMA.bind(WsjrdpDocument.all, except: except)
  end
end
