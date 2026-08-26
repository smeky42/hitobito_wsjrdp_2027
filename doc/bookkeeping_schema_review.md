# Bookkeeping tables — schema review & association plan

Status: **§2/§3 cleanups APPLIED** (create migrations updated + dev DB altered
additively + importers adapted). The association itself (§4) is still a
**proposal** — options reported, nothing implemented.

Applied changes (2026-08-20):
- `wsjrdp_ledger_accounts`: + `additional_info` jsonb, `account_type` NOT NULL,
  `deleted_at` dropped, **27 creditor stub rows deleted**, CHECK
  `number !~ '^7\d{5}$'`.
- `wsjrdp_cost_centers`: `moss_status` vocabulary aligned to Moss's
  (`inactive` → **`deactivated`**, 11 rows migrated; model/importer/locale
  updated), `deleted_at` dropped.
- `wsjrdp_personal_accounts`: `default_account/cost_center/sphere` →
  `*_number` suffix, + `account_type` NOT NULL default `'CREDITOR'` (+ CHECK),
  `deleted_at` dropped, CHECK `number ~ '^7\d{5}$'`.
- Importers: accounts importer **skips 7xxxxx creditor rows**; cc importer
  writes `deactivated`; supplier importer uses the renamed columns. Re-import
  baseline: ledger accounts **34** (was 61) / cc 82 / suppliers 88.

## 1. Table inventory

The DATEV bookkeeping feature consists of exactly four tables:

| Table | Rows (dev) | Role |
|---|---|---|
| `datev_bookings` | 6 568 | the bookings (Primanota import) |
| `wsjrdp_ledger_accounts` | 61 | DATEV chart of accounts (Sachkonten **incl. 27 personal/creditor accounts**) |
| `wsjrdp_cost_centers` | 82 | Kostenstellen (Moss master data) |
| `wsjrdp_personal_accounts` | 88 | Kreditoren (Moss master data) |

No table was missed. Adjacent but *not* part of bookkeeping:
`wsjrdp_fin_accounts` (payments feature). **Not existing (by design so far):**
tables for Sphären (plain codes) and for Primanota import runs (provenance
lives denormalised on each booking: source_file/sheet, primanota_*).

## 2. Discrepancies found

1. **Three different lifecycle mechanisms.**
   - bookings: `status` ("active"/"soft_deleted") + `deleted_at`
   - reference tables: `deleted_at` only — **never set anywhere** (0 rows in
     all three; currently a dead column)
   - cost centers + suppliers: `moss_status`
   Suggest deciding on one convention per kind (bookings' status machine is
   fine; the reference tables' `deleted_at` should either get used by the
   importers or be dropped).
2. **`moss_status` vocabulary differs**: cost centers use `"inactive"`,
   suppliers use `"deactivated"` for the same concept. Align (one word, one
   constant) before code starts branching on it.
3. **`additional_info` jsonb** exists on bookings, cost centers and suppliers —
   **missing on `wsjrdp_ledger_accounts`**. Add for symmetry when the table is
   next touched.
4. **`name` nullability**: suppliers `NOT NULL`, ledger accounts and cost
   centers nullable. The nullable case is real: the 27 creditor rows in the
   chart of accounts have **no name** (see below).
5. **`moss_status` missing on ledger accounts** (accounts exist in Moss too);
   fine for now, worth adding if account sync with Moss ever matters.
6. **Naming convention drift**: bookings consistently use `*_number`
   (`account_number`, `cost_center_number`, `sphere_number`); the suppliers
   table's defaults do not (`default_account`, `default_cost_center`,
   `default_sphere`). Rename to `default_account_number` etc. at the next
   schema touch.
7. **`account_type` duplication and nullability**: bookings carry
   `account_type`/`offsetting_account_type` `NOT NULL`; the source column
   `wsjrdp_ledger_accounts.account_type` is nullable (currently 0 NULLs). Both
   are derived from the same number heuristic
   (`account_type_for_account_number`), not joined — they can only drift if
   that rule changes. Suggest `NOT NULL` on the ledger column and treating the
   Python heuristic as the single source until a real DATEV Kontenart export
   exists.
