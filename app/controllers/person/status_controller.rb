# frozen_string_literal: true

class Person::StatusController < ApplicationController
  include ContractHelper

  class_attribute :permitted_attrs

  respond_to :html

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
    :planned_custom_installments_string,
    :planned_custom_installments_issue,
    :planned_custom_installments_comment,
    :deregistration_issue,
    :deregistration_effective_date,
    :missing_installment_issue
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

  def activate_planned_custom_installments
    authorize!(:log, person)
    Rails.logger.info "soft_delete #{person.active_fee_rule.inspect}"
    Rails.logger.info "activate #{person.planned_fee_rule.inspect}"
    if !person.planned_fee_rule.nil?
      person.active_fee_rule&.soft_delete!
      person.planned_fee_rule.activate!(prev_rule_id: person.planned_fee_rule&.id)
    end
    respond_with person, location: status_group_person_path
  end

  def delete_planned_custom_installments
    authorize!(:log, person)
    Rails.logger.info "soft_delete #{person.planned_fee_rule.inspect}"
    person.planned_fee_rule&.soft_delete!
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
