# Unit-Budget

Whether a booking belongs to the budget of a **unit** — money a unit spends of
its own, as against the contingent's central bookkeeping. Nothing outside
Hitobito answers that question: neither DATEV nor Moss has a counterpart field,
so the flags below are Hitobito-owned and no import rewrites them.

The answer is never stored on the booking alone. A booking may carry an
explicit override, but the ordinary case is that its **cost center** and then
its two **accounts** decide, and the rule that combines them is written once
and read in three places.


## The rule

For one booking, in four steps:

1. the booking's own `datev_bookings.is_unit_budget`, whenever it is not
   `NULL`;
2. otherwise its **primary cost center** (`cost_center_number`, looked up by
   number in `wsjrdp_cost_centers`): where that cost center is known and is
   **not** a unit's own — `is_unit_cost_center` is `FALSE` — the answer is
   `false` and the accounts are not asked. A booking on the contingent's cost
   center is not a unit's spending, whatever it was booked on. A cost center
   that *is* a unit's own, one whose flag is `NULL`, and a number naming no
   cost center at all all leave the question open;
3. otherwise the flags of its two accounts — Konto (`account_number`) and
   Gegenkonto (`offsetting_account_number`), each looked up **by number** in
   `wsjrdp_ledger_accounts` or `wsjrdp_personal_accounts` — combined with
   **AND**: a `false` on either side wins. A number that names no account at
   all counts as unknown, and the other side decides alone;
4. otherwise `true`.

The **source** of the answer travels with it, so a page can say where the value
came from:

| Source | Meaning |
|---|---|
| `booking` | the booking carries the flag itself; nothing else was asked |
| `cost_center` | the primary cost center is not a unit's own; step 2 |
| `konten` | both accounts are known and together give the answer |
| `konto` | the Konto decided — it said `false` while the Gegenkonto said `true`, or it was the only known side |
| `gegenkonto` | the Gegenkonto decided, the same way |
| `default` | no number named an account; step 4 |

In SQL the rule is one `COALESCE` chain with the matching `CASE` for the source
([`DatevBooking`](../../app/models/datev_booking.rb)):

```sql
COALESCE(datev_bookings.is_unit_budget,
         CASE WHEN ub_kostenstelle.is_unit_cost_center = FALSE THEN FALSE END,
         ub_konto.is_unit_budget AND ub_gegenkonto.is_unit_budget,
         ub_konto.is_unit_budget,
         ub_gegenkonto.is_unit_budget,
         TRUE)
```

The cost-center step is a `CASE` without an `ELSE` on purpose: it yields
`FALSE` where the cost center says no and `NULL` everywhere else — including
where the flag itself is `NULL`, since `NULL = FALSE` is `NULL` — so `COALESCE`
walks on to the accounts in exactly the cases step 2 leaves open.

The chain ends in `TRUE`, so the value is never `NULL`: `nicht ja` and `nein`
are the same set, and the field is never blank on a page.


## The columns

| Table | Column | Shape |
|---|---|---|
| `datev_bookings` | `is_unit_budget` | `boolean`, nullable — the override; `NULL` means "let the accounts decide" |
| `wsjrdp_ledger_accounts` | `is_unit_budget` | `boolean`, default `true`, `NOT NULL` |
| `wsjrdp_personal_accounts` | `is_unit_budget` | `boolean`, default `true`, `NOT NULL` |
| `wsjrdp_cost_centers` | `is_unit_cost_center` | `boolean`, default `false`, nullable — this cost center is a unit's own |

`is_unit_cost_center` does two things: it decides step 2 of the rule, and it
says **whose** budget a cost center holds — the tiles below measure against the
sum of the unit cost centers' `effective_total_budget`. It is nullable with
`false` as its default, so an unanswered cost center reads `nein` on a page. In
the rule the two are not the same, though: `FALSE` settles the question,
`NULL` leaves it to the accounts.

### The migration's two data steps

The same migration seeds both the flag and the group assignment from what the
names already say. Both statements are idempotent — the finance team reruns
them by hand after new units have been created, and a database somebody
curated by hand is not touched:

