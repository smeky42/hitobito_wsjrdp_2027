# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027
module Wsjrdp::Sync::MossApi
  # The expense accounts (GET /v1/expense-accounts) into wsjrdp_ledger_accounts.
  class LedgerAccounts < MasterPart
    self.key = "moss_api.master_data.ledger_accounts"
    self.path = "v1/expense-accounts"
    self.model = WsjrdpLedgerAccount
    self.sort_orders = %w[account_number -account_number].freeze

    def self.number(code) = WsjrdpLedgerAccount.number_from(code)
  end
end
