# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Column definitions of the account list (Konten & Wallets, Übersicht at
# /fin/acc): one WsjrdpFinAccount per row. The rows are a relation
# (Fin::WsjrdpFinAccountsController#accounts), so every column sorts by an SQL
# expression.
#
# The balance (BALANCE_SQL) is computed in SQL so it can be sorted: the opening
# balance plus the account's statement rows -- the camt transactions of a bank
# account, the Moss bookings of the wallet -- branching on the same marker as
# WsjrdpFinAccount#transactions, so it equals #closing_balance_cents.
module Fin::FinAccountsColumns
  BALANCE_SQL = <<~SQL.squish
    (wsjrdp_fin_accounts.opening_balance_cents / 100.0 + CASE
      WHEN wsjrdp_fin_accounts.transaction_type = 'MossBalanceMovement' THEN
        COALESCE((SELECT SUM(b.signed_base_amount) FROM moss_bookings b
          JOIN moss_transactions t ON t.id = b.moss_transaction_id
          WHERE t.fin_account_id = wsjrdp_fin_accounts.id), 0)
      ELSE
        COALESCE((SELECT SUM(c.signed_base_amount) FROM wsjrdp_camt_transactions c
          WHERE c.fin_account_id = wsjrdp_fin_accounts.id), 0)
    END)
  SQL

  PRODUCT_RANK_SQL = "array_position(ARRAY[#{WsjrdpFinAccount::ACCOUNT_PRODUCTS.map { |p| "'#{p}'" }.join(", ")}]" \
    "::varchar[], wsjrdp_fin_accounts.account_product)"

  # Narrow screens: no column gives way on its own -- the table scrolls
  # sideways instead, with the account's name staying at the left; the name
  # starts narrow and widens to its target. Wide screens: the name, the
  # institute, the account type and the G/L account grow further (`grow:`), then
  # the gaps (`t.gaps` in the view). Kontoart is in the columns menu only.
  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "facol") do |c|
    c.column key: "label", abbr: "lb", label: "Konto", width: "9rem", target_width: "15rem", grow: 2,
      truncate: true, sticky: true,
      sort: "LOWER(COALESCE(NULLIF(wsjrdp_fin_accounts.short_name, ''), wsjrdp_fin_accounts.account_identification))",
      default: true
    c.column key: "servicer", abbr: "sv", label: "Institut", width: "7rem", target_width: "10rem", grow: 1,
      truncate: true,
      sort: "LOWER(wsjrdp_fin_accounts.servicer_short_name)", default: true
    c.column key: "product", abbr: "pr", label: "Kontoart", width: "7rem", target_width: "10rem", grow: 1,
      truncate: true,
      sort: PRODUCT_RANK_SQL
    c.column key: "iban", abbr: "ib", label: "IBAN / Kennung", width: "15rem", tabular_nums: true,
      sort: "COALESCE(NULLIF(wsjrdp_fin_accounts.iban, ''), wsjrdp_fin_accounts.account_identification)",
      default: true
    c.column key: "bookkeeping", abbr: "bk", label: "Sachkonto", width: "8rem", target_width: "11rem", grow: 1,
      truncate: true, tabular_nums: true,
      sort: "wsjrdp_fin_accounts.bookkeeping_account_number", default: true
    c.column key: "balance", abbr: "sa", label: "Saldo", numeric: true, width: "8.5rem",
      sort: BALANCE_SQL, sort_first: "desc", default: true
  end
end
