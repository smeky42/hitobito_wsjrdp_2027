# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The versions table of a document or a document group
# (documents/_versions_table): its state (VERSIONS_POLICY, prefix "v") and
# #document_versions_rows, for each controller whose pages show one.
module DocumentManagement::VersionsTable
  extend ActiveSupport::Concern

  included do
    include Wsjrdp::TableStateful

    # All on one page, in the given order until a column sorts them.
    const_set(:VERSIONS_POLICY, wsjrdp_expandable_table_policy(prefix: "v",
      columns: DocumentManagement::DocumentVersionsColumns::COLUMNS.codec,
      cols: {default: DocumentManagement::DocumentVersionsColumns::COLUMNS.default_keys},
      per_page: {default: :all}))

    helper_method :document_versions_rows
  end

  private

  # The rows of a versions table over `versions` (an Array in their order).
  def document_versions_rows(versions)
    order = versions.each_with_index.to_h
    Wsjrdp::ExpandableTableRows.new(wsjrdp_expandable_table_state(self.class::VERSIONS_POLICY), versions,
      sort: DocumentManagement::DocumentVersionsColumns::COLUMNS.sort_expressions,
      tiebreaker: ->(document) { order[document] })
  end
end
