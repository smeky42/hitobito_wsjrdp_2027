# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Nach Person und Art", a tab of the main section Dokumente
# (/documents/by_person_and_kind), for admins: the documents grouped by
# subject, kind and numbers -- the versions of one person's document in a row
# (DocumentManagement::DocumentGroups), as an expandable table over an Array.
# Its filter is the one of the documents
# (DocumentManagement::DocumentsFilterSchema), applied before grouping. A row
# opens the group's page (show, /documents/by_person_and_kind/:id, the
# parameter of DocumentManagement::DocumentGroups) as its lazy detail: the
# group's versions with the comparison, and a link to them in the tab Alle.
# The versions are an expandable table of their own
# (DocumentManagement::VersionsTable), each opening the document's page
# without its versions as its lazy detail.
class DocumentManagement::DocumentGroupsController < ApplicationController
  include Wsjrdp::TableStateful
  include DocumentManagement::VersionsTable

  POLICY = wsjrdp_expandable_table_policy prefix: "",
    columns: DocumentManagement::DocumentGroupsColumns::COLUMNS.codec,
    # Unsorted: the latest upload first; ties as the rows' tiebreaker says.
    sort: {hidden: [["last_at", "desc"]]},
    cols: {default: DocumentManagement::DocumentGroupsColumns::COLUMNS.default_keys},
    per_page: {default: 50},
    filter: {policy: :remember, schema: DocumentManagement::DocumentsFilterSchema,
             presets: DocumentManagement::DocumentsFilterSchema::GROUP_PRESETS}

  before_action { authorize!(:manage_documents, WsjrdpDocument) }

  helper_method :groups

  def index
  end

  # A group: the page, or the lazy detail of its row. 404 for a parameter
  # that names no group with documents.
  def show
    slot = DocumentManagement::DocumentGroups.slot_from_param(params[:id])
    @document_group = slot && DocumentManagement::DocumentGroups.find(slot)
    raise ActiveRecord::RecordNotFound, "no document group #{params[:id]}" unless @document_group

    render layout: false if request.headers["Turbo-Frame"].present?
  end

  # Apply target of the filter builder (PRG, Wsjrdp::TableStateful).
  def apply
    wsjrdp_apply_table_filter(table_state, redirect_to: document_management_document_groups_path)
  end

  private

  def table_state = wsjrdp_expandable_table_state(POLICY)

  def groups
    @groups ||= Wsjrdp::ExpandableTableRows.new(table_state,
      DocumentManagement::DocumentGroups.groups(table_state.filter.scope(WsjrdpDocument.all)),
      sort: DocumentManagement::DocumentGroupsColumns::COLUMNS.sort_expressions,
      # After any sort: by person, then by the kind's position.
      tiebreaker: ->(group) { group.tiebreak_key })
  end
end
