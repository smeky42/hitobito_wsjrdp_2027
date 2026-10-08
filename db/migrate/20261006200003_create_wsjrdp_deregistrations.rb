# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class CreateWsjrdpDeregistrations < ActiveRecord::Migration[7.1]
  def change
    create_table :wsjrdp_deregistrations do |t|
      # No foreign key: the row keeps the id of a deleted person.
      t.integer :person_id, null: false
      # Counts the rows of a person, a replacing row included.
      t.integer :number, null: false
      t.string :status, null: false, default: "recorded"
      # On a row replacing another one.
      t.references :replaces, null: true, foreign_key: {to_table: :wsjrdp_deregistrations, on_delete: :nullify}
      t.string :kind, null: false, default: "withdrawal"
      t.string :issue, null: true
      t.date :requested_date, null: true
      t.date :effective_date, null: true
      t.date :reply_due_date, null: true
      t.decimal :actual_compensation, null: true, precision: 20, scale: 3
      t.string :actual_compensation_currency, null: false, default: "EUR"
      t.boolean :show_contractual_compensation, null: false, default: true
      t.jsonb :form_options, null: false, default: {}
      # When the form went out; from then on the row is fixed.
      t.datetime :form_sent_at, null: true
      # What the made form says beyond the columns: the person's role and
      # team or unit, the deadline, the compensation and the figures.
      t.jsonb :form_snapshot, null: false, default: {}
      # The form as it was sent and as it came back signed.
      t.references :sent_form_document, null: true, foreign_key: {to_table: :wsjrdp_documents, on_delete: :nullify}
      t.references :signed_form_document, null: true, foreign_key: {to_table: :wsjrdp_documents, on_delete: :nullify}
      # When the signed form came in, apart from its upload.
      t.datetime :signed_form_received_at, null: true
      # Set when the row reaches a final status.
      t.datetime :closed_at, null: true
      t.text :comment, null: false, default: ""
      t.jsonb :additional_info, null: false, default: {}
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :updated_at, null: true

      t.index [:person_id, :number], unique: true
      t.index :status
      t.check_constraint "number >= 1", name: "chk_wsjrdp_deregistrations_number"
    end

    create_table :wsjrdp_deregistration_events do |t|
      t.references :deregistration, null: false, index: false,
        foreign_key: {to_table: :wsjrdp_deregistrations, on_delete: :cascade}
      # create, update or notify; what for in action.
      t.string :event, null: false
      t.string :action, null: true
      t.string :from_status, null: true
      t.string :to_status, null: true
      t.datetime :occurred_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      # No foreign key: the row keeps the id of a deleted actor.
      t.string :actor_type, null: true, default: "Person"
      t.bigint :actor_id, null: true
      t.text :comment, null: false, default: ""
      # {"attribute": [before, after]}
      t.jsonb :field_changes, null: false, default: {}
      t.jsonb :additional_info, null: false, default: {}
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :updated_at, null: true

      t.index [:deregistration_id, :occurred_at], name: "index_wsjrdp_deregistration_events_on_deregistration"
      t.index [:actor_type, :actor_id], name: "index_wsjrdp_deregistration_events_on_actor"
      t.index :event
      t.index :action
    end
  end
end
