# frozen_text_literal: true

class AddPeopleAttrsStatus < ActiveRecord::Migration[4.2]
    def change
      add_column :people, :status, :string, :default => 'Registriert' 
      # Registriert
      # Anmeldung gedruckt 
      # Upload vollständig
      # Dokumente in Überprüfung
      # Dokumente überprüft
      # Bestätigt
      # Abmeldung vermerkt
      # Abgemeldet
    end
end