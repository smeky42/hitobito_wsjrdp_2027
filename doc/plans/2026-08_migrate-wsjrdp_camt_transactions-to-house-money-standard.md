# Plan: `wsjrdp_camt_transactions` → house money standard (EUR-only, single migration)

## Context
`wsjrdp_camt_transactions` still uses the legacy integer-cents dialect
(`amount_cents` int, `amount_currency`, `credit_debit_indication`). It is the one
finance table `doc/fin/money_conventions.md` currently **exempts** ("Not to be
touched … ISO 20022 source mirror"). Goal: bring it onto the house standard
(`numeric(20,3)`, signed account-perspective convention) so it reconciles
uniformly with `datev_bookings` / `moss_card_transactions`.

Decisions (confirmed):
- **EUR-only (minimal)** — no `transaction_*` / `exchange_rate`, no CAMT-parser FX
  work. All data is EUR; the parser exposes no FX anyway.
- **Single migration (phase 1 + 2 together)** — add + backfill + verify, then in
  the *same* migration **drop `amount_cents`** (a real type/value change:
  integer cents → numeric EUR). `amount_currency` is **renamed** to
  `base_currency` (same varchar, same EUR value — a metadata-only rename, no
  backfill/drop). The `down` restores `amount_cents` and renames back. The exact
  in-migration verify gates the `amount_cents` drop; full re-import from
  `External_Data/CAMT` is the safety net if `signed_base_amount` were ever
  miscomputed.
- The Python importer writes **only** the new columns (no more
  `amount_cents`/`amount_currency`).
- `credit_debit_indication` stays (ISO CRDT/DBIT source mirror).

## Setup (before any change)
- Work happens on the **existing** branch **`2026-08_migrate-wsjrdp_camt_transactions-to-house-money-standard`**, which already exists and is checked out in BOTH repos (wagon + `wsjrdp_scripts`). Verify with `git branch --show-current` in each before starting — do not create or re-branch it.
- Save this plan (in English) to the wagon at **`doc/plans/2026-08_migrate-wsjrdp_camt_transactions-to-house-money-standard.md`** so it stays available for later reference (alongside the existing `doc/plans/*`).

## Target columns (account-perspective, single-sided, EUR-only)
Template: `moss_card_transaction_bookings` (`db/migrate/20260829000200_add_moss_card_transactions.rb`) — signed amount is the **input**, unsigned is generated. Final state of the money columns:

| column | kind | definition |
|---|---|---|
| `signed_base_amount` | input | `numeric(20,3)`, signed (+ = inflow: CRDT +, DBIT −), NOT NULL. Importer writes this. |
| `base_amount` | generated | `t.virtual … as: "ABS(signed_base_amount)", stored: true` — reconciliation anchor. |
| `base_currency` | input (renamed) | `varchar NOT NULL, default "EUR"` + CHECK `base_currency = 'EUR'`. **Renamed** from `amount_currency` (NOT NULL + default carry over). |
| `debit_credit` | generated | `t.virtual … as: "CASE WHEN credit_debit_indication = 'CRDT' THEN 'C' ELSE 'D' END", stored: true`. |
| `credit_debit_indication` | kept + constrained | ISO CRDT/DBIT source mirror; the source of `debit_credit`. This migration adds a CHECK `IN ('CRDT','DBIT')` (and a pre-flight guard) so that source stays clean. |
| ~~`amount_cents`~~ | **dropped** | removed in this migration (down restores via `ROUND(signed_base_amount*100)`). |
| ~~`amount_currency`~~ | **renamed** | → `base_currency` (down renames back). |

**`debit_credit` is derived from `credit_debit_indication`, not from the sign** (a deliberate deviation from the moss template, which has no ISO indicator). Verified against the live table (232 rows): `credit_debit_indication` is NOT NULL, only ever `CRDT`/`DBIT`, and 100 % consistent with the sign of `amount_cents` (0 mismatches). Deriving from the ISO indicator is source-faithful and robust for a zero-amount booking (`amount = 0` with `CdtDbtInd = 'CRDT'` would be mis-labelled `'D'` by a `signed_base_amount > 0` rule; there are 0 such rows today, but the ISO field states the truth regardless).

No `transaction_*`/`exchange_rate` (EUR-only). Out of scope: the existing id-based `account_*`/`offsetting_account_*` columns (different pattern, not money/rate).

## Migration — `db/migrate/20260830001100_*.rb` (raw-SQL, reversible `up`/`down`)
`def up`:
1. **Pre-flight guards (at the very start, before any DDL/DML — abort the whole migration on failure):**
   - `RAISE` if any row has `amount_currency <> 'EUR'` (a non-EUR ISO exponent would make `/100` wrong — none exist today).
   - `RAISE` if any row has `credit_debit_indication IS NULL OR credit_debit_indication NOT IN ('CRDT','DBIT')` — the generated `debit_credit` derives from this column, so it must be clean before we depend on it (verified: 0 offenders today).
2. `add_column :signed_base_amount, :decimal, precision: 20, scale: 3` (nullable).
3. **Backfill (exact) + rename the currency (metadata-only):** `UPDATE … SET signed_base_amount = amount_cents::numeric / 100` (no WHERE → all rows; assert affected == total), then `rename_column :amount_currency, :base_currency` (same varchar/EUR value; NOT NULL + `'EUR'` default carry over) and set its comment.
4. Add generated `base_amount` = `ABS(signed_base_amount)` and `debit_credit` = `CASE WHEN credit_debit_indication = 'CRDT' THEN 'C' ELSE 'D' END` (both `t.virtual … stored: true`).
5. `change_column_null :signed_base_amount, false` (`base_currency` is already NOT NULL from the rename); `add_check_constraint "base_currency = 'EUR'", name: "chk_wsjrdp_camt_tx_base_currency"`; `add_check_constraint "credit_debit_indication IN ('CRDT', 'DBIT')", name: "chk_wsjrdp_camt_tx_credit_debit_indication"` (guarantees the `debit_credit` source stays clean going forward).
6. **Verify — gates the drop.** Run each check with `select_value` and `raise ActiveRecord::MigrationError, "<msg>"` unless the count is 0. This is the single safety gate before the irreversible drop, so it is deliberately exhaustive:
   - **a) nothing unbackfilled:** `WHERE signed_base_amount IS NULL OR base_currency IS NULL` = 0.
   - **b) exact per-row cents equality (the core lossless proof):** `WHERE ROUND(signed_base_amount * 100) <> amount_cents` = 0.
   - **c) aggregate cross-check (catches systematic drift):** `SUM(amount_cents) = ROUND(SUM(signed_base_amount) * 100)` — else raise.
   - **d) base_currency all EUR:** `WHERE base_currency <> 'EUR'` = 0.
   - **e) generated `base_amount` sane:** `WHERE base_amount <> ABS(signed_base_amount)` = 0.
   - **f) `debit_credit` consistent with the sign (non-zero rows):** `WHERE (debit_credit = 'C' AND signed_base_amount < 0) OR (debit_credit = 'D' AND signed_base_amount > 0)` = 0.
   - **g) row count unchanged:** the count from step 3's UPDATE equals `COUNT(*)` (no rows added/removed).
   Log each check's result (name + count) so a run leaves an audit trail before the drop.
