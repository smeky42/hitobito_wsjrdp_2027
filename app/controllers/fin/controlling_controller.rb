# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Controlling" section overview at /fin/controlling (default tab). The area is
# new and still empty -- the page carries nothing but its heading so far.
# controller "fin/controlling" -> Sheet::Fin::Controlling (renders the left_nav
# + the Übersicht tab).
class Fin::ControllingController < Fin::FinController
  before_action :authorize_action

  def index
  end

  private

  def authorize_action
    authorize!(:fin_admin, WsjrdpFinAccount)
  end
end
