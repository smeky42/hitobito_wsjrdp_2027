# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The cells of the Moss departments list (Fin::MossDepartmentsColumns) and the
# formatters of a department's detail (fin_format_moss_department_<attr>).
module Fin::MossDepartmentsHelper
  def moss_departments_table_columns
    cells = {
      "name" => ->(department) { moss_org_name_cell(department) },
      "owner" => ->(department) { moss_org_user_cell(department.owner) },
      "team_count" => ->(department) { department.team_count },
      "user_count" => ->(department) { department.user_count },
      "comment" => ->(department) { department.comment }
    }
    Fin::MossDepartmentsColumns::COLUMNS.map { |col| col.to_table_column(cell: cells.fetch(col.key)) }
  end

  def fin_format_moss_department_owner(department) = moss_org_user_reference(department.owner, department.owner_uuid)

  def fin_format_moss_department_moss_department_uuid(department) = moss_org_uuid(department.moss_department_uuid)

  def fin_format_moss_department_owner_uuid(department) = moss_org_uuid(department.owner_uuid)

  def fin_format_moss_department_moss_organisation_uuid(department)
    moss_org_uuid(department.moss_organisation_uuid)
  end

  def fin_format_moss_department_comment(department)
    department.comment.presence && simple_format(department.comment)
  end
end
