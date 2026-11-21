# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The table of the credential store. One row represents one version of
# one account in one stage. Its fields that are not secret are stored as
# plain values, each secret field is sealed by itself with the version's
# key, a key of that stage.
class CreateWsjrdpCredentials < ActiveRecord::Migration[7.1]
  def change
    create_table :wsjrdp_credentials,
      comment: "Credentials to access outside services" do |t|
      # which account
      t.string :kind, null: false
      t.string :account_key, null: false, comment: "Names the account within its kind"
      t.string :stage, null: false, comment: "Stage the version works in, e.g. production"
      t.text :comment, null: false, default: "", comment: "Comment on this version"

      # the version
      t.string :name, null: true, comment: "Optional name of the version, e.g. the key's name at the provider"
      t.jsonb :public_data, null: false, default: {}
      t.jsonb :secret_data, null: false, default: {},
        comment: "The secret fields, each sealed by itself with the version's key"

      # encryption information
      t.string :scheme, null: false, comment: "How secret_data is sealed: rails-me-v1"
      t.string :encryption_key_fingerprint, null: false,
        comment: "Fingerprint of the key that sealed secret_data: hex(SHA-256(its 64 hex digits, lower-case))"
      t.string :encryption_key_label, null: true, comment: "Label of the encryption key"

      # validity
      t.datetime :valid_from, null: true
      t.datetime :expires_at, null: true
      t.datetime :revoked_at, null: true

      # reminder: data only, no mail is sent yet
      t.integer :remind_days_before, array: true, null: false, default: [],
        comment: "Lead times in days, e.g. {30,14,3}; empty = the kind's default"
      t.string :remind_emails, array: true, null: false, default: [], comment: "Free mail addresses"
      t.datetime :reminded_at, array: true, null: false, default: [],
        comment: "Reserved: one entry per reminder mail that went out"

      # feedback from use
      t.datetime :last_success_at, null: true
      t.datetime :last_failure_at, null: true
      t.text :last_failure_message, null: true

      t.bigint :author_id, null: true
      t.string :author_type, null: true, default: "Person"
      t.jsonb :additional_info, null: false, default: {}, comment: "Reserved for future use"
      t.timestamps
    end
    add_index :wsjrdp_credentials, [:stage, :kind, :account_key]
    add_index :wsjrdp_credentials, [:author_type, :author_id]
  end
end
