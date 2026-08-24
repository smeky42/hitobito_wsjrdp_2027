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

  belongs_to :manager, class_name: "Person", optional: true,
    inverse_of: :managed_spheres

  validates :number, presence: true, uniqueness: true

  scope :active, -> { where(moss_status: STATUS_ACTIVE) }
  scope :deactivated, -> { where(moss_status: STATUS_DEACTIVATED) }

  def active?
    moss_status == STATUS_ACTIVE
  end

  def to_s
    name.present? ? "#{number} #{name}" : number
  end
end
