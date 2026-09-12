# Sub cost centers (Unterkostenstellen)

A **sub cost center** refines a cost center inside Hitobito, below the
granularity DATEV and Moss know about. The two tables differ in ownership:

* [`wsjrdp_cost_centers`](../../db/migrate/20260822000100_add_wsjrdp_cost_centers_and_spheres.rb)
  is master data synced with both external systems — its `number` is DATEV's
  KOST field and Moss's cost center, and an import keeps the rows in step.
* [`wsjrdp_sub_cost_centers`](../../db/migrate/20260912110000_add_wsjrdp_sub_cost_centers.rb)
  is Hitobito-owned and exists only here; neither DATEV nor Moss has a
  counterpart, so nothing outside Hitobito creates, renames or removes one.
  Model: [`WsjrdpSubCostCenter`](../../app/models/wsjrdp_sub_cost_center.rb),
  hanging off [`WsjrdpCostCenter`](../../app/models/wsjrdp_cost_center.rb).


## The table

One row is one sub cost center. The columns in the order and the groups the
migration uses — the link, the identity and names, the flags, the budgets, the
free text, the reserved JSONB:

| Column | Type | Holds |
|---|---|---|
| `created_at` / `updated_at` | `datetime` | Row timestamps; `created_at` defaults to `CURRENT_TIMESTAMP` and is `NOT NULL`, `updated_at` is nullable. |
| `cost_center_number` | `string`, `NOT NULL` | The cost center this sub cost center belongs to — its `wsjrdp_cost_centers.number`, not an id. |
| `number` | `string`, `NOT NULL` | The sub cost center number, unique within its cost center. |
| `name` | `string` | Full designation. |
| `short_name` | `string` | Short designation. |
| `aliases` | `text[]`, default `[]`, `NOT NULL` | Hitobito-specific alternative names. |
| `display_short_name` | `string`, generated, stored | `short_name`, falling back to `name`, then `''`. The one place defining how a short display name is derived. |
| `delete_without_finance_permission` | `boolean`, default `true`, `NOT NULL` | Whether the row may be deleted without a finance permission. |
| `visibility` | `string`, default `auto`, `NOT NULL` | Hitobito-specific: `auto`, `visible` (always visible) or `hidden` (never visible). |
| `budget_2025` … `budget_2028` | `decimal(20,3)` | One signed budget per year, expenses negative; `NULL` = not set. |
| `explicit_total_budget` | `decimal(20,3)` | An explicitly set total budget for the whole period; `NULL` = not set. |
| `effective_total_budget` | `decimal(20,3)`, generated, stored | The displayed total: the yearly sum or `explicit_total_budget`, whichever is larger in absolute value. Not writable. |
| `description` / `comment` | `text`, default `''`, `NOT NULL` | Free text. |
| `user_comment` | `text`, default `''`, `NOT NULL` | Free text, visible for users. |
| `additional_info` | `jsonb`, default `{}`, `NOT NULL` | Reserved for future use. |

Both generated columns are Postgres **stored** generated columns
(`t.virtual … stored: true`): the database computes them on write, no code can
assign them. `display_short_name` is
`COALESCE(NULLIF(short_name, ''), NULLIF(name, ''), '')` — the short name if
set and non-empty, else the name, else the empty string, never `NULL`.

```sql
CASE
  WHEN coalesce(budget_2025, budget_2026, budget_2027, budget_2028) IS NULL
    THEN explicit_total_budget
  WHEN explicit_total_budget IS NULL
    OR abs(coalesce(budget_2025, 0) + coalesce(budget_2026, 0)
         + coalesce(budget_2027, 0) + coalesce(budget_2028, 0)) > abs(explicit_total_budget)
    THEN coalesce(budget_2025, 0) + coalesce(budget_2026, 0)
       + coalesce(budget_2027, 0) + coalesce(budget_2028, 0)
  ELSE explicit_total_budget
END
```

yields `effective_total_budget`: the sum of the yearly budgets or the
explicitly set total, whichever has the **larger absolute value** — budgets are
signed with expenses negative (see
[money_conventions.md](money_conventions.md)), so a numeric `MAX` would pick
the *smaller* envelope of two expense budgets. With all four years `NULL` the
result is `explicit_total_budget`. The identical expression sits on
`wsjrdp_cost_centers`; each migration carries its own copy because migrations
stay self-contained. These budget columns, `effective_total_budget` included,
are the ones
[`WsjrdpBudgetable`](../../app/models/concerns/wsjrdp_budgetable.rb) describes,
shared with `WsjrdpCostCenter` and `WsjrdpSphere`.


## Keys and constraints

* The one unique index is `index_wsjrdp_sub_cost_centers_on_cost_center_and_number`
  on `(cost_center_number, number)`. A number is therefore unique **within its
  cost center**, and the same number may appear again under another cost
  center.
* There is deliberately **no foreign key** on `cost_center_number`. The link is
  by number, the way the Moss and DATEV tables link to accounts.


## The model

[`WsjrdpSubCostCenter`](../../app/models/wsjrdp_sub_cost_center.rb) includes
`WsjrdpBudgetable` and is otherwise small:

* `belongs_to :cost_center, class_name: "WsjrdpCostCenter", optional: true,
  foreign_key: :cost_center_number, primary_key: :number, inverse_of:
  :sub_cost_centers` — both keys are spelled out because neither matches what
  Rails would derive from the association name.
