# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Prepended to the core's Person::SecurityToolsController: blocking and
# unblocking post to the group's URL and come back to the security page --
# at its short URL in the person's primary group, at the group's URL in any
# other (Wsjrdp2027::PeopleHelper#person_subpage_path).
module Wsjrdp2027::Person::SecurityToolsController
  private

  def security_tools_group_person_path(group, person, options = {})
    helpers.person_subpage_path(:security_tools, group, person, options)
  end
end
