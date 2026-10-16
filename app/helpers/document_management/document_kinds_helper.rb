# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The cells of the tab Dokument-Arten (document_management/document_kinds).
module DocumentManagement::DocumentKindsHelper
  # The widget's column Hashes (DocumentManagement::DocumentKindsColumns).
  def document_kind_table_columns
    cells = {
      "position" => ->(kind) { kind.position },
      "label" => ->(kind) { kind.label },
      "key" => ->(kind) { content_tag(:span, kind.key, class: "font-monospace small") },
      "secondary_key" => ->(kind) { content_tag(:span, kind.secondary_key, class: "font-monospace small") },
      "subject_type" => ->(kind) { kind.subject_type },
      "rights" => ->(kind) { document_kind_rights(kind) },
      "files" => ->(kind) { document_kind_files(kind) },
      "role_rules" => ->(kind) { document_kind_rules(kind) },
      "documents" => ->(kind) { document_counts[[kind.subject_type, kind.key, kind.secondary_key]].to_i }
    }
    name = ->(kind, keys) { document_kind_label(kind, keys) }
    DocumentManagement::DocumentKindsColumns::COLUMNS.map do |col|
      col.to_table_column(cell: cells.fetch(col.key),
        merged_cell: (name if col.merge == DocumentManagement::DocumentKindsColumns::NAME))
    end
  end

  RULES_SHOWN = 2
  FILE_TYPES_IN_TIP = 10

  # The shared cell of label and keys: the label (hyphenated where it must
  # break), the keys small below it -- those of `keys` that are shown.
  def document_kind_label(kind, keys)
    shown = [(kind.key if keys.include?("key")), (kind.secondary_key.presence if keys.include?("secondary_key"))]
      .compact
    safe_join([(content_tag(:div, kind.label, class: "dk-name-label") if keys.include?("label")),
      (content_tag(:div, shown.join(" · "), class: "font-monospace small text-muted dk-name-keys") if shown.any?)]
      .compact)
  end

  # One entry of a rights list, written out.
  def document_kind_entry(entry) = content_tag(:span, entry, class: "dk-entry")

  def document_kind_entries(entries) = safe_join(Array(entries).map { |entry| document_kind_entry(entry) }, " ")

  # A line per right -- lesen, schreiben, löschen --, rights with the same
  # list sharing one ("schreiben · löschen"); an empty list is the system's.
  # Each line runs on: the verb, then its entries, wrapping like text.
  def document_kind_rights(kind)
    lines = []
    WsjrdpDocumentKind::LISTS.each do |list|
      entries = Array(kind.public_send(list))
      line = lines.find { |line| entries.any? && line[:entries] == entries }
      line ? line[:verbs] << list : lines << {verbs: [list], entries: entries}
    end
    scope = "document_management.document_kinds.rights"
    safe_join(lines.map do |line|
      verbs = line[:verbs].map { |list| t("#{scope}.#{list}") }.join(" · ")
      entries = line[:entries].any? ? document_kind_entries(line[:entries]) :
        content_tag(:span, t("#{scope}.system"), class: "dk-system")
      content_tag(:div, safe_join([content_tag(:span, verbs, class: "dk-verb"), entries], " "), class: "dk-rights-line")
    end)
  end

  FILE_FAMILIES = [
    [->(type) { type.start_with?("image/") }, :"file-image"],
    [->(type) { type == "application/pdf" }, :"file-pdf"],
    [->(type) { type.start_with?("text/") }, :"file-alt"],
    [->(type) { type.start_with?("audio/") }, :"file-audio"],
    [->(type) { type.start_with?("video/") }, :"file-video"],
    [->(_type) { true }, :file]
  ].freeze

  # The accepted types as families (an icon each, with the number of types
  # when more than one); the tooltip lists types and extensions. The kind's
  # own size limit beside them.
  def document_kind_files(kind)
    types = Array(kind.content_types)
    size = kind.max_upload_size_mb && content_tag(:span, "≤ #{kind.max_upload_size_mb} MB", class: "small text-muted")
    if types.empty? && Array(kind.extensions).empty?
      return safe_join([content_tag(:span, t("document_management.document_kinds.any_file"), class: "text-muted"), size].compact, " ")
    end

    families = types.group_by { |type| FILE_FAMILIES.find { |test, _| test.call(type) }.last }
    families = {file: []} if families.empty?
    icons = families.map do |family, list|
      safe_join([icon(family), (content_tag(:span, list.size, class: "small text-muted") if list.size > 1)].compact)
    end
    tip = content_tag(:span, safe_join(icons, " "), class: "wsjrdp-html-tip dk-files",
      title: (types + Array(kind.extensions).map { |ext| ".#{ext}" }).join(", "),
      data: {bs_title: document_kind_files_tip(kind)})
    safe_join([tip, size].compact, " ")
  end

  # The tooltip of the files: up to FILE_TYPES_IN_TIP types with their
  # extensions, the extensions no type stands for, the size limit.
  def document_kind_files_tip(kind)
    types = Array(kind.content_types)
    extensions = Array(kind.extensions)
    lines = types.first(FILE_TYPES_IN_TIP).map do |type|
      own = extensions.select { |ext| Marcel::MimeType.for(name: "x.#{ext}") == type }
      content_tag(:div, safe_join([content_tag(:span, type, class: "font-monospace"),
        content_tag(:span, own.map { |ext| ".#{ext}" }.join(" "), class: "wsjrdp-tip-muted")], " "))
    end
    scope = "document_management.document_kinds.files_tip"
    lines << content_tag(:div, t("#{scope}.more", count: types.size - FILE_TYPES_IN_TIP), class: "wsjrdp-tip-muted") if types.size > FILE_TYPES_IN_TIP
    lone = extensions.reject { |ext| types.include?(Marcel::MimeType.for(name: "x.#{ext}")) }
    lines << content_tag(:div, t("#{scope}.extensions", list: lone.map { |ext| ".#{ext}" }.join(" "))) if lone.any? && types.any?
    lines << content_tag(:div, t("#{scope}.only_extensions", list: lone.map { |ext| ".#{ext}" }.join(" "))) if types.empty?
    lines << content_tag(:div, kind.max_upload_size_mb ? t("#{scope}.max", size: kind.max_upload_size_mb) : t("#{scope}.general_max"),
      class: "wsjrdp-tip-muted")
    content_tag(:div, safe_join(lines), class: "dk-files-tip").to_str
  end

  # The first RULES_SHOWN rules written out, one line each; how many more.
  def document_kind_rules(kind)
    rules = Array(kind.role_rules)
    scope = "document_management.document_kinds.summary"
    return content_tag(:span, t("#{scope}.none"), class: "text-muted small") if rules.empty?

    lines = rules.first(RULES_SHOWN).map { |rule| content_tag(:div, document_kind_rule(rule), class: "dk-rule") }
    if rules.size > RULES_SHOWN
      lines << content_tag(:div, t("#{scope}.more", count: rules.size - RULES_SHOWN), class: "small text-muted")
    end
    safe_join(lines)
  end

  # One rule: its roles, Pflicht, who it is offered to, the statuses it is
  # not offered in, the tag that marks it missing -- statuses as ranges in
  # their order (document_kind_statuses).
  def document_kind_rule(rule)
    scope = "document_management.document_kinds.summary"
    roles = Array(rule["roles"]).presence || [t("#{scope}.all_roles")]
    parts = []
    parts << content_tag(:span, t("#{scope}.required"), class: "dk-required") if rule["required"] == true
    offer_to = Array(rule["offer_to"])
    parts << (offer_to.any? ? safe_join([t("#{scope}.offered_to"), " ", document_kind_entries(offer_to)]) :
      content_tag(:span, t("#{scope}.not_offered"), class: "text-muted"))
    if rule["not_for_status"].present?
      parts << safe_join([t("#{scope}.not_in"), " ", document_kind_statuses(rule["not_for_status"])])
    end
    if (tag = rule["missing_tag"])
      tag_parts = [content_tag(:span, tag["tag"], class: "dk-tag")]
      tag_parts += [" ", t("#{scope}.from"), " ", document_kind_statuses(tag["from_status"])] if tag["from_status"].present?
      tag_parts << " · #{t("#{scope}.removed_on_upload")}" if tag["remove_on_upload"]
      parts << safe_join(tag_parts)
    end
    safe_join([safe_join(roles.map { |role| content_tag(:span, role, class: "dk-role") }, " "), " ",
      safe_join(parts, " · ")])
  end

  # Statuses in their order (Settings.status), each as an outlined chip with
  # its name as the tooltip; runs of three and more as "first … last".
  def document_kind_statuses(statuses)
    names = Settings.status.to_h.transform_keys(&:to_s)
    order = names.keys
    indexes = Array(statuses).map { |status| order.index(status.to_s) }.compact.sort
    chip = ->(index) { content_tag(:span, order[index], class: "dk-status", title: names[order[index]]) }
    runs = indexes.slice_when { |a, b| b != a + 1 }.flat_map do |run|
      (run.size >= 3) ? [safe_join([chip.call(run.first), chip.call(run.last)], " … ")] : run.map(&chip)
    end
    safe_join(runs, ", ")
  end
end
