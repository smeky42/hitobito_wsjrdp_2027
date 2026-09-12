# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# POST /session_settings: the background target of the session bar's
# segments and its x, and of the admin tab's menu (and of anything else that
# wants to set the cap or a display flag without a page change). The
# parameters are the same as everywhere -- max_finance_permission,
# finance_tier_bar, admin_tab -- and are stored by
# Wsjrdp2027::Concerns::SessionSettings before this action runs; all that is
# left to do is to answer without a body, so the caller can reload.
class SessionSettingsController < ApplicationController
  def update
    authorize!(:show, current_user)
    head :no_content
  end
end
