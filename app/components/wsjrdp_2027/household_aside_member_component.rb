# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The household in a person's aside lists its members like the other person
# lists of the page (Wsjrdp2027::PeopleHelper#wsjrdp_person_list_entry): the
# contingent role, muted, before the name in bold. The name links where the
# viewer may see that member -- the core asked whether the viewer may see the
# page's person instead.
module Wsjrdp2027::HouseholdAsideMemberComponent
  private

  def person_entry(member)
    helpers.wsjrdp_person_list_entry(member)
  end
end
