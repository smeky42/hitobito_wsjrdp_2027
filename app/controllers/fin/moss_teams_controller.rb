# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Teams", a Moss tab (/fin/moss/teams): the teams in Moss. See
# Fin::MossOrganisationController for the list, the page and the edit page.
class Fin::MossTeamsController < Fin::MossOrganisationController
  self.model_class = MossTeam
  self.row_id_prefix = "mt"
  self.page_frame_prefix = "mtpage"
  PRELOADS = [:department, {team_lead: :person}].freeze
  self.row_preloads = PRELOADS

  COLUMNS = Fin::MossTeamsColumns::COLUMNS
  POLICY = list_policy(COLUMNS, Fin::MossTeamsFilterSchema)
  USERS_POLICY = nested_policy("u", Fin::MossUsersColumns::COLUMNS, Fin::MossUsersFilterSchema,
    hidden: %w[team department])

  helper_method :team_users

  def team_users
    @team_users ||= filtered_rows(USERS_POLICY, Fin::MossUsersColumns::COLUMNS,
      MossUser.where(moss_team_uuid: entry.moss_team_uuid), Fin::MossUsersController::PRELOADS)
  end

  def apply_users = apply_nested(USERS_POLICY)

  private

  def list_source = Fin::MossTeamsColumns.with_counts
end
