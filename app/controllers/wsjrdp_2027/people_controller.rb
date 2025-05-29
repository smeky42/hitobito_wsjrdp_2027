# frozen_string_literal: true

#  Copyright (c) 2025, German Contingent for the Worldscoutjamboree 2027. This file is part of
#  hitobito_wsjrdp_2027 and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/hitobito/hitobito_wsjrdp_2027.

module Wsjrdp2027::PeopleController
  extend ActiveSupport::Concern
  included do
    self.permitted_attrs += [
      :rdp_association,
      :rdp_association_region,
      :rdp_association_sub_region,
      :rdp_association_group,
      :rdp_association_number,
      :buddy_id,
      :buddy_id_ul,
      :buddy_id_yp
    ]

    # Override crud_controller
    # Display a form to edit an exisiting entry of this model.
    #   GET /entries/1/edit
    def edit(&block)
      @rdp_groups = YAML.load_file(HitobitoWsjrdp2027::Wagon.root.join("config/rdp_groups.yml"))[Rails.env]

      respond_with(entry, &block)
    end
  end
end
