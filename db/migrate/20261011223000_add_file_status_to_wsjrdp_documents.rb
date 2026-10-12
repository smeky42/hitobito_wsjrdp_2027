# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class AddFileStatusToWsjrdpDocuments < ActiveRecord::Migration[7.1]
  def change
    # Whether the file of the document exists (WsjrdpDocument::FILE_STATUSES,
    # checked by the model, not the database): present or missing; a missing
    # file keeps its row (and its name), e.g. a registration upload whose file
    # is gone. Apart from status, which is about versions.
    add_column :wsjrdp_documents, :file_status, :string, null: false, default: "present"
    # When the file was last found present or missing.
    add_column :wsjrdp_documents, :file_checked_at, :datetime, null: true
    # Unknown for a missing file.
    change_column_null :wsjrdp_documents, :byte_size, true

    add_check_constraint :wsjrdp_documents, "file_status = 'missing' OR byte_size IS NOT NULL",
      name: "chk_wsjrdp_documents_byte_size"

    # A document without a kind (WsjrdpDocumentKind) and without lists given
    # has restricted access.
    change_column_default :wsjrdp_documents, :readable_by, from: %w[person log], to: %w[log]
    change_column_default :wsjrdp_documents, :writable_by, from: %w[person log], to: []
    change_column_default :wsjrdp_documents, :deletable_by, from: %w[log], to: []
  end
end
