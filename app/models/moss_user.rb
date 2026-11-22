# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A user in Moss (API /v1/users). Mostly one per Hitobito person; a few
# people have several, and some Moss users have no person at all.
#
# Like every Moss table it points at the others by Moss UUID, without foreign
# keys, so a reference may dangle. Only `person_id` is a real foreign key, and
# deleting the person clears it.
class MossUser < ActiveRecord::Base
  include MossSyncedRecord

  STATUS_INVITED = "INVITED"
  STATUS_ACTIVE = "ACTIVE"
  STATUS_DEACTIVATED = "DEACTIVATED"

  validates :moss_user_uuid, presence: true, uniqueness: true
  validates :person, presence: true, if: :person_id?

  belongs_to :person, optional: true, inverse_of: :moss_users
  belongs_to :team, class_name: "MossTeam", optional: true,
    primary_key: :moss_team_uuid, foreign_key: :moss_team_uuid, inverse_of: :users
  belongs_to :manager, class_name: "MossUser", optional: true,
    primary_key: :moss_user_uuid, foreign_key: :manager_uuid, inverse_of: :reports

  # rubocop:disable Rails/HasManyOrHasOneDependent -- references may dangle
  has_many :reports, class_name: "MossUser",
    primary_key: :moss_user_uuid, foreign_key: :manager_uuid, inverse_of: :manager
  has_many :led_teams, class_name: "MossTeam",
    primary_key: :moss_user_uuid, foreign_key: :team_lead_uuid, inverse_of: :team_lead
  has_many :owned_departments, class_name: "MossDepartment",
    primary_key: :moss_user_uuid, foreign_key: :owner_uuid, inverse_of: :owner
  # rubocop:enable Rails/HasManyOrHasOneDependent

  scope :active, -> { where(status: STATUS_ACTIVE) }
  scope :with_role, ->(role) { where("? = ANY(roles)", role) }

  def full_name = [first_name, last_name].compact_blank.join(" ")

  def to_s = full_name.presence || email.presence || moss_user_uuid
end
