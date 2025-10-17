# frozen_text_literal: true

class AddPeopleAttrsClusterCode < ActiveRecord::Migration[7.1]
  def change
    add_column :people, :cluster_code, :string
  end
end
