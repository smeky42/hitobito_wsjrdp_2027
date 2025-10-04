# frozen_string_literal: true

#  Copyright (c) 2025, German Contingent for the Worldscoutjamboree 2027. This file is part of
#  hitobito_wsjrdp_2027 and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/hitobito/hitobito_wsjrdp_2027.

class Group::MapController < ApplicationController
  before_action :authorize_action
  before_action :redirect_to_layer
  prepend_before_action :group

  decorates :group

  def index
    allowed_statuses = ["printed", "upload", "in_review", "reviewed"]
    groups = @group.self_and_descendants

    @people = ::Person.joins(:groups)
      .where(groups: {id: groups.pluck(:id)})
      .where(status: allowed_statuses)
      .where.not(longitude: nil, latitude: nil)
      .distinct
      .select(
        :first_name, :last_name, :zip_code, :town, :country,
        :street, :housenumber, :longitude, :latitude, :unit_code
      )
  end

  private

  def authorize_action
    authorize!(:show_statistics, group)
  end

  def redirect_to_layer
    unless group.layer?
      redirect_to group_statistics_path(group.layer_group_id)
    end
  end

  def group
    @group ||= Group.find(params[:group_id])
  end
end
