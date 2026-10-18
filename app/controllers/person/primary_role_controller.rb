# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The page "Hauptgruppe/Rolle wechseln" below the status page
# (Wsjrdp2027::PrimaryRoleChange), with and without a group in the URL,
# built step by step in its turbo frame primary_role_dialog. Every step is a
# GET of #show with the choices so far (the group select submits itself);
# #create carries the change out and sends the browser back to the status
# page. Whoever reaches the status page (:log on the person) may use it.
class Person::PrimaryRoleController < ApplicationController
  FRAME = "primary_role_dialog"

  helper_method :change, :frame_id

  before_action :group

  def show
    authorize!(:log, person)
    change.validate if change.complete?
    render "show"
  end

  def create
    authorize!(:log, person)
    authorize_change!
    note = change.note_text
    change.save!
    flash[:notice] = note
    render turbo_stream: helpers.turbo_stream_action_tag(:redirect_top, url: helpers.status_page_path(change.group, person))
  rescue ActiveModel::ValidationError
    render "show", status: 422
  rescue ActiveRecord::RecordInvalid => e
    # A record refused by its own validations (the new role, say): shown
    # like the dialog's own errors.
    change.errors.add(:base, e.record.errors.full_messages.to_sentence)
    render "show", status: 422
  end

  private

  def frame_id = FRAME

  # What the change does beyond the status page, on the rights of each
  # part: the new role (unless the person holds it there already), every
  # role to end, the new primary group.
  def authorize_change!
    return unless change.complete?

    authorize!(:create, change.role_class.new(person: person, group: change.group)) unless change.existing_target_role
    change.end_roles.each { |role| authorize!(:destroy, role) }
    authorize!(:primary_group, person) if change.primary_group_changes?
  end

  def change
    @change ||= Wsjrdp2027::PrimaryRoleChange.new(person: person, by: current_user, ability: current_ability, **change_params)
  end

  def change_params
    params.fetch(:primary_role_change, {})
      .permit(:group_id, :role_type, :role_group_id, :wsj_role, :contract, :end_roles_chosen, end_role_ids: [], keep_role_ids: [])
      .to_h.symbolize_keys
  end

  # By id alone, as the status page (Person::StatusController#person).
  def person
    @person ||= Person.find(params[:id])
  end

  # The group of the URL, without one the primary group, as on the status
  # page (Person::StatusController#group).
  def group
    @group ||= params[:group_id] ? Group.find(params[:group_id]) : person.default_group
  end
end
