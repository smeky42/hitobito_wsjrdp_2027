# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Kartentransaktionen" -- the second Moss tab. Index at
# /fin/moss/card_transactions is an expandable, filterable table (the row detail
# is the same detail shown at /fin/moss/card_transactions/:id). The filter reuses
# the generic CNF filter scaffolding (Fin::MossCardTransactionsFiltering), like
# the Buchungen page. controller "fin/moss_card_transactions" ->
# Sheet::Fin::MossCardTransaction (parent Sheet::Fin::Moss for the tabs).
class Fin::MossCardTransactionsController < Fin::FinController
  include Fin::MossCardTransactionsFiltering

  before_action :authorize_action

  def index
    return if handle_clear

    query # memoized; builds the filtered/sorted/paginated result
  end

  def show
    @card_transaction = MossCardTransaction
      .includes(bookings: [:expense_datev_booking, :clearing_datev_booking])
      .find(params[:id])
  end

  # PRG target of the CNF filter builder.
  def apply
    apply_filter_and_redirect(moss_card_transactions_path)
  end

  private

  def authorize_action
    authorize!(:fin_admin, MossCardTransaction)
  end
end
