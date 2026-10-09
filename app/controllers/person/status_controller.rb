# frozen_string_literal: true

class Person::StatusController < ApplicationController
  include ContractHelper

  class_attribute :permitted_attrs

  respond_to :html

  helper_method :wsj_role_options
  helper_method :contract_question
  helper_method :permitted_attrs

  self.permitted_attrs = [
    :status,
    :birthday,
    :first_name,
    :last_name,
    :print_at,
    :contract_upload_at,
    :complete_document_upload_at,
    :unit_code,
    :cluster_code,
    :deregistration_issue,
    :deregistration_requested_date,
    :deregistration_effective_date,
    :debit_return_issue,
    :payment_role,
    :wsj_role,
    :is_preallocated_ist
  ]

  def show
    authorize!(:log, person)
    render "show"
  end

  def edit
    authorize!(:log, person)
    render "edit"
  end

  # A change of status that starts or ends the contract (Person#track_contract)
  # is saved only once asked and confirmed: the form comes back with the
  # question (contract_question) and its values, and saves with
  # confirm_contract=1. The question is decided here, on the stored contract,
  # not in the browser.
  def update
    authorize!(:log, person)
    person.attributes = params.require(:person).permit(permitted_attrs)
    if contract_question && params[:confirm_contract] != "1"
      render "edit", status: 422
      return
    end

    person.contract_confirmed_by = current_user if contract_question.in?(%i[confirm confirm_again])
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

  # What the status change about to be saved does to the contract: :confirm
  # (the first contract), :confirm_again (a new contract after the end) or
  # :end (the contract in force ends); nil when it leaves it as it is.
  def contract_question
    return unless person.status_changed?

    case person.status
    when "confirmed"
      case person.contract_status
      when "none" then :confirm
      when "ended" then :confirm_again
      end
    when "deregistered"
      :end if person.contract_status == "confirmed"
    end
  end

  def wsj_role_options
    blank_opt = [nil, "Nicht gesetzt: WSJ Rolle = WSJRDP Rolle = #{person.short_payment_role}"]
    [blank_opt] + Settings.wsj_role.map { |key, val| [key, val] }
  end
end
