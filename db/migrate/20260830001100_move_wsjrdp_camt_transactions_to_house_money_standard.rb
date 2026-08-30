# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Move wsjrdp_camt_transactions from the legacy integer-cents dialect to the
# house money standard (doc/fin/money_conventions.md): the account-perspective
# pattern (the SIGNED amount is the input, the unsigned one is generated),
# EUR-only.
#
#   amount_cents (integer)  -> signed_base_amount numeric(20,3)  (signed input, + = inflow)
#                           +  base_amount = ABS(signed_base_amount)          (generated)
#   amount_currency         -> base_currency  (RENAMED: same varchar, same EUR
#                              value, NOT NULL + default carried over) + CHECK = 'EUR'
#   (new)                      debit_credit = C/D from credit_debit_indication (generated)
#
# credit_debit_indication (the ISO CRDT/DBIT source mirror) stays and gains a
# CHECK -- it is the source of the generated debit_credit. amount_cents is
# DROPPED here (only signed_base_amount replaces it, a real type/value change);
# amount_currency is merely renamed. `down` restores amount_cents exactly
# (ROUND(signed_base_amount * 100)) and renames base_currency back. A pre-flight
# guard and an exhaustive verify gate the (irreversible) amount_cents drop; the
# data is also fully re-importable from External_Data/CAMT.
class MoveWsjrdpCamtTransactionsToHouseMoneyStandard < ActiveRecord::Migration[7.1]
  TABLE = :wsjrdp_camt_transactions

  def up
    guard_preconditions!

    add_column TABLE, :signed_base_amount, :decimal, precision: 20, scale: 3, null: true,
      comment: "Signed booking amount in the base currency (EUR), account perspective (+ = inflow: CRDT +, DBIT -)"

    # Exact backfill from the integer cents (EUR minor unit = 2). No WHERE, so
    # every row is touched -- assert that.
    total = select_value("SELECT COUNT(*) FROM #{TABLE}").to_i
    updated = exec_update(<<~SQL.squish)
      UPDATE #{TABLE}
         SET signed_base_amount = amount_cents::numeric / 100
    SQL
    unless updated == total
      raise ActiveRecord::MigrationError,
        "backfill touched #{updated} of #{total} rows -- aborting"
    end

    # amount_currency and base_currency are the same varchar carrying the same
    # value (EUR): a metadata-only rename, not a data transformation. NOT NULL
    # and the 'EUR' default carry over automatically.
    rename_column TABLE, :amount_currency, :base_currency
    change_column_comment TABLE, :base_currency,
      "Base/ledger currency, always EUR (check-constrained)"

    add_column TABLE, :base_amount, :virtual, type: :decimal, precision: 20, scale: 3,
      stored: true, as: "ABS(signed_base_amount)",
      comment: "Sign-less base-currency amount"
    add_column TABLE, :debit_credit, :virtual, type: :string, stored: true,
      as: "CASE WHEN credit_debit_indication = 'CRDT' THEN 'C' ELSE 'D' END",
      comment: "Debit/credit (C/D) derived from the ISO credit_debit_indication"

    change_column_null TABLE, :signed_base_amount, false
    add_check_constraint TABLE, "base_currency = 'EUR'",
      name: "chk_wsjrdp_camt_tx_base_currency"
    add_check_constraint TABLE, "credit_debit_indication IN ('CRDT', 'DBIT')",
      name: "chk_wsjrdp_camt_tx_credit_debit_indication"

    verify_before_drop!(total)

    remove_column TABLE, :amount_cents
  end

  def down
    add_column TABLE, :amount_cents, :integer, null: true
    execute(<<~SQL.squish)
      UPDATE #{TABLE}
         SET amount_cents = ROUND(signed_base_amount * 100)::int
    SQL
    change_column_null TABLE, :amount_cents, false

    # Remove the checks first, so renaming base_currency back does not carry a
    # constraint onto the restored amount_currency.
    remove_check_constraint TABLE, name: "chk_wsjrdp_camt_tx_base_currency"
    remove_check_constraint TABLE, name: "chk_wsjrdp_camt_tx_credit_debit_indication"
    remove_column TABLE, :debit_credit
    remove_column TABLE, :base_amount
    remove_column TABLE, :signed_base_amount
    # base_currency is the renamed amount_currency -- rename it back (NOT NULL +
    # 'EUR' default carry over); restore the original (comment-less) state.
    rename_column TABLE, :base_currency, :amount_currency
    change_column_comment TABLE, :amount_currency, nil
  end

  private

  # Abort before any change if the assumptions behind the backfill / the
  # generated debit_credit do not hold.
  def guard_preconditions!
    bad_ccy = select_value(
      "SELECT COUNT(*) FROM #{TABLE} WHERE amount_currency <> 'EUR'"
    ).to_i
    if bad_ccy.positive?
      raise ActiveRecord::MigrationError,
        "#{bad_ccy} row(s) with amount_currency <> 'EUR': signed_base_amount = " \
        "amount_cents/100 assumes EUR (minor unit 2) -- refusing to migrate."
    end

    bad_cdi = select_value(
      "SELECT COUNT(*) FROM #{TABLE} " \
      "WHERE credit_debit_indication IS NULL OR credit_debit_indication NOT IN ('CRDT', 'DBIT')"
    ).to_i
    if bad_cdi.positive?
      raise ActiveRecord::MigrationError,
        "#{bad_cdi} row(s) with credit_debit_indication not in ('CRDT','DBIT'): " \
        "debit_credit derives from it -- refusing to migrate."
    end
  end

  # The single safety gate before the irreversible drop of amount_cents /
  # amount_currency. Every check must come back 0; each is logged for an audit
  # trail. Deliberately exhaustive.
  def verify_before_drop!(total)
    zero_checks = {
      "a) unbackfilled" =>
        "SELECT COUNT(*) FROM #{TABLE} WHERE signed_base_amount IS NULL OR base_currency IS NULL",
      "b) per-row cents equality" =>
        "SELECT COUNT(*) FROM #{TABLE} WHERE ROUND(signed_base_amount * 100) <> amount_cents",
      "d) base_currency all EUR" =>
        "SELECT COUNT(*) FROM #{TABLE} WHERE base_currency <> 'EUR'",
      "e) base_amount = ABS(signed_base_amount)" =>
        "SELECT COUNT(*) FROM #{TABLE} WHERE base_amount <> ABS(signed_base_amount)",
      "f) debit_credit vs sign" =>
        "SELECT COUNT(*) FROM #{TABLE} " \
        "WHERE (debit_credit = 'C' AND signed_base_amount < 0) " \
        "OR (debit_credit = 'D' AND signed_base_amount > 0)"
    }
    zero_checks.each do |name, sql|
      offenders = select_value(sql).to_i
      say "verify #{name}: #{offenders}"
      if offenders.positive?
        raise ActiveRecord::MigrationError,
          "camt money migration verify FAILED at #{name}: #{offenders} offending row(s)"
      end
    end

    # c) aggregate cross-check: SUM(amount_cents) must equal ROUND(SUM(signed)*100).
    delta = select_value(<<~SQL.squish).to_i
      SELECT COALESCE(SUM(amount_cents), 0)
           - ROUND(COALESCE(SUM(signed_base_amount), 0) * 100)::bigint
        FROM #{TABLE}
    SQL
    say "verify c) aggregate cents delta: #{delta}"
    unless delta.zero?
      raise ActiveRecord::MigrationError,
        "camt money migration verify FAILED: aggregate cents delta #{delta}"
    end

    # g) row count unchanged since the backfill.
    now = select_value("SELECT COUNT(*) FROM #{TABLE}").to_i
    say "verify g) row count: #{now} (backfilled #{total})"
    unless now == total
      raise ActiveRecord::MigrationError,
        "camt money migration verify FAILED: row count #{now} <> #{total}"
    end
  end
end
