# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027
module Wsjrdp::Sync::MossApi
  # The items of the cost center dimension into wsjrdp_cost_centers.
  class CostCenters < MasterPart
    self.key = "moss_api.master_data.cost_centers"
    self.path = "v1/dimensions/#{MossDimension::COST_CENTER_UUID}/items"
    self.model = WsjrdpCostCenter
    self.sort_orders = %w[name -update_time].freeze
  end
end