7. Only if all of step 6 passed: `remove_column :amount_cents` (`amount_currency` is already gone — renamed in step 3).

`def down` (restores losslessly):
1. `add_column :amount_cents, :integer` (nullable).
2. `UPDATE … SET amount_cents = ROUND(signed_base_amount*100)::int` (exact: `signed_base_amount` was cents/100).
3. `change_column_null :amount_cents, false`.
4. Remove both check constraints added in `up` (`chk_wsjrdp_camt_tx_base_currency` **and** `chk_wsjrdp_camt_tx_credit_debit_indication` — the `credit_debit_indication` column itself is pre-existing and stays); drop generated `debit_credit`, `base_amount`; `remove_column :signed_base_amount`; then `rename_column :base_currency, :amount_currency` (checks already removed, so no constraint carries onto the restored column) and reset its comment to `nil`.

Then `wagon:schema_dump` (regenerate `db/schema.rb` + `.diff`).

**Zero-data-loss basis:** the currency is a metadata-only **rename** (trivially preserved); cents→numeric is exact (`int/100`); the step-6 verify proves per-row cents equality *before* the `amount_cents` drop; `down` re-derives `amount_cents` exactly and renames the currency back; and the whole set is re-importable from source.

## Python — `accounting_tools/import_camt_bank_statements.py`
- `_tx_value_row`: **replace** `amount_cents`/`amount_currency` with `"signed_base_amount": Decimal(tx.amount_cents) / 100` and `"base_currency": tx.amount_currency`. (The parser attribute `tx.amount_cents` stays; only the DB columns change.) `base_amount`/`debit_credit` are DB-generated → never written. `credit_debit_indication` unchanged.
- `_IMMUTABLE`: `("signed_base_amount", "base_currency", "value_date")` (was amount_cents/amount_currency/value_date).
- Update the module docstring (money columns list).
- Legacy `_pg.py` writers/readers that name the old columns **must** be updated (they would break once `amount_cents` is dropped / `amount_currency` renamed): `pg_insert_camt_transaction` / `pg_insert_camt_transaction_from_tx` (write `amount_cents`/`amount_currency` → write `signed_base_amount`/`base_currency`) and `pg_select_camt_tx_unique_db_key2row` (selects `amount_cents,amount_currency,value_date` → `signed_base_amount,base_amount,base_currency,debit_credit,value_date`). `accounting_tools/one-shots/2026-01-04--Initial-CAMT-Upload.py` uses the wrapper — its `tx.amount_cents` logging still works (parser attr).

