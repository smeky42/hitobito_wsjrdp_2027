# frozen_text_literal: true

class AddPeopleAttrsStatus < ActiveRecord::Migration[4.2]
  def change
    add_column :people, :status, :string, default: "registered"
    add_column :people, :contract_upload_at, :date
    add_column :people, :complete_document_upload_at, :date
  end
end