```sql
-- a) a unit's cost center is numbered like the unit ("X1"); its NAME is the
--    prose form ("Unit X1"), so the NUMBER is what carries the pattern.
UPDATE wsjrdp_cost_centers
   SET is_unit_cost_center = TRUE
 WHERE number ~ '^[A-Z][0-9]+$';

-- b) every unit group whose WHOLE name is such a number gets the same-named
--    cost center appended -- only where it exists and is not listed yet.
UPDATE groups g
   SET additional_info = jsonb_set(COALESCE(g.additional_info, '{}'::jsonb),
                                   '{cost_center_numbers}',
                                   COALESCE(g.additional_info->'cost_center_numbers', '[]'::jsonb) || to_jsonb(g.name),
                                   true)
  FROM wsjrdp_cost_centers c
 WHERE g.type = 'Group::Unit'
   AND g.deleted_at IS NULL
   AND g.name ~ '^[A-Z][0-9]+$'
   AND c.number = g.name
   AND NOT (COALESCE(g.additional_info->'cost_center_numbers', '[]'::jsonb) ? g.name);
```

The `?` is the jsonb "has key" operator. Rails' `execute` sends a statement
verbatim, without parameter substitution, so it needs no escaping there.

The migration's `down` undoes nothing of this beyond dropping the column: the
cost-center flags go with the column, and a group's `cost_center_numbers` entry
is master data a human may have set as well — there is no way to tell the two
apart afterwards, so it stays.

Sachkonten and Personenkonten use **disjoint** number ranges (the
`chk_ledger_account_number_not_personal_account` and
`chk_personal_account_number_six_digits` constraints enforce it), so one union
of the two tables is an unambiguous `number -> flag` lookup, and a `LEFT JOIN`
over it can never multiply a booking row.


## One definition, three readers

`DatevBooking` keeps the rule as SQL fragments under fixed join aliases
(`ub_kostenstelle`, `ub_konto`, `ub_gegenkonto`) and every reader takes the same
expression:

* **the rows** — `DatevBooking.with_unit_budget` selects it as
  `effective_is_unit_budget` and the source as `is_unit_budget_source`;
* **the filter** — the `unit_budget` attribute of
  [`Fin::DatevBookingsFilterSchema`](../../app/domain/fin/datev_bookings_filter_schema.rb)
  compiles against the expression itself, because PostgreSQL cannot see a
  SELECT alias in a `WHERE`;
* **the sort** — the `unit_budget` column of
  [`Fin::DatevBookingsColumns`](../../app/domain/fin/datev_bookings_columns.rb)
  orders by the same expression, so a sorted table and its cells cannot
  disagree.

`with_unit_budget` is a `select` plus three joins, **not** a derived table:
`DatevBooking.legs` already is a derived table aliased back to `datev_bookings`,
and the account detail pages list their bookings through it, so a second `from`
would replace it. A select and a join compose with `legs`, with
`with_sub_cost_center` and with the filter schema's base relation, which merges
its own joins into whatever relation a host hands in. The joins alone are
`DatevBooking.with_unit_budget_accounts`; that is what the filter schema binds
to, so a page can filter and sort by the rule without selecting the columns.

A relation carrying the two columns is counted with `count(:all)` — which is
what Kaminari does — never with a bare `#count`, which would fold the whole
select list into one `COUNT()`.

For a single booking loaded without those columns — the detail page —
`DatevBooking#unit_budget` computes the same rule in Ruby and returns
`[value, source]`; a row that carries the columns is answered from them, so a
table page costs no query per row. `DatevBooking#automatic_unit_budget` gives
what the **cost center and the accounts** say between them, ignoring the
override; it walks the same order as the SQL.

`wsjrdp_cost_centers.number` is unique, so the cost-center join cannot multiply
a booking row either.


## On the pages

**The bookings table** has a `unit_budget` column ("Unit-Budget?", wire token
`ub`). Its cell reads `ja` / `nein`, with the source muted beside it —
`Kostenstelle 9500`, `Konto 66500`, `Gegenkonto 1200`, `Standard` or
`Buchung`. The `konten` source
carries **no** label: two accounts that simply agree are the ordinary case, and
naming both numbers would be the longest text on the page for the answer that
says the least, so the cell shows the bare `ja` / `nein` and the detail stops
at `automatisch`. The condensed variant embedded in a Buchhaltung detail shows
the bare answer throughout. On `/fin` the column is offered in the column menu;
on a group's Buchhaltung tab it is one of the default columns, right behind the
amount.

