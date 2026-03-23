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

  def group
    @group ||= person.primary_group
  end

  def map_id_to_person_id
    params[:person_id] = params[:id] unless params.key?(:person_id)
  end
end