8. **Missing indexes on `datev_bookings`**: no index on `account_number`,
   `offsetting_account_number`, `cost_center_number` — the bookkeeping
   summaries and the new filter group/filter on exactly these. Suggest three
   plain b-tree indexes (cheap, high value).
9. **Types are consistent** where it matters: every account/cost-center/sphere
   number is `character varying` on both sides of every potential join;
   timestamps are `timestamp(6)`; money is `numeric(20,3)`. ✓

## 3a. Root cause of the 27 creditor stubs (investigated & hardened)

Why did the accounts CSV contain 27 nameless 7xxxxx rows at all? Evidence from
comparing the CSV against the bookings:

- the CSV's 27 creditors are a strict **subset of the 43** creditor numbers
  used in bookings — exactly the ones with postings *up to the export date*
  (the 16 missing ones are newer);
- the CSV's Sachkonten side contains the **full chart** (incl. 4 accounts
  never used in any booking), all with names;
- **every** creditor row is nameless, **every** Sachkonto is named.

Conclusion: the CSV was a DATEV **Sachkonten list export that included the
bespielten Personenkonten** as of the export date. In DATEV's Sachkonten frame
personal accounts appear in account lists, but their *Beschriftung* column is
empty — creditor names live in the Debitoren/Kreditoren-Stammdaten (the
suppliers export). So there never was real master-data overlap; the export
simply mixed the two account kinds, and the importer dutifully inserted stubs.

Hardening applied: the 27 lines were removed from `datev_accounts.csv`, the
accounts importer now **aborts with a hard error** (exit 1, offending numbers
listed) when the CSV contains any 7xxxxx number, and
`datev-stammdaten-export.md` instructs the accountant to filter the Sachkonten
list to Sachkonten only before exporting.

## 3b. secondary_cost_center_number (investigated & repurposed)

Why did the column contain data? The original importer design filled it with
"the respective other KOST column". Measurement: for **all 4 866** rows with
fiscal year ≥ 2026 it equalled `sphere_number` exactly (in SKR42, KOST1 *is*
the Sphäre — so "the other KOST column" duplicates the sphere), and for all
1 702 rows ≤ 2025 it was NULL (those files carry no KOST2). The column held
**zero independent information**.

Fix applied: the import **never writes** `secondary_cost_center_number` any
more (removed from the parser and the insert/update column lists), a re-import
**preserves** whatever is there (verified: a manual value survives a full
Mai re-import), the 4 866 import-written duplicates were set to NULL, and the
column is documented as manually maintained (migration comment + importer
docstring). The raw KOST values remain available in `original_kost1/2`.

## 3c. Matching accounting_entries ↔ datev_bookings (verified strategy)

Every channel was probed on live data (2026-08-20); numbers are exact.

**Scope: pre-notifications are NEVER part of the reconciliation.** A
pre-notification (`wsjrdp_direct_debit_pre_notifications`) is the announcement
of an upcoming direct debit — it is shown in a person's private financial tab,
but it is **not a money movement** and is never itself reconciled against
anything. Reconciliation matches exactly two things: **accounting entries**
(the actual payments/movements) and **DATEV bookings**. Pre-notifications
appear in the strategy below in ONE role only: their id is a **stable join
key** that the SEPA/DATEV generator embeds in Belegfeld 1 and that each
collection entry references (`direct_debit_pre_notification_id`) — nothing
more.

**The landscape.** 6 270 accounting_entries =
6 116 collection entries (`direct_debit_pre_notification_id` set) +
87 bank-statement entries (`camt_transaction_id`) + 15 Moss entries
(`moss_balance_movement_id`) + 52 unlinked (50 of them **zero-amount**
Finanzstatus notes — no booking exists by nature; plus one ±1 €
correction pair).

