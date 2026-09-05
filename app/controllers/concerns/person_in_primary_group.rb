# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module PersonInPrimaryGroup
  extend ActiveSupport::Concern

  included do
    before_action :map_id_to_person_id
    decorates :group, :person
  end

  private

  def person
    @person ||= Person.find(params[:person_id])
  end

  # The person's primary group -- the root group for a person without one (the
  # root user has no role at all), so the person sheet and its left navigation
  # always have a group to draw.
  def group
    @group ||= person.primary_group || Group.root
  end

  def map_id_to_person_id
    params[:person_id] = params[:id] unless params.key?(:person_id)
  end
end
