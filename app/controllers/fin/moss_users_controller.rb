# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Benutzer", a Moss tab (/fin/moss/users): the users in Moss. See
# Fin::MossOrganisationController for the list, the page and the edit page.
class Fin::MossUsersController < Fin::MossOrganisationController
  self.model_class = MossUser
  self.row_id_prefix = "mu"
  self.page_frame_prefix = "mupage"
  # Also what the tables of users on other pages load with their rows.
  PRELOADS = [{team: :department}, {manager: :person}, :person].freeze
  self.row_preloads = PRELOADS
  # Besides the comment, the Hitobito person behind the user.
  self.editable_attrs = [:comment, :person_id].freeze

  COLUMNS = Fin::MossUsersColumns::COLUMNS
  POLICY = list_policy(COLUMNS, Fin::MossUsersFilterSchema)
end