**Tier 1 — 2026 collections, deterministic.** The SEPA/DATEV generator
(wsjrdp_scripts `_datev.py`) writes
`Belegfeld 1 = "Einzug-YYYY-MM-{SEQ}-{run}-{pre_notification_id}"`.
The trailing id is the `wsjrdp_direct_debit_pre_notifications` id, and each
entry carries `direct_debit_pre_notification_id` →
**3 462 / 3 462 bookings resolve to exactly one entry, with amount AND
value-date agreement on every single pair.** Per-month counts of entries vs
bookings are identical for Jan–Jul 2026 (1172/1079/1072/38/31/35/35). The
1 068 August-2026 entries have no Primanota yet — they become Tier-1 matches
with the next Primanota import.

**Tier 2 — 2025 collections, heuristic but exact in practice.** 2025 bookings
carry no id (Belegfeld = "Aug%25" etc.), but the Buchungstext contains the
person number ("CMT 14 Ines Höfig / Beitrag"). Key =
(person number from text ∈ entry.description) × |amount| ×
(value_date within ±7 days): **1 586 / 1 601 unique, 0 ambiguous.**

**Tier 3 — the 15 remaining 2025 bookings are ALL camt events** (Retouren,
Stornierungen, Sondervereinbarungen, manual Überweisungen): each matches a
`camt_transaction`-linked entry by amount ± 30 days. The other camt entries
(87 total) and the 15 Moss entries are matched the same way (amount +
date [+ person text]); at these volumes a review list for the leftovers is
acceptable.

**Cross-check:** 1 601 2025 collection bookings = 1 586 (Tier 2) + 15
(Tier 3) exactly.

**Write-back (implemented 2026-08-20):** both link columns are set together
(`accounting_entry_id` — 1:1 via unique index — and
`person_id := entry.subject_id`).

- **Tier 1 (2026, deterministic)** is implemented as `DatevBookingMatcher`
  (wagon model) behind the *"Zuordenbare Buchungen verbinden"* button on
  /reconciliation/participant_fees: it connects every booking of the current
  filter scope whose Einzug-Belegfeld resolves to exactly one unlinked entry
  **of the person named in the Buchungstext** (extra safety check on top of
  the pn id). Matchable rows show a link icon in the table (generic
  `row_badge` hook of the bookings table).
- **Tier 2 (2025)** is implemented **at import**
  (`import_datev_primanota.py`, `_match_2025_fee_entries`): scope
  KOST 9500 + Gegenkonto 41030, person id from the Buchungstext, equal
  |amount| and **exact** `booking_date = value_date` (probe confirmed exact
  dates suffice: 1 586/1 595 unique, 0 ambiguous, 0 date misses; the 9 rest
  carry no person number — they are the Tier-3 camt cases). Idempotent,
  unambiguous-only, runs after every reconcile.
- **Tier 3** (camt/Moss leftovers) remains manual/for later.

**Matcher v2 (2026-08-20, review UI).** `DatevBookingMatcher.propose` returns
`{booking_id => Match(entry, level, basis)}` over four tiers (first hit wins,
exact |amount| always required, only entries without a booking):
A `:sure` Einzug-Kennung + person number; B `:sure` person number + exact
date (all years — covers 2025 in the UI too); C `:heuristic` person NAME in
the text + exact date; D `:heuristic` name ± 7 days (bank offsets, e.g.
Retouren). Empirics on the 68-row residue after A/B: 12 exact-name, 13
near-name, 2 ambiguous (skipped), 41 impossible under exact-amount (Retouren
include added bank fees; Sammel-Buchungen sum several entries) — so a name
heuristic can NOT match everything with exact amounts; the 41 need split/fee
handling later. `connect!` writes accounting_entry_id + person_id +
camt_transaction_id (mirrored from the entry) in ONE bulk UPDATE
(5 074 pairs ≈ 110 ms; propose ≈ 0.7 s over 5 116 rows). The reconciliation
page injects the proposal column (checkbox, green=sure / yellow=heuristic,
entry + person + basis) via the generic `extra_col` hook and offers
Auswahl / Seite / Alle connect modes. The importer mirrors
camt_transaction_id the same way after its 2025 matching. All links were
reset to NULL on 2026-08-20 for review.

