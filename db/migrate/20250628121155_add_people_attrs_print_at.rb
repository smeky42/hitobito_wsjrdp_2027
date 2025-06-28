# frozen_text_literal: true

class AddPeopleAttrsPrintAt < ActiveRecord::Migration[4.2]
  def change
    add_column :people, :print_at, :date
  end
end
