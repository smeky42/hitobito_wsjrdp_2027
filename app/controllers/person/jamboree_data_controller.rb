# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require_dependency "sheet/person/jamboree_data"

class Person::JamboreeDataController < ApplicationController
  class_attribute :permitted_attrs

  respond_to :html

  before_action :group

  self.permitted_attrs = [
    *Wsjrdp2027::Person::JamboreeData::TEXT_ATTRS,
    *Wsjrdp2027::Person::JamboreeData::SELECT_ATTRS,
    *Wsjrdp2027::Person::JamboreeData::DATE_ATTRS,
    *Wsjrdp2027::Person::JamboreeData::BOOLEAN_ATTRS,
    *Wsjrdp2027::Person::JamboreeData::VISA_YES_NO_ATTRS,
    *Wsjrdp2027::Person::JamboreeData::ALLERGY_LEVEL_ATTRS,
    {medical_equipment_needs: []},
    :diet,
    :shirt_size,
    :uniform_size,
    :uniform_long_sleeve,
    :uniform_order,
    :headgear,
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
    attrs = person.jamboree_data_adult? ? permitted_attrs : permitted_attrs - Wsjrdp2027::Person::JamboreeData::ADULT_ONLY_ATTRS
    attrs -= Wsjrdp2027::Person::JamboreeData::JOURNEY_ATTRS unless person.jamboree_data_journey_editable?
    attrs -= [:uniform_order] unless person.uniform_order_available?
    attrs -= [:visa_information] # kept, but no longer asked
    person.attributes = params.require(:person).permit(attrs)
    person.save
    respond_with person, location: helpers.jamboree_data_page_path(group, person)
  end

  private

  # By id alone, as the status page (Person::StatusController#person): the
  # page works in every group, and without one (/people/:id/jamboree_data)
  # in the primary group.
  def person
    @person ||= Person.find(params[:id])
  end

  def group
    @group ||= params[:group_id] ? Group.find(params[:group_id]) : (person.primary_group || Group.root)
  end
end
