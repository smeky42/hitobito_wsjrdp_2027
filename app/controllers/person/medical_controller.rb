# frozen_string_literal: true

class Person::MedicalController < ApplicationController
  respond_to :html

  def show
    authorize!(:show_full, person)
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
