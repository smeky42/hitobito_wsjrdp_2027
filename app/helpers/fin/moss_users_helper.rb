# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The cells of the Moss users list (Fin::MossUsersColumns) and the formatters
# of a user's detail (fin_format_moss_user_<attr>, doc/fin/detail_partials.md).
module Fin::MossUsersHelper
  def moss_users_table_columns
    cells = {
      "name" => ->(user) { moss_users_name_cell(user) },
      "email" => ->(user) { moss_users_email_link(user) },
      "team" => ->(user) { user.team && moss_org_link(user.team.to_s, moss_team_path(user.team)) },
      "department" => ->(user) {
        department = user.team&.department
        department && moss_org_link(department.to_s, moss_department_path(department))
      },
      "status" => ->(user) { moss_org_status_label(user.status) },
      "roles" => ->(user) { moss_org_roles(user) },
      "person" => ->(user) { moss_org_person_cell(user.person) || moss_org_dash },
      "manager" => ->(user) { moss_org_user_cell(user.manager) },
      "phone" => ->(user) { user.phone },
      "moss_created_at" => ->(user) { fin_date_time(user.moss_created_at) },
      "moss_updated_at" => ->(user) { fin_date_time(user.moss_updated_at) },
      "comment" => ->(user) { user.comment }
    }
    Fin::MossUsersColumns::COLUMNS.map { |col| col.to_table_column(cell: cells.fetch(col.key)) }
  end

  # Without a Moss name (invited users) the linked person's name stands in.
  def moss_users_name_cell(user)
    return moss_org_name_cell(user) if user.full_name.present?

    stand_in = user.person&.full_name.presence || user.email.presence || user.moss_user_uuid
    moss_org_name_cell(user, content_tag(:span, stand_in, class: "fst-italic text-muted",
      title: "Noch kein Name in Moss"))
  end

  def fin_format_moss_user_status(user) = moss_org_status_with_raw(user)

  def fin_format_moss_user_roles(user) = moss_org_roles(user)

  def fin_format_moss_user_team(user) = moss_org_reference(user.team, user.moss_team_uuid)

  def fin_format_moss_user_manager(user) = moss_org_user_reference(user.manager, user.manager_uuid)

  # The linked Hitobito person, or nothing (the detail says "nicht gesetzt").
  def fin_format_moss_user_person(user) = user.person && moss_org_person_with_icon(user.person)

  def fin_format_moss_user_moss_team_uuid(user) = moss_org_uuid(user.moss_team_uuid)

  def fin_format_moss_user_manager_uuid(user) = moss_org_uuid(user.manager_uuid)

  def fin_format_moss_user_moss_user_uuid(user) = moss_org_uuid(user.moss_user_uuid)

  def fin_format_moss_user_moss_organisation_uuid(user) = moss_org_uuid(user.moss_organisation_uuid)

  # The address as a mail link, for the list and the edit page.
  def moss_users_email_link(user) = user.email.presence && mail_to(user.email)

  # In the detail also the icon that copies the address.
  def fin_format_moss_user_email(user)
    fin_account_copyable(mail_to(user.email), user.email) if user.email.present?
  end

  def fin_format_moss_user_comment(user) = user.comment.presence && simple_format(user.comment)
end
