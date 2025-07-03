# frozen_string_literal: true

class Person::StatusController < ApplicationController
  class_attribute :permitted_attrs

  respond_to :html

  self.permitted_attrs = [
    :status,
    :birthday,
    :first_name,
    :last_name,
    :print_at,
    :contract_upload_at,
    :complete_document_upload_at
  ]

  def show
    authorize!(:log, person)
    render "show"
  end

  def edit
    authorize!(:log, person)
    render "edit"
  end

  def update
    authorize!(:log, person)
    person.attributes = params.require(:person).permit(permitted_attrs)
    person.save
    respond_with person, location: status_group_person_path
  end

  def review_documents
    authorize!(:log, person)
    if @person.status == "upload"
      @person.status = "in_review"
      person.save
    end
    respond_with person, location: status_group_person_path
  end

  def approve_documents
    authorize!(:log, person)
    if @person.status == "in_review"
      @person.status = "reviewed"
      person.save
    end
    respond_with person, location: status_group_person_path
  end

  private

  def person
    @person ||= fetch_person
  end

  def group
    @group ||= Group.find(params[:group_id])
  end
end
