# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The model half of the Sachkonten detail (fin/ledger_accounts/_detail): one
# formatter per field of a WsjrdpLedgerAccount that shows more than its stored
# value, found by the name rule of Fin::AttrFormatHelper
# (fin_format_wsjrdp_ledger_account_<attr>).
#
# The labels of the fields live in
# de.activerecord.attributes.wsjrdp_ledger_account; a field without a formatter
# takes the finance type rules of Fin::AttrFormatHelper -- which is why the
# number, the two names and the two texts need none.
module Fin::LedgerAccountsHelper
  # The account kind in words, as the Buchungen views spell it.
  def fin_format_wsjrdp_ledger_account_account_kind(account)
    account_kind_label(account.account_kind)
  end

  # The Moss status in words, as every other finance view spells it.
  def fin_format_wsjrdp_ledger_account_moss_status(account)
    moss_status_cell(account.moss_status)
  end

  # Whether a booking on this account belongs to a unit's budget. The column is
  # NOT NULL, so the field always says ja or nein -- what the two accounts of a
  # BOOKING then make of it is DatevBooking's three-step rule.
  def fin_format_wsjrdp_ledger_account_is_unit_budget(account)
    account_unit_budget_label(account.is_unit_budget)
  end
end
