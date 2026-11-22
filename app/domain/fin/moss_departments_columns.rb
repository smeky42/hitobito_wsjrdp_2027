# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Columns of the Moss departments list (/fin/moss/departments): one
# MossDepartment per row. The two counts are subqueries the list selects as
# `team_count` and `user_count`. They count what is current: teams in Moss and
# not archived, and their users in Moss and not deactivated.
module Fin::MossDepartmentsColumns
  CURRENT_TEAMS_SQL = "moss_teams t WHERE t.moss_department_uuid = moss_departments.moss_department_uuid " \
    "AND t.moss_removed_at IS NULL AND t.status IS DISTINCT FROM '#{MossTeam::STATUS_ARCHIVED}'"
  TEAM_COUNT_SQL = "(SELECT COUNT(*) FROM #{CURRENT_TEAMS_SQL})"
  USER_COUNT_SQL = "(SELECT COUNT(*) FROM moss_users u WHERE u.moss_removed_at IS NULL " \
    "AND u.status IS DISTINCT FROM '#{MossUser::STATUS_DEACTIVATED}' " \
    "AND u.moss_team_uuid IN (SELECT t.moss_team_uuid FROM #{CURRENT_TEAMS_SQL}))"
  OWNER_NAME_SQL = "(SELECT CONCAT_WS(' ', u.first_name, u.last_name) FROM moss_users u " \
    "WHERE u.moss_user_uuid = moss_departments.owner_uuid)"

  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "mdcol") do |c|
    c.column key: "name", abbr: "nm", label: "Name", width: "9rem", target_width: "18rem", grow: 2,
      truncate: true, sticky: true, sort: "LOWER(moss_departments.name)", default: true
    c.column key: "owner", abbr: "ow", label: "Owner", width: "8rem", target_width: "14rem", grow: 1,
      truncate: true, sort: "LOWER(#{OWNER_NAME_SQL})", default: true
    c.column key: "team_count", abbr: "tc", label: "Teams",
      header_tooltip: "Teams der Abteilung, die in Moss und nicht archiviert sind",
      numeric: true, width: "5.5rem", sort: TEAM_COUNT_SQL, sort_first: "desc", default: true
    c.column key: "user_count", abbr: "uc", label: "Benutzer",
      header_tooltip: "Benutzer dieser Teams, die in Moss und nicht deaktiviert sind",
      numeric: true, width: "6rem", sort: USER_COUNT_SQL, sort_first: "desc", default: true
    # In the columns menu only.
    c.column key: "comment", abbr: "cm", label: "Kommentar", width: "10rem", target_width: "16rem",
      truncate: true, sort: "LOWER(moss_departments.comment)"
  end
end
