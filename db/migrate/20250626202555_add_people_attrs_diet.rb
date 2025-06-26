# frozen_text_literal: true

class AddPeopleAttrsDiet < ActiveRecord::Migration[4.2]
  def change
    add_column :people, :diet, :string, default: "omnivorous"
  end
end