**Matcher v4 (2026-08-20, scored).** propose now returns a `Result`
(proposals + per-booking alternatives). Score = person % × date %; the
amount must match exactly INCLUDING THE SIGN: the booking's signed amount
from the fee-account (41030) side must equal the entry's amount_cents
(empirically true for all 5 107 historical pairs — 41030 is always the
Gegenkonto and offsetting_amount = amount_cents). Besides the person's own
name, ALTERNATIVE names are matched: Person.sepa_name (account holder) and
additional_contact_name_a/b — exact 80, per-word typo-tolerant 65 (multi-word
names only). Shared Jira-style REFERENCE CODES (e.g. "HELP-1681" in both the
Buchungstext and the entry description) override the date component with
100 % — Abmeldungs-refunds are often booked weeks after the payout, far
outside the ±7-day window (seen: 14 and 24 days); code-carrying entries join
the candidate pool date-independently via an extra `description ~* code`
query. Booking-side codes are read from the texts AND Belegfeld 1/2 (e.g.
Belegfeld 1 "HELP-1448"). Dates beyond ±7 days score 40 up to ±92 days
(~three months); beyond that a pair is NEVER an automatic candidate (only a
shared code). Manual associations (person AND entry) live in the shared
booking detail view on every host (bookings list, booking page,
reconciliation); the entry field autocompletes over unlinked entries with
EXACTLY the booking's signed amount
(`GET /bookkeeping/bookings/:id/query_entries`). On "moving the fuzzy matching to SQL": PostgreSQL could do it
(`fuzzystrmatch` levenshtein / `pg_trgm` similarity; both extensions are
available but NOT installed in this DB — would need `enable_extension` in a
migration, i.e. prod DB rights). Not worth it at current volume: the pool is
pre-filtered by signed amount + date window in SQL, so the Ruby fuzzy pass
touches only a few hundred pairs (~200 ms total). Person: 100 person_id already on the booking /
prefixed person number / short full name; 85 full name fuzzy (Levenshtein
≤ 2); 70 last name exact; 60 last name fuzzy or bare person number; 40 first
name ONLY (low); 30 first name only fuzzy (very low). Date: 100 exact,
70 ± 7 days — the entry's value_date AND booking_date both count. Score 100
⇒ `:sure`, else `:heuristic`; ties propose nothing but surface as
alternatives (≤ 5, shown in the detail view with per-candidate connect
buttons; > 1 candidate is flagged as "N Kandidaten" in the proposal column).
The detail view (shared layout with the Buchhaltung item details,
`shared/_detail_fields`, no tinted background) puts the person-assign +
connect controls at the top; the person autocomplete uses per-booking form
scopes (`as: datev_booking_<id>`) because hitobito's autocomplete binds by
DOM id and duplicate ids leave all but the first widget dead.

### 3c-bis. Matcher refinements (2026-08)

Three changes to `DatevBookingMatcher` / the reconciliation UI:

1. **Import-exact vs heuristic is now a `kind`, not the score.** `Match#kind`
   is `:import` for the Ende-zu-Ende-ID channel (the same deterministic rule
   the DATEV import itself applies — Belegfeld 1 → pre-notification id → the
   unique entry) and `:heuristic` for the scored person/date/initials channel.
   `#level` derives from `kind`, so a **scored 100 % is `:heuristic`** (amber),
   never `:sure`. Only an `:import` match is green. Rationale: a heuristic full
   hit is still a guess; the green/amber split now answers "would the import
   have made this link?" instead of "is the score 100 %?".

1b. **2025 import-equivalence** (`import_equivalent_2025?`, added 2026-08-21).
   A 2025 pair whose Buchungstext carries the person id WITH its role prefix and
   whose entry Valuta is EXACTLY the booking date is also marked `kind: :import`
   (green), because that is precisely the rule the importer applies for 2025
   (wsjrdp_scripts `_match_2025_fee_entries`: person id from the text, exact
   signed amount, `value_date = booking_date`). The amount is already guaranteed
   by the candidate pool and only unambiguous best hits are proposed, so the
   matcher's result is a superset only in the importer's scope restriction
   (cost center 9500 / Gegenkonto 41030). Measured on the live dev data: **1586**
   pairs qualify — the same 1586 the importer links (doc §3c Tier 2).

