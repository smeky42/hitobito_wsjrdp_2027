# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A dimension in Moss (API /v1/dimensions). Its items have no table of their
# own: the cost center items are WsjrdpCostCenter rows, the cost carrier items
# WsjrdpSphere rows, each linked by `moss_uuid`. `items_table` names that table.
class MossDimension < ActiveRecord::Base
  include MossSyncedRecord

  # Fixed by Moss for every organisation.
  COST_CENTER_UUID = "00000000-0000-0000-0000-000000000001"
  COST_CARRIER_UUID = "00000000-0000-0000-0000-000000000002"

  ITEM_MODELS = {
    "wsjrdp_cost_centers" => "WsjrdpCostCenter",
    "wsjrdp_spheres" => "WsjrdpSphere"
  }.freeze

  STATUS_ACTIVE = "ACTIVE"
  STATUS_DELETED = "DELETED"

  validates :moss_dimension_uuid, presence: true, uniqueness: true
  validates :items_table, inclusion: {in: ITEM_MODELS.keys}, allow_nil: true

  scope :active, -> { where(status: STATUS_ACTIVE) }

  # The dimension's items, or nil when Hitobito keeps none.
  def items
    ITEM_MODELS[items_table]&.constantize&.all
  end

  def to_s = name.presence || moss_dimension_uuid
end
