# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027
module Wsjrdp::Sync::MossApi
  # The departments (GET /v1/departments) into moss_departments.
  class Departments < ListPart
    self.key = "moss_api.organisation_structure.departments"
    self.path = "v1/departments"
    self.model = MossDepartment
    self.uuid_column = "moss_department_uuid"
    self.notice_fields = {"unknown_owner" => "owner_uuid"}.freeze

    private

    def attributes(record)
      {moss_department_uuid: record["id"], moss_organisation_uuid: record["organisationId"],
       owner_uuid: record["ownerId"], name: record["name"]}
    end

    def label(record) = record["name"].presence || record["moss_department_uuid"]

    def notices(records, changes, table)
      owners = known(MossUser, :moss_user_uuid, Users.key, Users.data_name)
      super + [important("unknown_owner", dangling(records, "ownerId", owners))].reject { |notice| notice.keys.empty? }
    end
  end
end