**The summary line** above the full table states the share of its sum that
counts against a unit's budget: `N Buchungen · Summe (gefiltert): X € · davon
Unit-Budget: Y € (M Buchungen)`. The share and the sum are two readings of the
**same** filtered relation — `Wsjrdp::ExpandableTableRows#subtotal` applies the
expression above to it, and `Fin::BookingsHelper#booking_table_summary` words
the line — so a filter moves both together and the share can never belong to
another set. Every host of the full table hands the rows
`DatevBooking.with_unit_budget`, which is what carries the account joins the
expression names: `/fin/bookkeeping/bookings`, a group's Buchhaltung tab and the
reconciliation page. The condensed table inside a Buchhaltung detail carries no
summary at all.

**The filter** offers "Unit-Budget?" in the Kostenrechnung group with `ist` /
`ist nicht` over `ja` and `nein`. The filter vocabulary has no boolean type, so
it is a REFERENCE with two options — the same shape every other yes/no
attribute takes.

**The Schnellauswahl** of a group's Buchhaltung tab carries one preset,
"Unit-Budget" (`Group::BookkeepingController::PRESETS`): one click adds the user
slot `unit_budget in (true)` and the list shows what counts against the unit's
own budget, a second click takes it away. It is a shortcut *into* the user
filter, not a pin — the slot it adds becomes an ordinary chip the builder can
edit or drop (`doc/wsjrdp/expandable_table.md`, "Presets").

**The tiles** on a group's Buchhaltung tab state four figures over the group's
**pinned** set — every booking whose primary or secondary cost center is one of
the group's, whatever the user's filter says
([`Fin::GroupBookkeepingFigures`](../../app/domain/fin/group_bookkeeping_figures.rb)).
They talk of expenses as POSITIVE figures: the signed booking sums with their
sign turned (`expenses_total`, `expenses_unit_budget`); the budget is positive
as it is stored:

| Tile | Figure |
|---|---|
| Ausgaben Gesamt | `-SUM(signed_base_amount)` over the pinned set |
| Ausgaben Unit-Budget | the same over the subset the rule above calls `true` |
| Unit-Budget | the Budget (below); "—" with a hint where there is none |
| Unit-Budget Verbraucht | `Ausgaben Unit-Budget / Budget`, in percent; "—" where there is no budget |

The **Budget** is the sum of `effective_total_budget` over the group's cost
centers that are marked `is_unit_cost_center`; a cost center of the group that
is not a unit's own carries the contingent's money and stays out. Budgets are
**expense budgets and stored positive** on all three budget tables
(`wsjrdp_cost_centers`, `wsjrdp_sub_cost_centers`, `wsjrdp_spheres`,
`WsjrdpBudgetable`), while a booking's signed amount has expenses negative —
so the share is taken over the expenses, and a spending unit's share is
positive. Without such a budget — none set, or a total of zero — the tile
reads `—` and says `kein Unit-Budget hinterlegt` rather than printing a figure
it cannot compute.

The tiles are deliberately independent of the filter: the table below answers
what the viewer is looking at, the tiles where the unit stands. The filtered
figures are the summary line's.

**The booking detail** always shows the field, value first and the origin in
parentheses: `ja (Buchung)` where the booking carries the flag,
`nein (automatisch, Kostenstelle 9500)` where the cost center settled it,
`nein (automatisch, Konto 66500)` where one account decided,
`ja (automatisch)` where both agreed. On the edit page it
is a select whose first option leaves the override unset and therefore names
the answer the accounts currently give — `automatisch (ja)` or
`automatisch (nein)`. A group may read the field but not change it; on its edit
page the text stands where the select would be.

**The Kostenstellen page** carries `is_unit_cost_center` beside the budgets of
a cost center's detail — it says whose budget they are — as a `ja` / `nein`
select for whoever may update the cost center, permitted by
`Fin::CostCentersController#update`. The list offers it as the column
"Unit-Kostenstelle" (wire token `ukst`), not shown by default: few cost centers
carry it.

**The account pages** (Sachkonten, Kreditoren) carry the flag as an ordinary
field, `ja` / `nein`, and offer it as a column in their list menus. Editing it
follows the bookings' split: the reading page shows a "Bearbeiten" button for
the write tier, the edit page carries the select, the two submits and
"Abbrechen", and `#update` permits `is_unit_budget` and nothing else. A number
without master data is a stub record on the reading page and has no edit page.
