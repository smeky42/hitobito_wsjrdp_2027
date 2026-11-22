# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Columns of the Moss teams list (/fin/moss/teams): one MossTeam per row. The
# counts are subqueries the list selects (`user_count`, `supplier_count`), so
# the cell, the sort and the filter count alike. Benutzer counts the users in
# Moss that are not deactivated, linked to a person or not.
module Fin::MossTeamsColumns
  USER_COUNT_SQL = "(SELECT COUNT(*) FROM moss_users u WHERE u.moss_team_uuid = moss_teams.moss_team_uuid " \
    "AND u.moss_removed_at IS NULL AND u.status IS DISTINCT FROM '#{MossUser::STATUS_DEACTIVATED}')"
  SUPPLIER_COUNT_SQL = "(SELECT COUNT(*) FROM wsjrdp_personal_accounts a " \
    "WHERE a.default_moss_team_uuid = moss_teams.moss_team_uuid)"
  DEPARTMENT_NAME_SQL = "(SELECT d.name FROM moss_departments d " \
    "WHERE d.moss_department_uuid = moss_teams.moss_department_uuid)"
  TEAM_LEAD_NAME_SQL = "(SELECT CONCAT_WS(' ', u.first_name, u.last_name) FROM moss_users u " \
    "WHERE u.moss_user_uuid = moss_teams.team_lead_uuid)"

  # The teams with the counts the cells, the sort and the filter share.
  def self.with_counts(scope = MossTeam.all)
    scope.select("moss_teams.*", "#{USER_COUNT_SQL} AS user_count", "#{SUPPLIER_COUNT_SQL} AS supplier_count")
  end

  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "mtcol") do |c|
    c.column key: "name", abbr: "nm", label: "Name", width: "9rem", target_width: "16rem", grow: 2,
      truncate: true, sticky: true, sort: "LOWER(moss_teams.name)", default: true
    c.column key: "department", abbr: "dp", label: "Abteilung", width: "8rem", target_width: "13rem", grow: 1,
      truncate: true, sort: "LOWER(#{DEPARTMENT_NAME_SQL})", default: true
    c.column key: "team_lead", abbr: "tl", label: "Team-Lead", width: "8rem", target_width: "13rem", grow: 1,
      truncate: true, sort: "LOWER(#{TEAM_LEAD_NAME_SQL})", default: true
    c.column key: "status", abbr: "st", label: "Status", width: "6.5rem", truncate: true,
      sort: "moss_teams.status", default: true
    c.column key: "user_count", abbr: "uc", label: "Benutzer",
      header_tooltip: "Benutzer im Team, die in Moss und nicht deaktiviert sind",
      numeric: true, width: "6rem", sort: USER_COUNT_SQL, sort_first: "desc", default: true
    # In the columns menu only.
    c.column key: "supplier_count", abbr: "sc", label: "Standard-Lieferanten",
      header_label: "Lieferanten", header_tooltip: "Kreditoren mit diesem Team als Standard-Team",
      numeric: true, width: "6.5rem", sort: SUPPLIER_COUNT_SQL, sort_first: "desc"
    c.column key: "comment", abbr: "cm", label: "Kommentar", width: "10rem", target_width: "16rem",
      truncate: true, sort: "LOWER(moss_teams.comment)"
  end
end
