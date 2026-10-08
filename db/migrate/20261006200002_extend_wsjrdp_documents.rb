# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class ExtendWsjrdpDocuments < ActiveRecord::Migration[7.1]
  def change
    # bigint like the ids it is referenced by; the sequence goes along.
    reversible do |direction|
      direction.up do
        change_column :wsjrdp_documents, :id, :bigint
        execute "ALTER SEQUENCE wsjrdp_documents_id_seq AS bigint"
      end
      direction.down do
        execute "ALTER SEQUENCE wsjrdp_documents_id_seq AS integer"
        change_column :wsjrdp_documents, :id, :integer
      end
    end

    remove_index :wsjrdp_documents, [:subject_id, :subject_type, :key, :secondary_key],
      name: "idx_on_subject_id_subject_type_key_secondary_key_390fd9927a",
      unique: true, where: "deleted_at IS NULL"
    remove_index :wsjrdp_documents, [:subject_id, :subject_type, :deleted_at],
      name: "idx_on_subject_id_subject_type_deleted_at_5207dd0233"

    # Relative to the upload root, <wagon>/private/uploads.
    rename_column :wsjrdp_documents, :storage_file_path, :relative_storage_file_path
    # Where the file lay when the row was written, in that installation.
    add_column :wsjrdp_documents, :absolute_storage_file_path, :string, null: false
    change_column_default :wsjrdp_documents, :comment, from: nil, to: ""
    change_column_null :wsjrdp_documents, :comment, false, ""
    change_column_null :wsjrdp_documents, :additional_info, false, {}

    # current, superseded or deleted. superseded_at, deleted_at and
    # replaces_id stay when the status changes later on.
    add_column :wsjrdp_documents, :status, :string, null: false, default: "current"
    add_column :wsjrdp_documents, :superseded_at, :datetime
    # On the newer document: the one it follows, superseded or deleted.
    add_reference :wsjrdp_documents, :replaces,
      foreign_key: {to_table: :wsjrdp_documents, on_delete: :nullify}

    add_column :wsjrdp_documents, :key_number, :integer, null: false, default: 0
    add_reference :wsjrdp_documents, :key_ref, polymorphic: true
    add_column :wsjrdp_documents, :secondary_key_number, :integer, null: false, default: 0
    add_reference :wsjrdp_documents, :secondary_key_ref, polymorphic: true

    # A derivation carries the keys of its original and goes with it.
    add_reference :wsjrdp_documents, :derived_from,
      foreign_key: {to_table: :wsjrdp_documents, on_delete: :cascade}
    add_column :wsjrdp_documents, :derivation_key, :string

    # The date of the document itself (sent, signed, receipt date), apart from
    # its upload.
    add_column :wsjrdp_documents, :document_date, :date
    # ui, api or import; the API key of an api upload.
    add_column :wsjrdp_documents, :origin, :string, null: false, default: "ui"
    add_reference :wsjrdp_documents, :origin_service_token, type: :integer,
      foreign_key: {to_table: :service_tokens, on_delete: :nullify}
    add_column :wsjrdp_documents, :content_sha256, :string

    # Who may read (download), write (upload, replace, change the metadata)
    # and delete (hide) the document; one entry suffices.
    add_column :wsjrdp_documents, :readable_by, :string, array: true, null: false, default: %w[person log]
    add_column :wsjrdp_documents, :writable_by, :string, array: true, null: false, default: %w[person log]
    add_column :wsjrdp_documents, :deletable_by, :string, array: true, null: false, default: %w[log]

    add_index :wsjrdp_documents,
      [:subject_type, :subject_id, :key, :key_number, :secondary_key, :secondary_key_number,
        :derived_from_id, :derivation_key],
      name: "index_wsjrdp_documents_current", unique: true, nulls_not_distinct: true,
      where: "status = 'current'"
    add_index :wsjrdp_documents, :relative_storage_file_path, unique: true
    add_index :wsjrdp_documents, :absolute_storage_file_path
    add_index :wsjrdp_documents, [:subject_type, :subject_id, :status],
      name: "index_wsjrdp_documents_on_subject_and_status"
    add_index :wsjrdp_documents, :content_sha256

    add_check_constraint :wsjrdp_documents, "key_number >= 0",
      name: "chk_wsjrdp_documents_key_number"
    add_check_constraint :wsjrdp_documents, "secondary_key_number >= 0",
      name: "chk_wsjrdp_documents_secondary_key_number"
    add_check_constraint :wsjrdp_documents, "derived_from_id IS NULL OR derivation_key IS NOT NULL",
      name: "chk_wsjrdp_documents_derivation_key"
    add_check_constraint :wsjrdp_documents, "content_sha256 IS NULL OR content_sha256 ~ '^[0-9a-f]{64}$'",
      name: "chk_wsjrdp_documents_content_sha256"
  end
end
