# frozen_string_literal: true

#  Copyright (c) 2026, German Contingent for the Worldscoutjamboree 2027. This file is part of
#  hitobito_wsjrdp_2027 and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/hitobito/hitobito_wsjrdp_2027.

# Distributes the ULs and YPs of a unit into patrols (people.patrol).
class Group::PatrolsController < ApplicationController
  PATROLS = %w[A B C D].freeze
  MAX_PATROL_SIZE = 10
  UL_ROLE_TYPES = %w[Group::Unit::Leader Group::Unit::UnapprovedLeader].freeze
  YP_ROLE_TYPES = %w[Group::Unit::Member].freeze

  before_action :authorize_action
  prepend_before_action :group

  decorates :group

  def index
    @patrols = PATROLS
    @max_patrol_size = MAX_PATROL_SIZE
    @people = unit_people
    @ul_ids = ul_ids
  end

  def update
    people = unit_people
    assignment = people.to_h do |p|
      value = params.dig(:patrols, p.id.to_s).to_s
      [p.id, PATROLS.include?(value) ? value : nil]
    end

    errors = validate_assignment(assignment)
    if errors.any?
      redirect_to group_patrols_path(group), alert: errors.join(" ")
      return
    end

    Person.transaction do
      assignment.group_by(&:last).each do |patrol, pairs|
        Person.where(id: pairs.map(&:first)).update_all(patrol: patrol)
      end
    end
    redirect_to group_patrols_path(group), notice: "Patrols wurden gespeichert."
  end

  private

  def validate_assignment(assignment)
    PATROLS.each_with_object([]) do |patrol, errors|
      ids = assignment.select { |_, v| v == patrol }.keys
      if ids.size > MAX_PATROL_SIZE
        errors << "Patrol #{patrol} hat #{ids.size} Personen (maximal #{MAX_PATROL_SIZE})."
      end
      unless ids.intersect?(ul_ids)
        errors << "In Patrol #{patrol} ist kein UL."
      end
    end
  end

  def unit_people
    ::Person.joins(:roles)
      .where(roles: {group_id: group.id, type: UL_ROLE_TYPES + YP_ROLE_TYPES})
      .where("people.status IS NULL OR people.status <> ?", "deregistered")
      .distinct
      .order(:first_name, :last_name)
      .to_a
  end

  def ul_ids
    @ul_ids ||= ::Role.where(group_id: group.id, type: UL_ROLE_TYPES).pluck(:person_id)
  end

  def authorize_action
    raise CanCan::AccessDenied unless group.is_a?(::Group::Unit)

    authorize!(can?(:update_patrols, group) ? :update_patrols : :log, group)
  end

  def group
    @group ||= Group.find(params[:group_id])
  end
end
