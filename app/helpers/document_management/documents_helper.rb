# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The cells of the Dokumente list (document_management/documents/index) and the
# values of a document's page (document_management/documents/_detail).
module DocumentManagement::DocumentsHelper
  # The widget's column Hashes, the full set (the columns menu picks from it).
  def document_table_columns(people_by_id)
    kinds = WsjrdpDocumentKind.all.index_by { |kind| [kind.subject_type, kind.key, kind.secondary_key] }
    cells = {
      "id" => ->(document) { document.id },
      "subject" => ->(document) { document_subject(document, people_by_id) },
      "kind" => ->(document) {
        kind = kinds[[document.subject_type, document.key, document.secondary_key]]
        document_kind_link(document, kind, title: document_kind_title(document, kind))
      },
      "key" => ->(document) { document_key_label(document) },
      "secondary_key" => ->(document) { document_secondary_key_label(document) },
      "derivation_key" => ->(document) { document.derivation_key },
      "status" => ->(document) { document_status_cell(document.status) },
      "file_status" => ->(document) { document_file_status_icon(document.file_status) },
      "filename" => ->(document) { document.filename },
      "content_type" => ->(document) { document_type_cell(document.content_type) },
      "byte_size" => ->(document) { document.byte_size && number_to_human_size(document.byte_size) },
      "origin" => ->(document) { document_origin_label(document.origin) },
      "created_at" => ->(document) { document_time(document.created_at) },
      "author" => ->(document) { document_author(document, people_by_id) }
    }
    DocumentManagement::DocumentsColumns::COLUMNS.map { |col| col.to_table_column(cell: cells.fetch(col.key)) }
  end

  # The column Hashes of a versions table (documents/_versions_table): L and
  # R pick the comparison's sides (`pair`, the comparison `preview_id`,
  # documents/_preview); the numbers only `with_numbers` (a group of several
  # combinations); `people` the uploaders by id.
  def document_version_table_columns(pair, preview_id, people:, with_numbers:)
    scope = "document_management.document"
    radio = ->(side, picked) {
      ->(document) {
        tag.input(type: "radio", class: "form-check-input", name: "#{preview_id}-#{side}", value: document.id,
          checked: document == picked, data: {preview_side: side, preview: preview_id},
          "aria-label": "#{t("#{scope}.compare_#{side}")}: ##{document.id}")
      }
    }
    cells = {
      "compare_left" => radio.call(:left, pair.first),
      "compare_right" => radio.call(:right, pair.last),
      "id" => ->(document) { content_tag(:span, document.id, class: "font-monospace") },
      "numbers" => ->(document) { content_tag(:span, document_numbers_label(document), class: "font-monospace") },
      "created_at" => ->(document) { document_time(document.created_at) },
      "status" => ->(document) { document_status_cell(document.status) },
      "superseded_at" => ->(document) { document_ended(document, %w[superseded_at]) },
      "deleted_at" => ->(document) { document_ended(document, %w[deleted_at]) },
      "file_status" => ->(document) { document_file_status_icon(document.file_status) },
      "author" => ->(document) { document_author(document, people) },
      "filename" => ->(document) { document.filename },
      "content_type" => ->(document) { document_type_cell(document.content_type) },
      "byte_size" => ->(document) { document.byte_size && number_to_human_size(document.byte_size) },
      "origin" => ->(document) { document_origin_label(document.origin) }
    }
    ended = ->(document, keys) { document_ended(document, keys) }
    columns = DocumentManagement::DocumentVersionsColumns::COLUMNS.map do |col|
      col.to_table_column(cell: cells.fetch(col.key), merged_cell: (ended if col.merge))
    end
    with_numbers ? columns : columns.reject { |col| col[:key] == "numbers" }
  end

  # The footer cell of a versions table column: below L and R the button that
  # takes the pick back (shown once picked, documents/_preview).
  def document_version_compare_clear(col, pair, preview_id)
    side = {"compare_left" => :left, "compare_right" => :right}[col[:key]]
    return nil unless side

    label = t("document_management.document.compare_clear_#{side}")
    content_tag(:button, icon(:times), type: "button", class: "btn btn-link btn-sm p-0",
      hidden: pair[(side == :left) ? 0 : 1].nil?, title: label, "aria-label": label,
      data: {preview: preview_id, preview_clear: side})
  end

  # When a document was replaced (an arrow up: the replacing version stands
  # above it) and deleted (a ban sign), of `fields` (superseded_at,
  # deleted_at), a line each with its time; nil for neither.
  def document_ended(document, fields = %w[superseded_at deleted_at])
    marks = {"superseded_at" => [:superseded, :"level-up-alt", "text-muted"],
             "deleted_at" => [:deleted, :ban, "text-danger"]}
    lines = fields.filter_map do |field|
      time = document.public_send(field)
      next unless time

      name, glyph, color = marks.fetch(field)
      content_tag(:div, title: t("document_management.document.end.#{name}_at", time: document_time(time))) do
        safe_join([content_tag(:span, icon(glyph), class: ["document-rows-end-icon", color]), document_time(time)])
      end
    end
    safe_join(lines).presence
  end

  # The key with its number, as the file name writes it.
  def document_key_label(document)
    content_tag(:span, document_part(document.key, document.key_number), class: "font-monospace")
  end

  # The keys with their numbers as a file name writes them, e.g.
  # "deregistration-2--signed_form-3".
  def document_numbers_label(document)
    second = document_part(document.secondary_key, document.secondary_key_number)
    [document_part(document.key, document.key_number), second].compact.join("--")
  end

  def document_secondary_key_label(document)
    part = document_part(document.secondary_key, document.secondary_key_number)
    part && content_tag(:span, part, class: "font-monospace")
  end

  # The label of the document's kind, linked to the kind; "unbekannt" without
  # one. `title` becomes the tooltip.
  def document_kind_link(document, kind = WsjrdpDocumentKind.for_document(document), title: nil)
    unless kind
      return content_tag(:span, t("document_management.unknown_kind"), class: "text-muted", title: title)
    end

    link_to(kind.label, document_management_document_kind_path(kind), title: title, data: {turbo_frame: "_top"})
  end

  # The tooltip of the kind in the list: the kind's label, key and secondary
  # key, each on a line.
  def document_kind_title(document, kind)
    scope = "document_management.document.fields"
    [[t("#{scope}.kind"), kind&.label || t("document_management.unknown_kind")],
      [t("#{scope}.key"), document_part(document.key, document.key_number)],
      [t("#{scope}.secondary_key"), document_part(document.secondary_key, document.secondary_key_number) || "—"]]
      .map { |label, value| "#{label}: #{value}" }.join("\n")
  end

  # The Typ cell: the icon of the type's file kind and its short name
  # (Wsjrdp2027::DocumentFileKinds), with the type -- after its name, if it
  # has one -- as tooltip. A type without a short name shows its subtype,
  # muted, cut off with an ellipsis where the column is too narrow; a
  # document without a type leaves the cell empty.
  def document_type_cell(content_type)
    return nil if content_type.blank?

    kinds = Wsjrdp2027::DocumentFileKinds
    short = kinds.short_label_for(content_type)
    name = kinds::TYPE_LABELS[content_type]
    content_tag(:span, class: ["d-inline-flex align-items-center gap-1 mw-100", ("text-muted" unless short)],
      title: name ? "#{name} – #{content_type}" : content_type) do
      safe_join([icon(kinds.icon_for(content_type)),
        content_tag(:span, short || content_type.split("/", 2).last, class: "text-truncate", style: "min-width: 0")])
    end
  end

  # The status, "aktuell" in green.
  def document_status_cell(status)
    label = document_status_label(status)
    (status == WsjrdpDocument::CURRENT) ? content_tag(:span, label, class: "text-success") : label
  end

  def document_part(key, number)
    return nil if key.blank? && number.to_i.zero?

    number.to_i.positive? ? "#{key}-#{number}" : key
  end

  def document_status_label(status)
    t("document_management.statuses.#{status}", default: status.to_s)
  end

  # The file status as an icon, its label as tooltip and accessible name: a
  # small grey tick for a file that is there, a red exclamation mark for one
  # that is missing, so the rare missing file stands out.
  def document_file_status_icon(status)
    label = t("document_management.file_statuses.#{status}", default: status.to_s)
    missing = status == WsjrdpDocument::FILE_MISSING
    content_tag(:span, document_mark(missing ? :missing : :ok), title: label, role: "img", "aria-label": label)
  end

  # A quiet status mark, each in a box of the same width so marks line up: a
  # thin grey tick (the text character; Font Awesome's free tick is bold)
  # for what is fine, a yellow or red exclamation mark for what is not.
  def document_mark(kind)
    box = "display: inline-block; width: 1.25em; text-align: center"
    case kind
    when :ok then content_tag(:span, "✓", class: "text-muted", style: box, "aria-hidden": "true")
    when :warning then content_tag(:span, icon(:"exclamation-circle"), class: "text-warning", style: box)
    else content_tag(:span, icon(:"exclamation-circle"), class: "text-danger", style: box)
    end
  end

  def document_file_status_label(status)
    label = t("document_management.file_statuses.#{status}", default: status.to_s)
    (status == WsjrdpDocument::FILE_MISSING) ? content_tag(:span, label, class: "text-danger") : label
  end

  def document_origin_label(origin)
    t("document_management.origins.#{origin}", default: origin.to_s)
  end

  # How the preview shows a document: :missing without a file, :image or
  # :frame for what the file route sends inline, :none for anything else.
  def document_preview_kind(document)
    return :missing if document.file_missing? || document.relative_storage_file_path.blank?
    return :none unless Wsjrdp::DocumentsController::INLINE_TYPES.include?(document.content_type)

    document.content_type.start_with?("image/") ? :image : :frame
  end

  # The two versions the comparison starts with, the ones the request names
  # (?left=&right=); nil for a side it does not name.
  def document_preview_pair(versions, params)
    by_id = versions.index_by { |version| version.id.to_s }
    [by_id[params[:left].to_s], by_id[params[:right].to_s]]
  end

  # With the year: documents span more than one.
  def document_time(time)
    time && l(time, format: "%d.%m.%Y %H:%M")
  end

  # The person a document is for, linked out of the row's frame like any
  # person; one that is gone by type and id, marked as not valid; any other
  # subject by type and id.
  def document_subject(document, people_by_id)
    document_party(document.subject_type, document.subject_id, people_by_id)
  end

  def document_author(document, people_by_id)
    document_party(document.author_type, document.author_id, people_by_id)
  end

  def document_party(type, id, people_by_id)
    return nil if id.nil?

    return "#{type} #{id}" unless type == "Person"

    person = people_by_id[id]
    return link_to(person.to_s, person_path(person), title: person.to_s, data: {turbo_frame: "_top"}) if person

    safe_join(["#{type} #{id}", content_tag(:span, "(#{t("document_management.invalid_party")})",
      class: "text-muted fw-light")], " ")
  end

  def document_lists(document)
    safe_join(%i[readable_by writable_by deletable_by].map do |list|
      content_tag(:div) do
        safe_join([content_tag(:span, t("document_management.lists.#{list}"), class: "text-muted me-2"),
          Array(document.public_send(list)).join(", ").presence || "—"])
      end
    end)
  end
end
