# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A department in Moss (API /v1/departments). The Moss tables point at each
# other by Moss UUID, without foreign keys: a reference may dangle, and
# removing a row never touches the rows pointing at it.
class MossDepartment < ActiveRecord::Base
  include MossSyncedRecord

  validates :moss_department_uuid, presence: true, uniqueness: true

  belongs_to :owner, class_name: "MossUser", optional: true,
    primary_key: :moss_user_uuid, foreign_key: :owner_uuid, inverse_of: :owned_departments

  # rubocop:disable Rails/HasManyOrHasOneDependent -- references may dangle
  has_many :teams, class_name: "MossTeam",
    primary_key: :moss_department_uuid, foreign_key: :moss_department_uuid, inverse_of: :department
  # rubocop:enable Rails/HasManyOrHasOneDependent

  def to_s = name.presence || moss_department_uuid
end
