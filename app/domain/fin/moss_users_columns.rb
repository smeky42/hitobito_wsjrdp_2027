# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Columns of the Moss users list (/fin/moss/users): one MossUser per row. The
# rows are a relation, so every column sorts by an SQL expression. The linked
# records are looked up by subquery, so a dangling reference sorts as empty.
#
# Narrow screens: the table scrolls sideways, the name stays at the left.
module Fin::MossUsersColumns
  NAME_SQL = "CONCAT_WS(' ', moss_users.first_name, moss_users.last_name)"
  TEAM_NAME_SQL = "(SELECT t.name FROM moss_teams t WHERE t.moss_team_uuid = moss_users.moss_team_uuid)"
  DEPARTMENT_NAME_SQL = "(SELECT d.name FROM moss_teams t JOIN moss_departments d " \
    "ON d.moss_department_uuid = t.moss_department_uuid WHERE t.moss_team_uuid = moss_users.moss_team_uuid)"
  MANAGER_NAME_SQL = "(SELECT CONCAT_WS(' ', m.first_name, m.last_name) FROM moss_users m " \
    "WHERE m.moss_user_uuid = moss_users.manager_uuid)"
  PERSON_NAME_SQL = "(SELECT CONCAT_WS(' ', p.first_name, p.last_name) FROM people p " \
    "WHERE p.id = moss_users.person_id)"
  # The name the list shows: the Moss name, else the linked person's, else the e-mail.
  SORT_NAME_SQL = "COALESCE(NULLIF(#{NAME_SQL}, ''), #{PERSON_NAME_SQL}, moss_users.email)"

  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "mucol") do |c|
    c.column key: "name", abbr: "nm", label: "Name", width: "9rem", target_width: "14rem", grow: 2,
      truncate: true, sticky: true, sort: "LOWER(#{SORT_NAME_SQL})", default: true
    c.column key: "email", abbr: "em", label: "E-Mail", width: "10rem", target_width: "17rem", grow: 1,
      truncate: true, sort: "LOWER(moss_users.email)"
    c.column key: "team", abbr: "tm", label: "Team", width: "7rem", target_width: "12rem", grow: 1,
      truncate: true, sort: "LOWER(#{TEAM_NAME_SQL})", default: true
    c.column key: "department", abbr: "dp", label: "Abteilung", width: "7rem", target_width: "11rem", grow: 1,
      truncate: true, sort: "LOWER(#{DEPARTMENT_NAME_SQL})", default: true
    c.column key: "status", abbr: "st", label: "Status", width: "6.5rem", truncate: true,
      sort: "moss_users.status", default: true
    c.column key: "roles", abbr: "rl", label: "Rollen", width: "7rem", target_width: "11rem",
      truncate: true, sort: "array_to_string(moss_users.roles, ',')", default: true
    c.column key: "person", abbr: "ps", label: "Person", width: "8rem", target_width: "13rem", grow: 1,
      truncate: true, sort: "LOWER(#{PERSON_NAME_SQL})"
    # In the columns menu only, like E-Mail and Person above.
    c.column key: "manager", abbr: "mg", label: "Manager", width: "8rem", target_width: "12rem",
      truncate: true, sort: "LOWER(#{MANAGER_NAME_SQL})"
    c.column key: "phone", abbr: "ph", label: "Telefon", width: "8rem", truncate: true,
      sort: "moss_users.phone"
    c.column key: "moss_created_at", abbr: "mc", label: "In Moss angelegt", width: "8.5rem",
      sort: "moss_users.moss_created_at", sort_first: "desc"
    c.column key: "moss_updated_at", abbr: "mu", label: "In Moss geändert", width: "8.5rem",
      sort: "moss_users.moss_updated_at", sort_first: "desc"
    c.column key: "comment", abbr: "cm", label: "Kommentar", width: "10rem", target_width: "16rem",
      truncate: true, sort: "LOWER(moss_users.comment)"
  end
end
