# frozen_text_literal: true

class AddPeopleGeocodedBy < ActiveRecord::Migration[4.2]
  def change
    add_column :people, :geocoded_by, :string
  end
end
