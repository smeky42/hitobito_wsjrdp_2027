# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Dokumente", a tab of the main section Dokumente (/documents), for admins:
# every stored document (WsjrdpDocument), whatever its status, as an
# expandable table. A document's page (/documents/:id/details) shows its
# metadata, lists and versions (DocumentManagement::VersionsTable); it is
# also the lazy detail of its row. The
# file itself is /documents/:id (Wsjrdp::DocumentsController).
class DocumentManagement::DocumentsController < ApplicationController
  include Wsjrdp::TableStateful
  include DocumentManagement::VersionsTable

  POLICY = wsjrdp_expandable_table_policy prefix: "",
    columns: DocumentManagement::DocumentsColumns::COLUMNS.codec,
    sort: {hidden: [["created_at", "desc"]]},
    cols: {default: DocumentManagement::DocumentsColumns::COLUMNS.default_keys},
    per_page: {default: 50},
    filter: {policy: :remember, schema: DocumentManagement::DocumentsFilterSchema,
             presets: DocumentManagement::DocumentsFilterSchema::PRESETS},
    pane: {default: 0}

  before_action { authorize!(:manage_documents, WsjrdpDocument) }

  helper_method :documents, :people_by_id

  def index
  end

  # A document: the page, or the lazy detail of its row.
  def show
    @document = WsjrdpDocument.find(params[:id])
    render layout: false if request.headers["Turbo-Frame"].present?
  end

  # Apply target of the filter builder (PRG, Wsjrdp::TableStateful).
  def apply
    wsjrdp_apply_table_filter(table_state, redirect_to: document_management_documents_path)
  end

  private

  def table_state = wsjrdp_expandable_table_state(POLICY)

  def documents
    @documents ||= Wsjrdp::ExpandableTableRows.new(table_state,
      table_state.filter.scope(WsjrdpDocument.all),
      sort: DocumentManagement::DocumentsColumns::COLUMNS.sort_expressions,
      # After any chosen sort: the newest upload first, then the highest id.
      tiebreaker: "wsjrdp_documents.created_at DESC, wsjrdp_documents.id DESC")
  end

  # The people of the shown rows (subjects and authors), by id.
  def people_by_id
    @people_by_id ||= begin
      rows = documents.page.to_a
      ids = rows.select { |document| document.subject_type == "Person" }.map(&:subject_id) +
        rows.select { |document| document.author_type == "Person" }.map(&:author_id)
      Person.where(id: ids.compact.uniq).index_by(&:id)
    end
  end
end
