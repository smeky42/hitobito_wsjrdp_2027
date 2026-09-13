# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# GET /wsjrdp/impersonate/people: the person search of the admin tab
# (doc/roles.md -> "The finance cap"), the lookup that feeds the typeahead
# field before Wsjrdp::ImpersonationController#create performs the switch.
#
# The core's Person::QueryController answers the same question, but asks it of
# #current_person -- while impersonating the impersonated person, who may
# neither :query people nor :impersonate_user anybody. So the field went blank
# exactly where it is needed most: to leave one impersonation for the next.
#
# Everything else is the core's: the search columns, the three-character
# minimum, the result limit and the typeahead JSON. Only who is asking
# changes, and it changes the way the impersonation controller already
# resolves it -- the origin user first.
class Wsjrdp::ImpersonationQueryController < Person::QueryController
  private

  # The person who actually logged in. Deliberately #current_person and not
  # #current_user: the latter reads back through #current_ability, which is
  # overridden right below.
  def actor
    @actor ||= origin_user || current_person
  end

  def current_ability
    @current_ability ||= Ability.new(actor)
  end

  # Not a general people search. The one question this endpoint answers is
  # whom the actor may impersonate, whatever the request asks for.
  def limit_by_permission
    "impersonate_user"
  end
end
