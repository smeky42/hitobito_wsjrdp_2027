class AddPeopleAttrsBuddyIdUlYp < ActiveRecord::Migration[4.2]
  def change
    add_column :people, :buddy_id_ul, :string
    add_column :people, :buddy_id_yp, :string
  end
end
