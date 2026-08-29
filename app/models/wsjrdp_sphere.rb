# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A tax sphere (steuerliche Sphäre) of the non-profit. In Moss it is a
# cost carrier.
class WsjrdpSphere < ActiveRecord::Base
  include WsjrdpBudgetable

  STATUS_ACTIVE = "active"
  STATUS_DEACTIVATED = "deactivated"

  # The foreign key is spelled out: the column is `manager_person_id`, not the
  # `manager_id` a belongs_to would derive from the association name.
  belongs_to :manager, class_name: "Person", optional: true,
    foreign_key: :manager_person_id, inverse_of: :managed_spheres

  validates :number, presence: true, uniqueness: true

  # moss_status is NULL for spheres unknown to Moss
  scope :active, -> { where(moss_status: STATUS_ACTIVE) }
  scope :deactivated, -> { where(moss_status: [STATUS_DEACTIVATED, nil]) }

  def active?
    moss_status == STATUS_ACTIVE
  end

  def to_s
    "#{number} #{display_short_name}"
  end
end
