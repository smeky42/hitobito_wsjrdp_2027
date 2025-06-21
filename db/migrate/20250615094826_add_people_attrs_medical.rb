# frozen_string_literal: true

class AddPeopleAttrsMedical < ActiveRecord::Migration[4.2]
  def change
    add_column :people, :medical_stiko_vaccinations, :boolean
    add_column :people, :medical_additional_vaccinations, :text
    add_column :people, :medical_preexisting_conditions, :text
    add_column :people, :medical_abnormalities, :text
    add_column :people, :medical_allergies, :text
    add_column :people, :medical_eating_disorders, :text
    add_column :people, :medical_mobility_needs, :text
    add_column :people, :medical_infectious_diseases, :text
    add_column :people, :medical_medical_treatment_contact, :text
    add_column :people, :medical_continuous_medication, :text
    add_column :people, :medical_needs_medication, :text
    add_column :people, :medical_self_treatment_medication, :text
    add_column :people, :medical_mental_health, :text
    add_column :people, :medical_situational_support, :text
    add_column :people, :medical_person_of_trust, :text
    add_column :people, :medical_other, :text
  end
end
