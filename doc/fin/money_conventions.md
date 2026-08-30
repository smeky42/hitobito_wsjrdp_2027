# Money & currency conventions (house standard)

How monetary amounts, signs, currencies and exchange rates are
represented across the finance tables. This is the single source for
these rules.


## The two layers

Import tables mirror an external system. To reconcile source fidelity
with uniformity, every money-bearing table has two kinds of columns:

* **Source-mirror columns** keep source-faithful names (Moss
  field-reference names like `original_amount`, `conversion_rate`;
  DATEV terms like `document_field_1`). They may differ between tables
  because they describe the *source*.
* **House columns** are our derived, comparable figures — the EUR
  anchor, signedness, exchange rate, account classification. Only this
  layer is normalized, and cross-table reconciliation uses only this
  layer.


## The rules

**R1 — currency axes.** `base_*` = amount/currency in our ledger
currency (EUR — enforced by check constraints and refused by the
importers otherwise); `transaction_*` = as transacted. Moss vocabulary
maps as *Home* ≙ base, *Original* ≙ transaction.

**R2 — sign follows the table's nature.**

* *Journal tables* (double-sided; `datev_bookings`) store amounts
  **unsigned** plus a `debit_credit` indicator (`D`/`C`, from DATEV
  S/H) — the SAP/DATEV/ISO 20022 convention. This is not just
  tradition: a journal row has no single sign, it has two perspectives
  (account/offsetting account) plus the P&L flip.
* *Account-perspective tables* (single-sided; the Moss tables,
  `wsjrdp_camt_transactions`) store **signed** amounts, convention
  **`+` = inflow to our account** (a card purchase is negative).
* A `signed_`/unsigned marker appears only where both representations
  of the same figure coexist in one table: then the unsigned input is
  unmarked and every signed view carries the `signed_` prefix.

**R3 — signed views name their perspective.** Generated columns follow
`signed_[offsetting_]<axis>_amount`. In `datev_bookings` the full 2×3
matrix is: `base_amount` / `transaction_amount` (unsigned inputs) →
`signed_base_amount`, `signed_offsetting_base_amount`,
`signed_transaction_amount`, `signed_offsetting_transaction_amount`
(generated; sign from `debit_credit` and the P&L flip via the account
types).  `SUM(signed_base_amount)` is always EUR.

**R4 — one exchange-rate concept.** `exchange_rate numeric(28, 12)`,
with the direction fixed as **`transaction = base × exchange_rate`** —
the rate counts **transaction-currency units per one unit of the base
currency** (EUR→PLN ≈ 4.24, i.e. 1 EUR = 4.24 PLN).

That is the German *Mengennotierung* (quantity notation), standard in
German accounting since the euro was introduced and what DATEV asks
for ("always state the rate in relation to the euro"); the ECB quotes
the same way (pair EUR/PLN, EUR being the unit). Verified against the
real DTVF data: the stored DATEV Kurs equals `transaction_amount /
base_amount` on every foreign-currency row.

Beware two traps. First, `EUR/PLN` is *pair* notation, not a division —
reading the slash as "divided by" yields the reciprocal. Second, our
`base_currency` means the **ledger** currency (EUR, check-constrained),
whereas "base currency" in FX means the first currency of the pair;
they coincide here only because our ledger currency is the quoted unit.
Because a bare formula invites exactly these mistakes, every
`exchange_rate` column comment states the direction **with a concrete
example**.

Importers never invent the rate: DATEV delivers it (record field 4)
and is stored unchanged; where a source has no usable rate, the
importer derives it as `|transaction| / |base|`.

**R5 — one account classification.** Wherever account numbers are
stored, the closed `account_kind` set (BANK, TRANSIT, CLEARING,
LIABILITY, CREDITOR, DEBITOR, INCOME, EXPENSE, EQUITY, UNKNOWN —
check-constrained) applies. The `account_type` /
`offsetting_account_type` columns hold the polymorphic target class
(`WsjrdpLedgerAccount` / `WsjrdpPersonalAccount`), derived from
`account_kind`; the second side of a booking always uses the
`offsetting_` prefix.