2. **Initials channel** (`initials_component`, lowest-confidence person tier).
   Fully anonymised refund texts such as `"YP P.D. / Konto S.D. und G.D."`
   carry no full name, id or reference code — only initials. The channel
   matches the person's own initials (required) against the text's `X.Y.`
   pairs, and raises the score when the SEPA account-holders' initials (from
   `sepa_name` / `additional_contact_name_a|b`, split on `& und + , /`) also
   appear: person only 45, +1 holder 65, +2 holders 75. Still gated by the hard
   exact-amount rule, so the candidate pool stays tiny (e.g. booking #219 →
   entry #5678 is the unique −180000 candidate → a single heuristic proposal).

3. **Entry autocomplete** (`Fin::BookingsController#query_entries`): a purely
   numeric query is an id search (prefix, exact id first) so typing `5678`
   autocompletes straight to Beitragsbuchung #5678 (still only among
   same-amount unlinked entries).

## 3. The 27 dual numbers (RESOLVED by the table split)

> **Update (applied):** the 27 nameless creditor stubs were deleted from
> `wsjrdp_ledger_accounts`, the accounts importer now skips 7xxxxx rows, and
> CHECK constraints enforce the split in both directions. Numbers are now
> globally unambiguous: 7xxxxx ⇒ suppliers, everything else ⇒ ledger accounts.
> The analysis below is kept for the history of the decision.

The DATEV chart of accounts (`datev_accounts.csv`) legitimately **contains the
creditor (personal) accounts** — 27 rows `700xxx` with **empty name columns**.
The same numbers exist in `wsjrdp_personal_accounts` with their real names (Moss). So:

- `wsjrdp_ledger_accounts` = the full DATEV chart incl. nameless creditor stubs
  (`account_type = "CREDITOR"`),
- `wsjrdp_personal_accounts` = the rich master data for exactly those creditors,
- **number alone is ambiguous** for these 27 — every join/label/association
  must dispatch on the type (CREDITOR → supplier).

Bookings currently reference numbers that all resolve (0 unknown numbers), and
the disambiguator already exists on every booking row:
`account_type`/`offsetting_account_type`.

Consequence already fixed in the filter: the merged Konto/Gegenkonto option
list showed the nameless stub label ("700019 ") instead of the supplier name;
`Filtering::Options.merge` now prefers the first **informative** label and
orders by number.

## 4. Polymorphic association — Option 1 IMPLEMENTED

> **Status:** Option 1 is implemented (2026-08-20): the two STORED GENERATED
> `*_ref_type` columns live in the create migration and the dev DB, and
> `DatevBooking` has `belongs_to :account` / `belongs_to :offsetting_account`
> (polymorphic, matched on `number`, `optional: true` because the reference
> tables are imported separately). Spec:
> `spec/models/datev_booking_accounts_spec.rb` (runs in the wagon test setup;
> locally verified via an equivalent transactional runner — 14 checks — since
> `maintain_test_schema!` needs exclusive DB access under the wagon setup).
> The options report below is kept as the decision record.

Goal: guides-style polymorphic `belongs_to` (Rails Association Basics,
"Polymorphic Associations") from a booking's `account_number` /
`offsetting_account_number` to `WsjrdpLedgerAccount` or `WsjrdpPersonalAccount`.
Class names in the bookings table are acceptable.

A classic polymorphic `belongs_to` needs a **type column** (class name) and a
**key column**. We have the key (`*_number`; both targets carry a unique
`number`, now with disjoint CHECK-enforced ranges) and the type is a pure
function of the existing `*_account_type` (`CREDITOR` ⇔ supplier). What's
missing is the class-name column — the options differ in how it comes to be.

### Option 1 — STORED GENERATED type columns (recommended)

