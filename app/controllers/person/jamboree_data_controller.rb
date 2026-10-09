# frozen_string_literal: true

require_dependency "sheet/person/jamboree_data"

class Person::JamboreeDataController < ApplicationController
  class_attribute :permitted_attrs

  respond_to :html

  self.permitted_attrs = [
    *Wsjrdp2027::Person::JAMBOREE_TEXT_ATTRS,
    *Wsjrdp2027::Person::JAMBOREE_SELECT_ATTRS,
    *Wsjrdp2027::Person::JAMBOREE_DATE_ATTRS,
    *Wsjrdp2027::Person::JAMBOREE_BOOLEAN_ATTRS,
    {medical_equipment_needs: []},
    :jamboree_data_confirmed
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
    respond_with person, location: jamboree_data_group_person_path
  end

  private

  def person
    @person ||= fetch_person
  end

  def group
    @group ||= Group.find(params[:group_id])
  end
end
