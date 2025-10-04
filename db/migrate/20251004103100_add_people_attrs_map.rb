# frozen_text_literal: true

class AddPeopleAttrsMap < ActiveRecord::Migration[4.2]
  def change
    add_column :people, :longitude, :string
    add_column :people, :latitude, :string
    add_column :people, :unit_code, :string
  end
end
