# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Buchhaltung" section overview at /bookkeeping. The actual pages live in one
# resource controller per entity: Fin::LedgerAccountsController,
# Fin::CostCentersController, Fin::PersonalAccountsController,
# Fin::BookingBatchesController and Fin::BookingsController.
class Fin::BookkeepingController < Fin::FinController
  before_action :authorize_action

  # Übersicht at /bookkeeping -- for now just links to the sub-pages.
  def overview
  end

  private

  def authorize_action
    authorize!(:fin_admin, DatevBooking)
  end
end
