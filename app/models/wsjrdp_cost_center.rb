# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

class WsjrdpCostCenter < ActiveRecord::Base
  include WsjrdpBudgetable

  STATUS_ACTIVE = "active"
  STATUS_DEACTIVATED = "deactivated"

  belongs_to :manager, class_name: "Person", optional: true,
    inverse_of: :managed_cost_centers

  validates :number, presence: true, uniqueness: true

  # moss_status is NULL for cost centers unknown to Moss
  scope :active, -> { where(moss_status: STATUS_ACTIVE) }
  scope :deactivated, -> { where(moss_status: [STATUS_DEACTIVATED, nil]) }

  def active?
    moss_status == STATUS_ACTIVE
  end

  def to_s
    "#{number} #{display_short_name}"
  end
end
