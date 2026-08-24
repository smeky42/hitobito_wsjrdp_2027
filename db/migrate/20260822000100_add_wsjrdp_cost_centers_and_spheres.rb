# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class AddWsjrdpCostCentersAndSpheres < ActiveRecord::Migration[7.1]
  # Displayed total budget (generated column on both tables): the yearly sum or
  # the explicitly set total, whichever has the LARGER ABSOLUTE VALUE. A numeric
  # MAX would be wrong here: budgets are signed (expenses negative, income
  # positive), so MAX(-25850, -10000) would pick the smaller envelope.
  # All-years-NULL is detected via coalesce (generation expressions allow no
  # subqueries).
  EFFECTIVE_TOTAL_BUDGET_SQL = <<~SQL.squish
    CASE
      WHEN coalesce(budget_2025, budget_2026, budget_2027, budget_2028) IS NULL
        THEN explicit_total_budget
      WHEN explicit_total_budget IS NULL
        OR abs(coalesce(budget_2025, 0) + coalesce(budget_2026, 0)
             + coalesce(budget_2027, 0) + coalesce(budget_2028, 0)) > abs(explicit_total_budget)
        THEN coalesce(budget_2025, 0) + coalesce(budget_2026, 0)
           + coalesce(budget_2027, 0) + coalesce(budget_2028, 0)
      ELSE explicit_total_budget
    END
  SQL

  def change
    create_table :wsjrdp_cost_centers, id: :bigserial, force: :cascade,
                 comment: "cost centers (synced with both DATEV and Moss)" do |t|
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :updated_at, null: true

      t.string :number, null: false,
               comment: "Moss: cost center, DATEV: KOST2 (SKR42), KOST1 (SKR03)"
      t.string :name, null: true
      t.string :short_name, null: true
      t.string :moss_status, null: false, default: "active",
               comment: "Moss Status: active or deactivated"

      t.string :manager_name, null: true, comment: "cost center manager"
      t.bigint :manager_person_id, null: true, comment: "Optional n:1 (<-> people)"

      t.decimal :budget_2025, precision: 20, scale: 2, null: true,
        comment: "Signed budget 2025 (expenses negative); NULL = not set"
      t.decimal :budget_2026, precision: 20, scale: 2, null: true,
        comment: "Signed budget 2026 (expenses negative); NULL = not set"
      t.decimal :budget_2027, precision: 20, scale: 2, null: true,
        comment: "Signed budget 2027 (expenses negative); NULL = not set"
      t.decimal :budget_2028, precision: 20, scale: 2, null: true,
        comment: "Signed budget 2028 (expenses negative); NULL = not set"
      t.decimal :explicit_total_budget, precision: 20, scale: 2, null: true,
        comment: "Explicitly set total budget for the whole period; NULL = not set"
      t.virtual :effective_total_budget, type: :decimal, precision: 20, scale: 2,
        stored: true, as: EFFECTIVE_TOTAL_BUDGET_SQL,
        comment: "Displayed total: yearly sum or explicit_total_budget, whichever is larger in absolute value; generated, not writable"

      t.jsonb :additional_info, null: false, default: {},
              comment: "Reserved for future use"

      t.index :number, unique: true
      t.index :manager_person_id
    end
    add_foreign_key :wsjrdp_cost_centers, :people, column: :manager_person_id


    create_table :wsjrdp_spheres, id: :bigserial, force: :cascade,
                 comment: "tax spheres / cost carriers (synced with both DATEV and Moss)" do |t|
      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :updated_at, null: true

      t.string :number, null: false,
               comment: "Moss: cost carrier, DATEV: KOST1 (SKR42), implicit (SKR03)"
      t.string :name, null: true
      t.string :short_name, null: true
      t.string :moss_status, null: false, default: "active",
               comment: "Moss Status: active or deactivated"

      t.string :manager_name, null: true, comment: "sphere manager"
      t.bigint :manager_person_id, null: true, comment: "Optional n:1 (<-> people)"

      t.decimal :budget_2025, precision: 20, scale: 2, null: true,
        comment: "Signed budget 2025 (expenses negative); NULL = not set"
      t.decimal :budget_2026, precision: 20, scale: 2, null: true,
        comment: "Signed budget 2026 (expenses negative); NULL = not set"
      t.decimal :budget_2027, precision: 20, scale: 2, null: true,
        comment: "Signed budget 2027 (expenses negative); NULL = not set"
      t.decimal :budget_2028, precision: 20, scale: 2, null: true,
        comment: "Signed budget 2028 (expenses negative); NULL = not set"
      t.decimal :explicit_total_budget, precision: 20, scale: 2, null: true,
        comment: "Explicitly set total budget for the whole period; NULL = not set"
      t.virtual :effective_total_budget, type: :decimal, precision: 20, scale: 2,
        stored: true, as: EFFECTIVE_TOTAL_BUDGET_SQL,
        comment: "Displayed total: yearly sum or explicit_total_budget, whichever is larger in absolute value; generated, not writable"

      t.jsonb :additional_info, null: false, default: {},
              comment: "Reserved for future use"

      t.index :number, unique: true
      t.index :manager_person_id
    end
    add_foreign_key :wsjrdp_spheres, :people, column: :manager_person_id

    reversible do |dir|
      dir.up do
        execute(<<~SQL)
          INSERT INTO wsjrdp_spheres (number, name, short_name, moss_status, created_at) VALUES
            ('1', 'Ideeller Bereich',                  'Ideell',           'deactivated', CURRENT_TIMESTAMP),
            ('2', 'Vermögensverwaltung',               'Vermögen',         'deactivated', CURRENT_TIMESTAMP),
            ('3', 'Zweckbetrieb',                      'Zweckbetrieb',     'active',      CURRENT_TIMESTAMP),
            ('4', 'Wirtschaftlicher Geschäftsbetrieb', 'Wirtschaftlich',   'deactivated', CURRENT_TIMESTAMP),
            ('9', 'Sammelposten',                      'Sammel',           'deactivated', CURRENT_TIMESTAMP)
        SQL
      end
    end
  end
end
