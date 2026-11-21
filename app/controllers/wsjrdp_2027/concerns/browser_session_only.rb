# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Pages for a browser session only: a request signed in by an API token,
# a service token or an OAuth token gets 403. Include it before any other
# before_action.
module Wsjrdp2027::Concerns::BrowserSessionOnly
  extend ActiveSupport::Concern

  included do
    before_action :refuse_token_sign_in
  end

  private

  # The three ways hitobito signs in without a session.
  def refuse_token_sign_in
    head :forbidden if token_authentication.user_from_token || current_service_token || current_oauth_token
  end
end
