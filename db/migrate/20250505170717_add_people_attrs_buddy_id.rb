class AddPeopleAttrsBuddyId < ActiveRecord::Migration[4.2]
  def change
    add_column :people, :buddy_id, :string
  end
end