## Generalumkehr (GU) in DATEV and signs — verified

`is_general_reversal` marks DATEV Generalumkehr rows. The DTVF export
delivers GU rows **already side-flipped** (the GU row carries the
opposite S/H of the booking it reverses), so the generated signed
columns cancel the reversed booking without any extra factor —
verified on the real data: each GU row pairs with its original row
(same accounts, same unsigned amount, opposite `debit_credit`), and
the pair sums to zero. Do **not** add a `CASE WHEN is_general_reversal
THEN -1` factor to the sign expressions; it would double instead of
cancel. The flag is informational (make reversals visible/filterable).


## The table landscape

| Table | Amount type | Signs | Direction field | Currency axes | Rate |
|---|---|---|---|---|---|
| `datev_bookings` | numeric(20,3) | unsigned inputs + 4 generated signed views | `debit_credit` D/C | `base_*` / `transaction_*` | `exchange_rate` (28,12), reliable |
| `datev_booking_batches` | — | — | — | `base_currency` (= EUR, checked) | — |
| `moss_card_transactions` / `_bookings` | numeric(20,3) | signed inputs + generated unsigned views | `debit_credit` D/C (generated from the sign) | `base_*` / `transaction_*` on the lines | `exchange_rate` (28,12), derived |
| `moss_balance_movements` | numeric(20,3) | signed (− = charge) | none | `currency` (= account EUR) / `original_*` | `conversion_rate` (20,8): **junk (1.0) on FX rows** |
| `wsjrdp_camt_transactions` | integer cents | signed | additionally `credit_debit_indication` CRDT/DBIT (ISO source mirror; redundant with the sign, deliberately) | EUR only | — |

Not to be touched: `wsjrdp_camt_transactions` (ISO 20022 source
mirror) and `accounting_entries` (`amount_cents`, hitobito heritage)
keep their dialects; this document only maps them.


## Status / plans

* `datev_bookings` / `datev_booking_batches` follow this standard
  (Tier 1).
* Moss card transaction tables follow this standard as well (Tier 2):
  the signed amount is the input and the unsigned one is generated --
  the mirror image of `datev_bookings`, because they are
  account-perspective tables (R2).
* `moss_balance_movements` (in production) - yet to be cleaned up.


## Money conventions (database)

This section describes how monetary amounts and exchange rates are
modelled in the database for `hitobito_wsjrdp_2027`. This applies to
new finance/bookkeeping tables (`datev_*`, `moss_*`,
`wsjrdp_cost_centers`/`wsjrdp_spheres` budgets, ...). The older
integer-cents idiom (`accounting_entries.amount_cents` & co.) is a
coexisting pattern that stays as it is for now.

### The two column types

* **Currency amounts: `numeric(20, 3)`** — up to 17 integer digits and
  3 fractional digits. Scale 3 covers every ISO 4217 currency (minor
  units are 0–3 decimals — most currencies 2, e.g. JPY 0, BHD/KWD/OMR 3)
  and leaves one guard digit beyond EUR cents.
* **Exchange rates: `numeric(28, 12)`** — up to 16 integer digits and
  12 fractional digits. Rates are not amounts: sources quote them with
  6 (DATEV Kurs), 8 (Moss conversion rates) or up to 10 fractional
  digits (ISO 20022 `BaseOneRate`: totalDigits 11 / fractionDigits
  10), so scale 12 is a superset of everything we may have to store
  losslessly. 16 integer digits cover every exchange rate ever quoted
  for a traded currency — including the historical extremes
  (Papiermark 1923: ~4.2 × 10¹² per USD; Zimbabwe dollar 2008/09:
  ~10¹³). Sole exception: The 1946 Hungarian pengő (~4 × 10²⁹), a
  magnitude no messaging standard can carry either.
* **Never `float`/`double precision`** for money or rates (see below).

### Why these shapes: how `numeric` storage works