Add to `datev_bookings` (same can't-drift pattern as `amount`):

```ruby
t.virtual :account_ref_type, type: :string, stored: true,
  as: "CASE WHEN account_type = 'CREDITOR' THEN 'WsjrdpPersonalAccount' ELSE 'WsjrdpLedgerAccount' END"
t.virtual :offsetting_account_ref_type, type: :string, stored: true,
  as: "CASE WHEN offsetting_account_type = 'CREDITOR' THEN 'WsjrdpPersonalAccount' ELSE 'WsjrdpLedgerAccount' END"
```

Then exactly the guides pattern, with custom column names:

```ruby
class DatevBooking < ActiveRecord::Base
  belongs_to :konto, polymorphic: true,
    foreign_key: :account_number, foreign_type: :account_ref_type,
    primary_key: :number
  belongs_to :gegenkonto, polymorphic: true,
    foreign_key: :offsetting_account_number, foreign_type: :offsetting_account_ref_type,
    primary_key: :number
end
```

- `booking.konto` / `booking.gegenkonto` return the right model; NOT NULL
  underneath, so not even `optional`.
- **Cannot drift**: the class name is computed by the DB from `account_type`,
  which the importer sets and the suppliers-side CHECK pins.
- Importer untouched (generated columns are never written).
- Class rename later = one migration replacing the CASE expression (drop/add
  generated column; data-free).

### Option 2 — plain physical type columns, importer-filled

Same association, but ordinary varchar columns that
`import_datev_primanota.py` fills (`'WsjrdpPersonalAccount'` /
`'WsjrdpLedgerAccount'`). Only advantage: no generated-column DDL. Costs:
importer change + backfill migration + the columns can silently drift from
`account_type` on any manual edit. Option 1 strictly dominates.

### Option 3 — `delegated_type` — not applicable

Rails' `delegated_type` models the *inverse* shape (one row owning a typed
"entryable"); it does not fit two lookup tables referenced by number.

### Option 4 — paired `belongs_to` + dispatch method (zero-migration fallback)

Two associations per side (`…_ledger_account` / `…_supplier`, each
`primary_key: :number, optional: true`) and a `konto` method dispatching on
`account_type`. Works today with no schema change, but `konto` is a method,
not an association (no `includes(:konto)`), and it stays second choice now
that class names in the table are acceptable.

### Spike results (executed on Rails 7.1.5.1 — all caveats resolved)

Decision: **Option 1**, associations named **`account`** and
**`offsetting_account`** (financial-English convention, matching the
`*_number`/`*_type` columns they sit next to).

The open questions were answered with a throwaway spike (one transaction:
`ALTER TABLE … ADD COLUMN … GENERATED`, associations via `class_eval`, tests,
`ROLLBACK`; scratchpad `poly_spike.rb`). All 13 checks passed:

- `booking.account` → `WsjrdpLedgerAccount`, `booking.offsetting_account` →
  `WsjrdpPersonalAccount` for creditor legs (data fact: creditor legs only occur on
  the Gegenkonto side in our bookings).
- **Name collision defused**: the association is named `account` while a
  column `account_type` (the DATEV Kontenart) already exists — the explicit
  `foreign_type: :account_ref_type` fully overrides the `#{name}_type`
  convention; `booking.account_type` still returns the Kontenart, and
  generated SQL touches only `account_ref_type`.
- `where(offsetting_account: supplier)` compiles to
  `offsetting_account_ref_type = 'WsjrdpPersonalAccount' AND
  offsetting_account_number = '…'` and matches the direct count; same for
  ledger accounts.
- `includes(:account, :offsetting_account)` over 100 mixed rows: **3 queries
  total**, zero queries on access (no N+1), every row resolved to the correct
  class.
- `joins(:account)` and `eager_load(:account)` raise
  `ActiveRecord::EagerLoadPolymorphicError` (by design); SQL that needs the
  join keeps using the explicit two-column form (as the filter's
  `any_account` does).
- Inverse side (`has_many` on the targets) needs explicit
  `foreign_key`/`primary_key` plus a type-scoped condition — add only when a
  concrete screen needs it.

### Option B — paired associations + dispatch (recommended first step, no migration)

