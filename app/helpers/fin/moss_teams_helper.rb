# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The cells of the Moss teams list (Fin::MossTeamsColumns) and the formatters
# of a team's detail (fin_format_moss_team_<attr>). The counts come from the
# list's query (`user_count`, `supplier_count`).
module Fin::MossTeamsHelper
  def moss_teams_table_columns
    cells = {
      "name" => ->(team) { moss_org_name_cell(team) },
      "department" => ->(team) { team.department && moss_org_link(team.department.to_s, moss_department_path(team.department)) },
      "team_lead" => ->(team) { moss_org_user_cell(team.team_lead) },
      "status" => ->(team) { moss_org_status_label(team.status) },
      "user_count" => ->(team) { team.user_count },
      "supplier_count" => ->(team) { team.supplier_count },
      "comment" => ->(team) { team.comment }
    }
    Fin::MossTeamsColumns::COLUMNS.map { |col| col.to_table_column(cell: cells.fetch(col.key)) }
  end

  def fin_format_moss_team_status(team) = moss_org_status_with_raw(team)

  def fin_format_moss_team_department(team) = moss_org_reference(team.department, team.moss_department_uuid)

  def fin_format_moss_team_team_lead(team) = moss_org_user_reference(team.team_lead, team.team_lead_uuid)

  def fin_format_moss_team_moss_team_uuid(team) = moss_org_uuid(team.moss_team_uuid)

  def fin_format_moss_team_moss_department_uuid(team) = moss_org_uuid(team.moss_department_uuid)

  def fin_format_moss_team_team_lead_uuid(team) = moss_org_uuid(team.team_lead_uuid)

  def fin_format_moss_team_moss_organisation_uuid(team) = moss_org_uuid(team.moss_organisation_uuid)

  def fin_format_moss_team_comment(team) = team.comment.presence && simple_format(team.comment)

  # A supplier by number and name, linked to its Kreditor page for whoever may
  # see it.
  def moss_team_supplier(account)
    label = [account.number, account.name].compact_blank.join(" ")
    return label unless can?(:show, account)

    moss_org_link(label, personal_account_path(account.number))
  end
end
