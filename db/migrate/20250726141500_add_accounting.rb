# frozen_text_literal: true

class AddAccounting < ActiveRecord::Migration[4.2]
    def change
      create_table "accounting_entries", id: :integer, force: :cascade do |t|
        t.integer "subject_id", null: false
        t.integer "author_id", null: false
        t.integer "ammount", null: false
        t.text "comment", size: :medium
        t.datetime "created_at"
        t.index ["subject_id"], name: "index_accounting_on_subject_id"
      end
    end
  end