```ruby
class DatevBooking < ActiveRecord::Base
  belongs_to :konto_ledger_account, class_name: "WsjrdpLedgerAccount",
    foreign_key: :account_number, primary_key: :number, optional: true
  belongs_to :konto_supplier, class_name: "WsjrdpPersonalAccount",
    foreign_key: :account_number, primary_key: :number, optional: true
  belongs_to :gegenkonto_ledger_account, class_name: "WsjrdpLedgerAccount",
    foreign_key: :offsetting_account_number, primary_key: :number, optional: true
  belongs_to :gegenkonto_supplier, class_name: "WsjrdpPersonalAccount",
    foreign_key: :offsetting_account_number, primary_key: :number, optional: true

  # Dispatch on the Kontenart -- NOT on "which table has the number" (27
  # numbers exist in both; CREDITOR must win the supplier).
  def konto
    (account_type == "CREDITOR") ? (konto_supplier || konto_ledger_account) : konto_ledger_account
  end

  def gegenkonto
    (offsetting_account_type == "CREDITOR") ? (gegenkonto_supplier || gegenkonto_ledger_account) : gegenkonto_ledger_account
  end
end
```

- Zero schema change; works today. Eager loading:
  `includes(:konto_ledger_account, :konto_supplier, …)` — both sides preloaded,
  the helper picks; the reference tables are tiny, so the double preload is
  cheap.
- Honest limitation: `konto` is a method, not an association — no
  `joins(:konto)`, no `where(konto: …)`.

### Option C — one real polymorphic association per side (needs a small migration)

Add **stored generated** discriminator columns (same pattern as
`amount`/`offsetting_amount`, so they can never drift):

```ruby
t.virtual :account_ref_type, type: :string, stored: true,
  as: "CASE WHEN account_type = 'CREDITOR' THEN 'supplier' ELSE 'ledger_account' END"
t.virtual :offsetting_account_ref_type, type: :string, stored: true,
  as: "CASE WHEN offsetting_account_type = 'CREDITOR' THEN 'supplier' ELSE 'ledger_account' END"
```

Give both target models stable polymorphic names (no class names in the DB):

```ruby
class WsjrdpPersonalAccount      < ActiveRecord::Base; def self.polymorphic_name = "supplier"; end
class WsjrdpLedgerAccount < ActiveRecord::Base; def self.polymorphic_name = "ledger_account"; end
```

Then a single association per side:

```ruby
belongs_to :konto, polymorphic: true, optional: true,
  foreign_key: :account_number, foreign_type: :account_ref_type, primary_key: :number
belongs_to :gegenkonto, polymorphic: true, optional: true,
  foreign_key: :offsetting_account_number, foreign_type: :offsetting_account_ref_type, primary_key: :number
```

- One association, `includes(:konto)` groups by type and preloads each target
  with `primary_key: :number` (both targets share the column — the uniform
  `primary_key` option is exactly the supported case).
- **Needs a spike** before committing: polymorphic `belongs_to` with a custom
  `primary_key` is less-travelled Rails territory (eager loading + `where`
  behaviour should be verified on our Rails version).
- Still no DB-level FK (polymorphic associations never have one).

### Option D — union view directory (not recommended now)

A DB view `UNION ALL` over both tables + one model on top. Single uniform
"account directory", but adds view management to the wagon (schema-dump
friction) for little gain while B/C suffice.

### Recommendation & flanking measures

1. Start with **Option B** (pure model code, reversible), migrate to **C** if
   single-association ergonomics (`joins`/`includes(:konto)`) prove wanted.
2. Add the three **indexes** on `datev_bookings(account_number)`,
   `(offsetting_account_number)`, `(cost_center_number)` — needed for the
   associations *and* today's summaries.
3. Add an import-time / boot-time **consistency check**: every booking number
   with type CREDITOR has a suppliers row; every non-CREDITOR number has a
   ledger row (both currently hold: 0 unknown numbers).
4. Keep supplier names **only** in `wsjrdp_personal_accounts` (don't backfill the
   nameless chart stubs — one source of truth; display code dispatches like
   the filter options now do).
5. An analogous pair `belongs_to :cost_center / :secondary_cost_center`
   (single-target, `primary_key: :number`) falls out for free and needs no
   polymorphism.