PostgreSQL stores `numeric` values by VALUE, not by declared type: the
docs state the requirement as “two bytes for each group of four
decimal digits, plus three to eight bytes overhead”. In a heap tuple
that is

    1 byte varlena header + 2 bytes numeric header
    + 2 bytes per group of four decimal digits,

where the four-digit groups are aligned at the decimal point and
counted separately for the integer and the fractional side; leading
and trailing all-zero groups are not stored at all. The declared
`precision` is never stored — it is only an input constraint — so the
*maximum* size of a column is

    max bytes = 3 + 2 * ( ceil((p - s) / 4) + ceil(s / 4) )

* `numeric(20, 3)`: ⌈17/4⌉ + ⌈3/4⌉ = 6 groups → **max 15 bytes**
* `numeric(28, 12)`: ⌈16/4⌉ + ⌈12/4⌉ = 7 groups → **max 17 bytes**

Both scales sit at four-digit group boundaries, so they waste nothing:
scale 3 costs the same as scale 4 would, scale 12 fills its three
fraction groups exactly, and 13–16 integer digits all cost the same
four groups.

In practice the footprint is much smaller and *variable*: a typical
Euro amount takes 5–9 bytes (measured over the imported some DATEV
bookings: ~79 % of rows at 5 bytes, ~21 % at 7, a handful at 9), zero
takes 3 bytes, and NULL only the row's null-bitmap bit — i.e. usually
**less than a fixed 8-byte `bigint` of cents**. The trade-off is
arithmetic speed: `numeric` math is implemented in software, integer
math in hardware; at our data volumes that is irrelevant.

### What others do

* The [PostgreSQL docs](https://www.postgresql.org/docs/current/datatype-numeric.html)
  explicitly recommend `numeric` “for storing monetary amounts and other
  quantities where exactness is required”.
* The integer-minor-units pattern (store cents in an integer; Stripe’s
  API model) is the main alternative — that is exactly what
  `accounting_entries.amount_cents` does. See [Storing currency
  values: data types, caveats, best
  practices](https://cardinalby.github.io/blog/post/best-practices/storing-currency-values-data-types/)
  for a survey of both patterns and the ISO 4217 minor-unit pitfalls.
* Microsoft [recommends `decimal` with at least four decimal places
  over the legacy `money(19,4)` type](https://learn.microsoft.com/en-us/sql/t-sql/data-types/money-and-smallmoney-transact-sql)
  — the classic accounting shape `numeric(19,4)` that our `(20,3)`
  is a close relative of.
* For rates, ISO 20022 defines
  [`BaseOneRate`](https://javadoc.io/static/com.tools20022/tools20022-api-payments/0.1.1/com/tools20022/repository/datatype/BaseOneRate.html)
  with totalDigits 11 / fractionDigits 10 (used e.g. by the camt
  `XchgRate` element); XML-Schema digit limits are not fixed SQL
  scales, which is why our column is a strict superset.

### Language mappings: why this is exact (and float is not)

* **Ruby / Rails** maps `numeric` to
  [`BigDecimal`](https://docs.ruby-lang.org/en/master/BigDecimal.html);
* **Python / psycopg** maps it to
  [`decimal.Decimal`](https://docs.python.org/3/library/decimal.html).

Both are arbitrary-precision *decimal* representations: `0.10` is
stored exactly, and addition, subtraction and multiplication are exact
— the same guarantee PostgreSQL gives for `numeric`. Sums, comparisons
and round-trips therefore match the database bit for bit.

IEEE-754 `float`/`double` cannot represent most decimal fractions:
`0.1 + 0.2 == 0.30000000000000004`, and accumulating thousands of such
values drifts by real cents. That is why values must stay
`BigDecimal`/`Decimal` end to end — never parse an amount into a float
“just briefly”, and format for display via helpers, not via float
conversion. Division and currency conversion still need an explicit
rounding decision (target scale + rounding mode) even with decimals;
exactness only comes for free for +, −, ×.
