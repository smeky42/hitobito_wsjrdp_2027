# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class AddWsjrdpConfigsDocumentsNotes < ActiveRecord::Migration[7.1]
  def change
    create_table "wsjrdp_documents", id: :serial, force: :cascade do |t|
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: true
      t.datetime :deleted_at, null: true
      t.bigint :subject_id, null: true
      t.string :subject_type, null: true, default: "Person"
      t.bigint :author_id, null: true
      t.string :author_type, null: true, default: "Person"
      t.string :key, null: false
      t.string :secondary_key, null: false, default: ""
      t.string :storage_file_path, null: false
      t.string :filename, null: false
      t.string :content_encoding, null: true
      t.string :content_type, null: false, default: "application/octet-stream"
      t.bigint :byte_size, null: false
      t.text :comment, null: true
      t.jsonb :additional_info, default: {}
    end
    add_index :wsjrdp_documents, [:author_type, :author_id]
    add_index :wsjrdp_documents, [:subject_id, :subject_type, :deleted_at]
    add_index :wsjrdp_documents, [:subject_id, :subject_type, :key, :secondary_key], unique: true, where: "deleted_at IS NULL"

    create_table "wsjrdp_notes", id: :serial, force: :cascade do |t|
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: true
      t.datetime :deleted_at, null: true
      t.bigint :subject_id, null: true
      t.string :subject_type, null: true
      t.bigint :author_id, null: true
      t.string :author_type, null: true, default: "Person"
      t.string :key, null: false, default: "generic"
      t.string :secondary_key, null: false, default: ""
      t.text :text
    end
    add_index :wsjrdp_notes, [:author_id, :author_type]
    add_index :wsjrdp_notes, [:subject_id, :subject_type, :deleted_at, :key, :secondary_key]

    create_table "wsjrdp_configs", id: :serial, force: :cascade do |t|
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: true
      t.boolean :active, null: false, default: true
      t.jsonb :config, null: false, default: {}
    end
    add_index :wsjrdp_configs, [:active], unique: true, where: "active"
    reversible do |direction|
      direction.up do
        execute <<-SQL
INSERT INTO wsjrdp_configs ("created_at", "active", "config") VALUES (NOW(), TRUE, '{"accounting_admins": [1, 2, 65]}'::jsonb);
        SQL
      end
    end
  end
end
