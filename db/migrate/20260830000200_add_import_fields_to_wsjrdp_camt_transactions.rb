# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class AddImportFieldsToWsjrdpCamtTransactions < ActiveRecord::Migration[7.1]
  def change
    change_table :wsjrdp_camt_transactions do |t|
      t.bigint :imported_subject_id, null: true, comment: "Person derived at import time"
      t.string :imported_subject_type, null: true, comment: "Polymorphic type for imported_subject_id (usually 'Person')"
      t.jsonb :imported_subject_link_meta, null: false, default: {}, comment: "Link metadata for imported_subject_id"

      t.jsonb :subject_link_meta, null: false, default: {}, comment: "Link metadata for subject_id"

      t.string :category, null: true
      t.string :sub_category, null: true

      t.string :source_file, null: true, comment: "CAMT file that inserted or last genuinely changed this row"
    end
  end
end
