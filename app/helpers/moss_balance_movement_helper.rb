# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module MossBalanceMovementHelper
  def format_moss_balance_movement_accounting_entry_id(tx)
    link_to(tx.accounting_entry_id, url_for(tx.accounting_entry))
  end

  def format_moss_balance_movement_amount(tx)
    tx.amount_eur_display
  end
end
