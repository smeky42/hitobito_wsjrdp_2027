# frozen_string_literal: true

class Person::MedicalController < ApplicationController
  class_attribute :permitted_attrs

  respond_to :html

  before_action :group

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
    respond_with person, location: helpers.medical_page_path(group, person)
  end

  private

  # By id alone, as the status page (Person::StatusController#person): the
  # page works in every group, and without one (/people/:id/medical) in the
  # primary group.
  def person
    @person ||= Person.find(params[:id])
  end

  def group
    @group ||= params[:group_id] ? Group.find(params[:group_id]) : person.default_group
  end
end
