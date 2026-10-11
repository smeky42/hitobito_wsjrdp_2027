class AddPatrolToPeople < ActiveRecord::Migration[7.1]
  def change
    add_column :people, :patrol, :string
  end
end
