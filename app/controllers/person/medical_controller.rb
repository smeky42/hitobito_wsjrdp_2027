# frozen_string_literal: true

class Person::MedicalController < ApplicationController
  class_attribute :permitted_attrs

  respond_to :html

  self.permitted_attrs = [
    :medical_stiko_vaccinations,
    :medical_additional_vaccinations,
    :medical_preexisting_conditions,
    :medical_abnormalities,
    :medical_allergies,
    :medical_eating_disorders,
    :medical_mobility_needs,
    :medical_infectious_diseases,
    :medical_medical_treatment_contact,
    :medical_continuous_medication,
    :medical_needs_medication,
    :medical_self_treatment_medication,
    :medical_mental_health,
    :medical_situational_support,
    :medical_person_of_trust,
    :medical_other
  ]

  def show
    authorize!(:show_full, person)
    render "show"
  end

  def edit
    authorize!(:edit, person)
    render "edit"
  end

  def update
    authorize!(:edit, person)
    person.attributes = params.require(:person).permit(permitted_attrs)
    person.save
    respond_with person, location: medical_group_person_path
  end

  private

  def person
    @person ||= fetch_person
  end

  def group
    @group ||= Group.find(params[:group_id])
  end
end
