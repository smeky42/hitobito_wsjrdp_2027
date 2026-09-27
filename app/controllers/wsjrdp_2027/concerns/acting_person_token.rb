# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A request signed in with a service token that has an acting person is
# authorized by Wsjrdp2027::ActingPersonTokenAbility instead of TokenAbility.
# Prepended to ApplicationController and JsonApiController, the two
# controllers that include Authenticatable.
module Wsjrdp2027::Concerns::ActingPersonToken
  def current_ability
    @current_ability ||= if !current_person && current_service_token&.acting_person
      Wsjrdp2027::ActingPersonTokenAbility.new(current_service_token)
    else
      super
    end
  end
end