* `validates :number, presence: true, uniqueness: {scope: :cost_center_number}`
  mirrors the unique index.
* `to_s` is `"#{number} #{display_short_name}"`.

On the other side, `WsjrdpCostCenter` has
`has_many :sub_cost_centers, -> { order(:number) }` with the same key pair and
**no `:dependent` option**, guarded by a
`rubocop:disable Rails/HasManyOrHasOneDependent` comment. That combination is
the point of the design: **a sub cost center outlives the cost center it
names.** Deleting a cost center leaves its sub cost centers alone — they keep
their `cost_center_number`, nothing is destroyed behind the user's back, and
the association resolves again by itself once a cost center with that number is
imported again. Cost centers are master data synced from DATEV and Moss, so
their disappearance is an import artifact, not a decision to discard the
Hitobito-owned refinement below them. `optional: true` says the same at the
record level, and is spelled out even though
`config.active_record.belongs_to_required_by_default = false` (core
`config/application.rb`) makes a bare `belongs_to` optional anyway — the
explicit option states the intent instead of inheriting it.


## A booking's sub cost center

[`datev_bookings.sub_cost_center_number`](../../db/migrate/20260912120000_link_datev_bookings_to_sub_cost_centers.rb)
carries the sub cost center a booking is assigned to. It is
Hitobito-owned, not a DATEV field, and it is **one half of the link**:
a sub cost center number is unique within its cost center only, so the
pair `(cost_center_number, sub_cost_center_number)` on the booking
names the row `(cost_center_number, number)` in
`wsjrdp_sub_cost_centers`. The index
`index_datev_bookings_on_cost_center_and_sub_cost_center` serves the
lookup from the sub cost center side.

There is no foreign key on that pair, and no validation: the select is
what narrows the choice. It is allowed to have a
combination of `cost_center_number` and `sub_cost_center_number` not
appearing in `wsjrdp_sub_cost_centers`.  That state is legal — the
association reads as `nil`, the raw number stays, and the booking
still saves when any other field changes. It is shown, not hidden: the
detail view renders the raw number with an `(unbekannt)` marker, and
the select offers the value back instead of dropping it.

Both sides use an instance-dependent scope that adds the cost center half:

* [`DatevBooking`](../../app/models/datev_booking.rb):
  `belongs_to :sub_cost_center, ->(booking) { where(cost_center_number:
  booking.cost_center_number) }, class_name: "WsjrdpSubCostCenter",
  foreign_key: :sub_cost_center_number, primary_key: :number, optional: true`.
* `WsjrdpSubCostCenter`: `has_many :datev_bookings, ->(sub) {
  where(cost_center_number: sub.cost_center_number) }` with the same
  key pair, `inverse_of: false` and **no `:dependent` option**
  (guarded by a `rubocop:disable Rails/HasManyOrHasOneDependent`
  comment) — bookings are independent facts, deleting a sub cost
  center must never touch them. A booking of another cost center
  carrying the same number is not listed.

An instance-dependent scope preloads but can never be eager-loaded or
joined (`ArgumentError: The association scope ... is instance
dependent`). Use `preload` / `includes`; a join is written out in SQL
over both numbers:

```sql
LEFT JOIN wsjrdp_sub_cost_centers scc
       ON scc.cost_center_number = datev_bookings.cost_center_number
      AND scc.number = datev_bookings.sub_cost_center_number
```

Both ready-made forms of that join live on the models.
[`DatevBooking.with_sub_cost_center`](../../app/models/datev_booking.rb)
puts it into a derived table aliased back to `datev_bookings` and adds
`sub_cost_center_name` and `sub_cost_center_short_name` as real
columns, `NULL` where the pair does not resolve — unlike the
association they can be sorted and filtered
on. [`WsjrdpSubCostCenter.with_booking_summary`](../../app/models/wsjrdp_sub_cost_center.rb)
is the same shape from the other side, grouped over both numbers, so
each sub cost center carries `booking_sum` and `booking_count`.

In the booking detail the field is a select next to the secondary cost
center (`Fin::BookingsHelper#fin_sub_cost_center_select_options`):
"nicht gesetzt" plus the sub cost centers of the booking's own cost
center, labelled by the model's `to_s`, plus the current value when it
does not resolve.


## Naming

DATEV's Kostenrechnung master data knows **Haupt- und Unterkostenstellen** and
arranges cost centers in **Kostenstellen-Hierarchien** built from
Hierarchieelementen ([DATEV Hilfe-Center 9212724](https://help-center.apps.datev.de/documents/9212724),
[DATEV Wissensplattform 9216091](https://wissensplattform.apps.datev.de/help/document/9216091));
in DATEV bookkeeping the fields are KOST1 (Kostenstelle) and KOST2
(Kostenträger). SAP calls a cost center hierarchy a **cost center group**, where
the upper levels are groups or nodes and only the cost centers at the lowest
level carry postings
([SAP docs](https://help.sap.com/docs/SAP_S4HANA_CLOUD/1e3c2c0366834d1fb76461f439248880/076f8f570a33491c98f8fc20d71b44f7.html)).
QuickBooks Online builds the same shape from **classes and subclasses**
("Subclass of",
[QuickBooks community](https://quickbooks.intuit.com/learn-support/en-us/other-questions/quickbooks-classes-and-subclasses/00/270012)).
Odoo keeps analytic accounts flat and adds groups for reporting only.
