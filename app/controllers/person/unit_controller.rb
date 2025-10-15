# frozen_string_literal: true

class Person::UnitController < ApplicationController
  class_attribute :permitted_attrs

  respond_to :html

  self.permitted_attrs = [
    :first_name,
    :last_name,
    :unit_code
  ]

  def show
    authorize!(:log, person)
    render "show"
  end

  private

  def person
    @person ||= fetch_person
  end

  def group
    @group ||= Group.find(params[:group_id])
  end
end
