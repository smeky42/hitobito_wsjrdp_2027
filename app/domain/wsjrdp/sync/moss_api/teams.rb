# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027
module Wsjrdp::Sync::MossApi
  # The teams (GET /v1/teams) into moss_teams.
  class Teams < ListPart
    self.key = "moss_api.organisation_structure.teams"
    self.depends_on = [Departments.key]
    self.path = "v1/teams"
    self.model = MossTeam
    self.uuid_column = "moss_team_uuid"
    self.notice_fields = {"unknown_department" => "moss_department_uuid",
                          "unknown_department_archived" => "moss_department_uuid",
                          "unknown_team_lead" => "team_lead_uuid"}.freeze

    private

    def attributes(record)
      {moss_team_uuid: record["id"], moss_organisation_uuid: record["organisationId"],
       moss_department_uuid: record["departmentId"], team_lead_uuid: record["teamLeadId"],
       name: record["name"], status: record["status"]}
    end

    def label(record) = record["name"].presence || record["moss_team_uuid"]

    def notices(records, changes, table)
      departments = known(MossDepartment, :moss_department_uuid, Departments.key, Departments.data_name)
      leads = known(MossUser, :moss_user_uuid, Users.key, Users.data_name)
      archived, current = records.partition { |record| record["status"] == MossTeam::STATUS_ARCHIVED }
      super + [important("unknown_department", dangling(current, "departmentId", departments)),
        hint("unknown_department_archived", dangling(archived, "departmentId", departments)),
        important("unknown_team_lead", dangling(records, "teamLeadId", leads))].reject { |notice| notice.keys.empty? }
    end
  end
end