## Wagon — migrate every consumer off `amount_cents`/`amount_currency`
(`amount_cents` is dropped and `amount_currency` renamed, so no fallback — all must move.)
- `app/models/wsjrdp_camt_transaction.rb`: replace `eur_attribute :amount_eur, cents_attr: :amount_cents` (:36) with `amount_eur` / `amount_eur=` / `amount_eur_display` / `amount_eur_input_field_options` **backed by `signed_base_amount`** (EUR, via `eur_display_or_nil`). Keep them because the shared fin_account statement view and `link_name` use `amount_eur_display` polymorphically with `MossBalanceMovement`. `link_name` (:80) stays unchanged.
- `app/models/concerns/wsjrdp_transaction.rb:57-66` (shared with `MossBalanceMovement`): leave the concern generic (its `accounting_entries_for_subject(amount_cents:)` compares against `AccountingEntry.amount_cents`, which **stays** integer-cents). **Override** `accounting_entries_for_subject_with_matching_amount` in the camt model to pass `(signed_base_amount * 100).round`; moss keeps using the concern default (its own `amount_cents`). The one cross-dialect boundary.
- `app/models/wsjrdp_fin_account.rb:53-55` `closing_balance_cents`: `transactions` are camt (bank) or moss (wallet) — sum in cents across both: `e.respond_to?(:signed_base_amount) ? (e.signed_base_amount*100).round : e.amount_cents`.
- `app/controllers/fin/wsjrdp_camt_transactions_controller.rb`: `create_accounting_entry` (:52-53) read `signed_base_amount`→cents + `base_currency`; `matching_accounting_entries` (:135) compare `e.amount_cents == (camt.signed_base_amount*100).round`.
- Views: `app/views/fin/wsjrdp_camt_transactions/show.html.haml:21`, `app/views/fin/wsjrdp_fin_accounts/show.html.haml:39,41`, `app/views/person/fee/_journal_entries.html.haml` (via `link_name`) → show `signed_base_amount`/`base_amount` + `base_currency`.
- `config/locales/wsjrdp_2027.de.yml:222-225`: replace the `amount_cents`/`amount_eur`/`amount_currency` labels with `signed_base_amount`/`base_amount`/`base_currency`/`debit_credit`.
- `doc/fin/money_conventions.md` (**one fewer integer-cents table**): update the "Not to be touched" note so it lists **only `accounting_entries`** (remove `wsjrdp_camt_transactions`); rewrite the landscape-table row for `wsjrdp_camt_transactions` (`integer cents / signed / EUR only` → `numeric(20,3) / signed input + generated ABS view / debit_credit from credit_debit_indication / EUR only, base_currency checked`); and note it in Status/plans as an account-perspective (EUR-only) table now following the standard.

## Verification (end-to-end, on dev)
- **Migration:** fresh restore from `data/hitobito_production_20260830-132144.dump` → `wagon:migrate`; confirm the step-6 verify passed and that `amount_cents` is **gone**, `amount_currency` is **renamed** to `base_currency`, `signed_base_amount`/`base_amount`/`debit_credit` present. Spot-check (against a pre-migration snapshot table): `base_amount = ABS(signed_base_amount)`, `debit_credit` agrees with `credit_debit_indication`, `ROUND(signed_base_amount*100) = snap.amount_cents` and `base_currency = snap.amount_currency` for all rows.
- **down/up:** `app:db:migrate:down` does not see wagon migrations, so test reversibility via a rails runner (`load` the migration file, `.new.migrate(:down)` then `.migrate(:up)`); `down` must restore `amount_cents` + rename `base_currency` back to `amount_currency` exactly (compare to the snapshot), re-`up` clean.
- **Importer:** `import_camt_bank_statements.py External_Data/CAMT/*/*.xml` → writes only the new columns; idempotent (2nd run 0/0/0); empty-table import fills `signed_base_amount`/`base_currency` on all rows; immutable + AcctSvcrRef guards pass.
- **Wagon UI (must keep working):** load these pages in the Browser pane and confirm HTTP 200 + rendered content (no 500), correct closing balances and per-transaction amounts (they exercise `closing_balance_cents` and the `signed_base_amount`/`link_name` display):
  - `http://localhost:3000/fin/acc` — the account list.
  - `http://localhost:3000/fin/acc/2`, `http://localhost:3000/fin/acc/3` — bank accounts (closing balance = opening + Σ `signed_base_amount`; bank-statement rows show amounts).
  - `http://localhost:3000/fin/acc/4` — the **Moss wallet** (uses the `MossBalanceMovement` branch of `closing_balance_cents`, i.e. NOT camt — must be unaffected; confirms the concern change didn't regress the moss side).
  Cross-check each account's closing balance against the pre-migration value.
- **Wagon tests/lint:** `bin/rspec` finance specs (abilities + fin_account/camt); `rubocop -a`.
- **Static:** `ruff` + `ty` on the importer.

## Out of scope
FX (`transaction_*`/`exchange_rate` + parser `AmtDtls`/`XchgRate`); the id-based `account_*` columns; `accounting_entries` (stays integer-cents by house rule).
