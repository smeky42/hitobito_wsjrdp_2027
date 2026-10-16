# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The cells of the tab Nach Person und Art of the main section Dokumente
# (document_management/document_groups/index).
module DocumentManagement::DocumentGroupsHelper
  # The widget's column Hashes, the full set (the columns menu picks from it).
  def document_group_table_columns
    cells = {
      "subject" => ->(group) { document_group_subject(group) },
      "kind" => ->(group) { document_group_kind(group) },
      "key" => ->(group) { content_tag(:span, group.key, class: "font-monospace") },
      "secondary_key" => ->(group) { document_group_secondary_key(group) },
      "count" => ->(group) { group.count },
      "current" => ->(group) { document_group_current(group) },
      "superseded" => ->(group) { group.superseded },
      "deleted" => ->(group) { group.deleted },
      "missing" => ->(group) { document_group_missing(group) },
      "first_at" => ->(group) { document_time(group.first_at) },
      "last_at" => ->(group) { document_time(group.last_at) },
      "bytes" => ->(group) { number_to_human_size(group.bytes) }
    }
    DocumentManagement::DocumentGroupsColumns::COLUMNS.map { |col| col.to_table_column(cell: cells.fetch(col.key)) }
  end

  # The person linked like any person; any other subject, or a person that
  # is gone, as in the list of documents (DocumentsHelper#document_party).
  def document_group_subject(group)
    people = group.subject ? {group.subject_id => group.subject} : {}
    document_party(group.subject_type, group.subject_id, people)
  end

  def document_group_kind(group)
    return content_tag(:span, t("document_management.unknown_kind"), class: "text-muted") unless group.kind

    link_to(group.label, document_management_document_kind_path(group.kind), data: {turbo_frame: "_top"})
  end

  def document_group_secondary_key(group)
    group.secondary_key.presence && content_tag(:span, group.secondary_key, class: "font-monospace")
  end

  # "2/3" then a mark, quiet like the file status (document_mark): a thin
  # grey tick when every combination has a current document, a yellow mark
  # when some have none, a red one when none has.
  def document_group_current(group)
    state = group.current_state
    label = t("document_management.document_group.current_#{state}", current: group.current,
      count: group.combinations)
    mark = document_mark({all: :ok, some: :warning, none: :error}.fetch(state))
    content_tag(:span, safe_join(["#{group.current}/#{group.combinations} ", mark]), title: label,
      "aria-label": label, style: "font-variant-numeric: tabular-nums; white-space: nowrap")
  end

  # The group's files like the file status in Alle (document_mark): a thin
  # grey tick when none is missing, a red mark when some are, their number in
  # front when more than one.
  def document_group_missing(group)
    label = t("document_management.document_group.missing_files", count: group.missing)
    parts = [(group.missing > 1) ? "#{group.missing} " : nil,
      document_mark(group.missing.zero? ? :ok : :error)].compact
    content_tag(:span, safe_join(parts), title: label, "aria-label": label,
      style: "font-variant-numeric: tabular-nums; white-space: nowrap")
  end

  # "Person · Art", the heading and title of a group's page.
  def document_group_title(group)
    subject = group.subject&.to_s || [group.subject_type, group.subject_id].compact.join(" ").presence
    [subject, group.label || t("document_management.unknown_kind")].compact.join(" · ")
  end

  # The tab Alle (/documents), filtered to the group's documents (within the
  # filter of `state`, if given): by person and kind -- for a group without a
  # kind by its keys, as "unbekannt" would take in the other unknown keys too.
  def document_group_documents_path(group, state = nil)
    schema = DocumentManagement::DocumentsFilterSchema
    subject = group.subject_id.nil? ? [] : [[["subject_id", "in", group.subject_id.to_s]]]
    kind = if group.kind
      [[["kind", "in", group.kind.keys_path]]]
    else
      [[["key", "in", group.key]],
        [["secondary_key", "in", group.secondary_key.presence || schema::NO_SECONDARY_KEY]]]
    end
    tree = (state ? state.filter.user_slots : []) + subject + kind
    rison = schema.encode_tree(tree, schema: schema.bound).to_s
    param = DocumentManagement::DocumentsController::POLICY.param_name(:filter)
    "#{document_management_documents_path}?#{param}=#{Wsjrdp::Filtering::UrlCodec.escape_for_query(rison)}"
  end
end
