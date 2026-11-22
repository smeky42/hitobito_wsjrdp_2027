# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A team in Moss (API /v1/teams). Like every Moss table it points at the
# others by Moss UUID, without foreign keys, so a reference may dangle.
class MossTeam < ActiveRecord::Base
  include MossSyncedRecord

  STATUS_ACTIVE = "ACTIVE"
  STATUS_ARCHIVED = "ARCHIVED"

  validates :moss_team_uuid, presence: true, uniqueness: true

  belongs_to :department, class_name: "MossDepartment", optional: true,
    primary_key: :moss_department_uuid, foreign_key: :moss_department_uuid, inverse_of: :teams
  belongs_to :team_lead, class_name: "MossUser", optional: true,
    primary_key: :moss_user_uuid, foreign_key: :team_lead_uuid, inverse_of: :led_teams

  # rubocop:disable Rails/HasManyOrHasOneDependent -- references may dangle
  has_many :users, class_name: "MossUser",
    primary_key: :moss_team_uuid, foreign_key: :moss_team_uuid, inverse_of: :team
  # Suppliers (creditors) whose new expenses go to this team.
  has_many :default_suppliers, class_name: "WsjrdpPersonalAccount",
    primary_key: :moss_team_uuid, foreign_key: :default_moss_team_uuid, inverse_of: :default_moss_team
  # rubocop:enable Rails/HasManyOrHasOneDependent

  scope :active, -> { where(status: STATUS_ACTIVE) }
  # In Moss and not archived: what the counts count.
  scope :current, -> { in_moss.where("moss_teams.status IS DISTINCT FROM ?", STATUS_ARCHIVED) }

  def to_s = name.presence || moss_team_uuid
end
