# frozen_string_literal: true

class AddJamboreeDataToPeople < ActiveRecord::Migration[7.1]
  def change
    add_column :people, :jamboree_data, :jsonb, default: {}, null: false
    add_column :people, :jamboree_data_confirmed, :boolean, default: false, null: false
    add_index :people, :jamboree_data_confirmed
  end
end