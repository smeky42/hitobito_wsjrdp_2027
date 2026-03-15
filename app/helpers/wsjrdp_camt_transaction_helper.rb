# frozen_string_literal: true

#  Copyright (c) 2025 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module WsjrdpCamtTransactionHelper
  def format_wsjrdp_camt_transaction_accounting_entry_id(tx)
    link_to(tx.accounting_entry_id, url_for(tx.accounting_entry))
  end
end
