# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Abteilungen", a Moss tab (/fin/moss/departments): the departments in Moss.
# See Fin::MossOrganisationController for the list, the page and the edit page.
class Fin::MossDepartmentsController < Fin::MossOrganisationController
  self.model_class = MossDepartment
  self.row_id_prefix = "md"
  self.page_frame_prefix = "mdpage"
  self.row_preloads = [{owner: :person}]

  COLUMNS = Fin::MossDepartmentsColumns::COLUMNS
  POLICY = list_policy(COLUMNS, Fin::MossDepartmentsFilterSchema)
  TEAMS_POLICY = nested_policy("t", Fin::MossTeamsColumns::COLUMNS, Fin::MossTeamsFilterSchema,
    hidden: %w[department])
  USERS_POLICY = nested_policy("u", Fin::MossUsersColumns::COLUMNS, Fin::MossUsersFilterSchema,
    hidden: %w[department])

  helper_method :department_teams, :department_users

  def department_teams
    @department_teams ||= filtered_rows(TEAMS_POLICY, Fin::MossTeamsColumns::COLUMNS,
      Fin::MossTeamsColumns.with_counts(teams), Fin::MossTeamsController::PRELOADS)
  end

  # The users of the teams the list counts.
  def department_users
    @department_users ||= filtered_rows(USERS_POLICY, Fin::MossUsersColumns::COLUMNS,
      MossUser.where(moss_team_uuid: teams.current.select(:moss_team_uuid)), Fin::MossUsersController::PRELOADS)
  end

  def apply_teams = apply_nested(TEAMS_POLICY)

  def apply_users = apply_nested(USERS_POLICY)

  private

  def teams = MossTeam.where(moss_department_uuid: entry.moss_department_uuid)

  def list_source
    MossDepartment.select("moss_departments.*", "#{Fin::MossDepartmentsColumns::TEAM_COUNT_SQL} AS team_count",
      "#{Fin::MossDepartmentsColumns::USER_COUNT_SQL} AS user_count")
  end
end
