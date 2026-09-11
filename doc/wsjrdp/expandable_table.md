# The `expandable_table` widget — tutorial & guide

`shared/wsjrdp/_expandable_table` is the one shared table used across the Finanzen
area (the Buchungen list, the Moss transactions list, the Buchhaltung summaries
and both reconciliation tables). Every extra element — a filter, a summary line,
paging, a column hamburger, row selection, sortable headers, expandable per-row
detail — is an **optional** local that is **off by default**. A bare call renders
a plain table; you turn on exactly the features a page needs.

> **Note on the examples.** The kit itself is app-wide and has no dependency on
> the finance code — the `Thing…` example in §1 is complete and self-contained.
> The `Fin::…` classes and `fin/…` pages appear from §5 on as the real worked
> examples.

This guide starts with the smallest possible table, explains who owns the
table's state, then adds one feature at a time, documents the query-param
namespacing that lets several tables share one page, the detail-nesting context,
the two real consumers as worked examples, and finally the full local reference.

- Widget: `app/views/shared/wsjrdp/_expandable_table.html.haml`
- Builder facade: `app/domain/wsjrdp/expandable_table_builder.rb`
  (`Wsjrdp::ExpandableTableBuilder` — what `t.…` calls)
- Helper: `app/helpers/wsjrdp/expandable_table_helper.rb`
  (`wsjrdp_expandable_table`, the `et_*` URL builders)
- Resolved state: `app/domain/wsjrdp/table_state.rb` (`Wsjrdp::TableState`,
  incl. `TableState::Filter` and the `Resolver`)
- Declaration: `app/domain/wsjrdp/table_state_policy.rb` (`Wsjrdp::TableStatePolicy`)
- Stores: `app/domain/wsjrdp/table_state_store.rb` (the interface),
  `table_state_store/session.rb`, `table_state_store/cookie.rb`
- Controller concern: `app/controllers/concerns/wsjrdp/table_stateful.rb`
  (`wsjrdp_expandable_table_policy` / `wsjrdp_expandable_table_state` /
  `wsjrdp_apply_table_filter`)
- Column description: `app/domain/wsjrdp/expandable_table_columns.rb` +
  `expandable_table_column.rb` (`Wsjrdp::ExpandableTableColumns.define`,
  `Wsjrdp::ExpandableTableColumn`), one module per dataset under
  `app/domain/fin/*_columns.rb`
- Rows: `app/domain/wsjrdp/expandable_table_rows.rb`
  (`Wsjrdp::ExpandableTableRows` — order, page, count, sum)
- Filter schema protocol: `app/domain/wsjrdp/filtering/filter_schema.rb`
  (`Wsjrdp::Filtering::FilterSchema`), one module per dataset
  (`Fin::DatevBookingsFilterSchema`, `Fin::MossTransactionsFilterSchema`,
  `Fin::PersonalAccountsFilterSchema`)
- Preset slot equality: `app/domain/wsjrdp/filtering/slot_equality.rb`
  (`Wsjrdp::Filtering::SlotEquality`)
- Sort logic: `app/domain/wsjrdp/expandable_table_sort.rb` (RISON encode/decode)
- Detail nesting: `app/domain/wsjrdp/table_context.rb` (`Wsjrdp::TableContext`)
- Sub-partials: `_expandable_table_paging`, `_expandable_table_columns_form`,
  `_table_selection_js`, `_table_hamburger`, `_expandable_table_styles`,
  `_expandable_table_js`, `filtering/_builder`
- Specs: `spec/domain/wsjrdp/table_state_spec.rb`,
  `spec/domain/wsjrdp/expandable_table_columns_spec.rb`,
  `spec/domain/wsjrdp/expandable_table_rows_spec.rb`,
  `spec/domain/wsjrdp/expandable_table_builder_spec.rb`,
  `spec/domain/wsjrdp/expandable_table_sort_spec.rb`,
  `spec/domain/wsjrdp/expandable_table_state_guard_spec.rb` (the D8.4 guard),
  `spec/controllers/fin/table_policies_spec.rb` (every declared table resolves),
  `spec/controllers/fin/ledger_accounts_controller_spec.rb`,
  `spec/controllers/fin/personal_accounts_controller_spec.rb` (the presets) and
  `spec/controllers/fin/moss_transactions_controller_spec.rb`

The design record behind the state model is
`doc/plans/2026-09_expandable-table-state.md`; its decision ids (D1, D2a, …) are
referenced throughout this guide and in the code comments.

---

## 1. The smallest table

A table is written in **three parts**: its **columns** are described once, the
**controller** declares the table and builds its rows, the **view** renders them.

### 1a. The columns of the dataset

```ruby
# app/domain/thing_columns.rb
module ThingColumns
  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "thcol") do |c|
    c.column key: "name",  abbr: "nm",  label: "Name",  width: "16rem",
      sort: "things.name", default: true
    c.column key: "total", abbr: "sum", label: "Summe", numeric: true,
      width: "8rem", sort: "things.total_cents", default: true
    c.column key: "note",  abbr: "nt",  label: "Notiz"
  end

  def self.codec = COLUMNS.codec                       # key => abbr
  def self.default_keys = COLUMNS.default_keys         # the columns shown first
  def self.sort_expressions = COLUMNS.sort_expressions # key => ORDER BY
end
```

Everything a column *is* lives here: `key` (the long name used everywhere in
code), `abbr` (the short wire token in `?c=` / `?s=`), `label`,
`condensed_label`, `numeric` (right-align), `width` (for the fixed table
layout), `sort` (how it sorts — an SQL expression for a relation, a
`->(row){ comparable }` extractor for an array), `default` (shown before the
user picks any) and `css_class` (derived from `css_prefix:` unless given).
`Wsjrdp::ExpandableTableColumn` is the value object; the collection is
`Enumerable` and also answers `keys`, `fetch(key)`, `key?(key)` and `size`.

### 1b. The controller

```ruby
class ThingsController < ApplicationController
  include Wsjrdp::TableStateful

  helper_method :things

  THINGS_POLICY = wsjrdp_expandable_table_policy prefix: "",
    columns:  ThingColumns.codec,
    sort:     {default: [["name", "asc"]]},
    cols:     {default: ThingColumns.default_keys},
    per_page: {default: 50}

  # THE table: the resolved state + the source, ordered and paged.
  def things
    @things ||= Wsjrdp::ExpandableTableRows.new(
      wsjrdp_expandable_table_state(THINGS_POLICY), Thing.all,
      sort: ThingColumns.sort_expressions)
  end

  def index = things
end
```

### 1c. The view

```haml
- cells = {"name"  => ->(thing) { thing.name },
           "total" => ->(thing) { thing.total },
           "note"  => ->(thing) { thing.note }}
= wsjrdp_expandable_table do |t|
  - t.rows    things
  - t.columns ThingColumns::COLUMNS.map { |col| col.to_table_column(cell: cells.fetch(col.key)) }
  - t.row_key { |thing| thing.id }
  - t.detail_page { |thing| thing_path(thing) }
  - t.detail  { |thing| render "things/detail", thing: thing }
  - t.paging
```

That renders a table with a clickable row per record; clicking a row expands an
inline **detail** (Bootstrap collapse, several can be open at once). `row_key`
must be unique — it keys the detail's DOM id and the open-rows URL param.
Instead of an inline `detail:`, pass `t.detail_src { |thing| url }` to
**lazy-load** the detail into a turbo frame the first time the row opens (keeps
big lists fast — the Buchhaltung summaries do this).

**The frame id is the table's, not the detail's.** The widget names the frame
`wsjrdp_detail_frame_id(id_prefix, key)` → `bkframe-<id_prefix>-<key>`, and
`id_prefix` is the table's (`t.rows … id:`, defaulting to the policy prefix).
The **same** detail is loaded from tables with **different** prefixes — the
Buchungen list asks as `bkframe-bk-<id>`, the condensed bookings table inside a
Buchhaltung item detail as `bkframe-b-<id>` — so the answering view must **never
build the id itself**:

```haml
= wsjrdp_detail_frame("bk", @booking.id) do
  = render "detail", booking: @booking, ctx: @ctx
```

`wsjrdp_detail_frame(prefix, key)` answers in the frame the `Turbo-Frame`
request header names, and falls back to the canonical `bkframe-<prefix>-<key>`
(wrapped in `#main`) on a direct visit. A hardcoded id answers the wrong frame,
and Turbo then renders **"Content missing"** instead of the detail. The header is
honoured only when it names **this** record (`…-<key>`), so a stray header — a
form in one pane redirecting onto another record's page — cannot rename that
page's own frame.

**A form inside a lazy detail must redirect to the DETAIL, not back.** In an
embedded pane the detail's forms submit *inside* the frame (only the `:regular`
full page sets `data-turbo=false`), so the response has to re-render that frame.
`redirect_back` lands on the host page, which contains no frame of that row —
Turbo shows "Content missing", or leaves the row on its `Wird geladen …`
placeholder. Redirect to the record's own path on a frame request instead; see
`Fin::BookingsController#redirect_after_update`. Note that a frame response
renders turbo-rails' minimal layout, which has **no flash slot**: a `notice:` on
that path is never seen.

Every detail opens with a **header line of double links** (§2) — that is where a
row links to its own page; the summary row itself carries no action icon.

The detail is optional like everything else: a table that declares **neither**
`detail` nor `detail_src` **nor** a link renders no detail row at all, and its
rows are not disclosure controls (no `role="button"`, no collapse trigger, no
pointer cursor). The Moss wallet (`fin/wsjrdp_fin_accounts/_moss_wallet`) shows
the middle case — its rows already show everything a detail would repeat, so it
declares only links and its detail row is the slim header-line bar.

`ExpandableTableColumn#to_table_column(cell:)` turns a description into the
column Hash the widget expects (`key`, `abbr`, `label`, `condensed_label`,
`numeric`, `width`, `css_class`, `sort_key`, `cell`). **The `cell:` lambda is
the only thing the view adds** — everything else is the description. A helper
that does this for a whole dataset (`booking_table_columns`,
`moss_transaction_table_columns`, `sachkonten_columns`, …) is the normal shape
once the cells need lookup maps.

### The three roles

| role | class | when | what it answers |
|---|---|---|---|
| **declaration** | `Wsjrdp::TableStatePolicy` | once, at **class level**; `wsjrdp_expandable_table_policy` returns the object, the host keeps it in a **constant** | which params this table owns, where each field is stored, what is fixed, what the defaults are |
| **resolved state** | `Wsjrdp::TableState` | once **per request**, from the policy object: `wsjrdp_expandable_table_state(THINGS_POLICY)` — memoised and frozen | what this request actually asks for: sort, visible columns, filter, page size, page, open rows, pane, nesting level |
| **rows** | `Wsjrdp::ExpandableTableRows` | once per request, from state + source | the ordered current `page`, plus `total_count` and `total_sum` over the whole source |

A column is **described once** because those three read different halves of the
same description: the **policy** takes `codec` (the `?c=` / `?s=` allow-list) and
`default_keys`, the **rows object** takes `sort_expressions` (the `ORDER BY`
allow-list), and the **widget** gets labels, widths, alignment and the wire
token through `to_table_column`. Nothing can drift, because there is only one
list.

### Builder facade

The `wsjrdp_expandable_table` helper wraps the partial call in a block-based
builder so you don't have to pass ~20 locals by hand. `t.rows` names the table
**once**: it takes the host's `Wsjrdp::ExpandableTableRows` and sets both halves
the widget needs (`t.state rows.state, id:` + `t.data rows.page`). Those two
survive for the rare table that has no rows object; one of the two forms is
**required**. `t.sort` only chooses the *display* mode (multi-column is the
default) — the sort itself and its default come from the state. See
`Wsjrdp::ExpandableTableBuilder` for the full method list.

### State: who owns what

Everything a table reads from the request — sort, visible columns, filter, page
size, page, open rows, the filter pane, the nesting level — is **resolved by the
controller into one frozen `Wsjrdp::TableState`** and handed to the view. The
widget itself reads nothing from `params`, `session` or `cookies`.

**The split (D1, D2c):**

1. The controller **declares** the table once, at class level, with
   `wsjrdp_expandable_table_policy prefix: …` (like `before_action` or Kaminari's
   `paginates_per`) and keeps the **returned policy object** in a constant.
   Class level is required because the reset `before_action` must know every
   table of the page before the action runs. Values that depend on the request
   (a store key built from `params[:number]`, a fixed filter from the path) are
   given as **lambdas** and evaluated on the controller instance.
2. The controller **resolves** that policy per request with
   `wsjrdp_expandable_table_state(POLICY)` — the policy is passed
   **positionally**, nothing looks a table up by its prefix string, and
   resolving a policy that is not declared on this controller raises. There is
   **no** `helper_method :wsjrdp_expandable_table_state`: a view never resolves
   a state, it reads what its host exposes.
3. The controller builds the table's `Wsjrdp::ExpandableTableRows` from that
   state and exposes **that** under a name of its own (`things`, `bookings`,
   `entries`, `cost_centers`, …). The view hands that ONE object to `t.rows`,
   which is where the state reaches the widget (`rows.state`).

The rule that the widget never touches request state is **enforced, not asked
for**: `spec/domain/wsjrdp/expandable_table_state_guard_spec.rb` greps every
`app/views/shared/wsjrdp/**/*.haml` partial and the helper for `params[`,
`session[`, `cookies[` and `request.`, and fails on any hit. The single exception
is link construction — `et_carry_params` and `et_current_path` merge
`request.query_parameters` / `request.path` so a generated link keeps every
*other* param (a sibling table's state, a host's own page param, the locale)
untouched. Those values are passed through into a URL, never turned into state.

#### The fields and their wire form (D2a)

A query param is `<prefix><short>`: the prefix followed directly by a
**one-character** field name (no underscore), so param names can never collide
across prefixes. `Wsjrdp::TableStatePolicy::FIELD_DEFINITIONS` is the one place
that table lives:

| field | short | wire form | reader on the state | default policy |
|---|---|---|---|---|
| `sort` | `s` | RISON list `bez,nr~` (`~` = descending, first = primary) | `state.sort_list` → `[[key, dir], …]` | `:remember` |
| `cols` | `c` | `nr,~bez,sum` (`~` = hidden), order = display order | `state.column_states` / `state.visible_column_keys` | `:remember` |
| `filter` | `f` | Rison CNF tree (the **user** part only, canonical short keys) | `state.filter` → a parsed `Wsjrdp::TableState::Filter`, see below | `:url` |
| `per_page` | `z` | integer or `all` | `state.per_page` → `Integer` or `:all`; `state.per_value` is its wire form | `:remember` |
| `page` | `p` | integer | `state.page`, applied by `state.paginate(source)` | `:remember` |
| `open` | `o` | comma list of row keys | `state.open_keys` (a Set) | `:url` (cannot be remembered) |
| `level` | `expandable_table_level` | integer (nesting depth) | `state.level` | `:url` (cannot be remembered; **not** prefixed — see below) |
| `pane` | `e` | `1` / `0` | `state.pane` | `:remember`, store `:cookie` |

Two more params are commands, not state: `<prefix>r=1` resets **that** table and
`table_state_reset` (`Wsjrdp::TableStatePolicy::PAGE_RESET_PARAM`, its value
ignored) resets **every** table declared on the page.

Code always uses the **long** names (D2b): column keys (`booking_date`),
attribute keys, field names. The one-letter field names and the short column
tokens exist only on the wire and in the stores. `state.param_name(:sort)` gives
the concrete param name, `state.wire(:sort)` the current wire value,
`state.column_token(key)` / `state.column_key(token)` translate a column either
way, and `state.wire_params` gives back exactly the params **the URL** chose
(for a redirect that has to reproduce the view).

#### The three policies (D1, defaults per D6)

```ruby
wsjrdp_expandable_table_policy prefix: "bk",
  columns:  Fin::DatevBookingsColumns.codec,                # key => abbr codec
  sort:     {default: [["booking_date", "desc"]]},          # LONG names
  cols:     {default: Fin::DatevBookingsColumns.default_keys},
  per_page: {default: 50, max: 500},
  filter:   {policy: :remember, schema: Fin::DatevBookingsFilterSchema, exclude: %i[sphere]},
  pane:     {default: 1}
```

Two table-wide options sit next to the per-field ones: `store:` (which store the
table's `:remember` fields use, default `:session`) and `store_key:` — both are
described under "Stores" below.

- `:url` — the value lives in the URL only, nothing is remembered.
- `:remember` — the URL carries it, the store mirrors the last value and restores
  it when the param is **absent**.
- `:fixed` — the controller gives the value; the param and the store are **not
  consulted at all** and the widget renders the field read-only (no sort links,
  no menus). There is no code path from user input to a fixed field, which is
  why the guarantee is structural rather than a UI convention (D8.1).

Resolution order is **fixed › URL › store › default**, in the one place that
does it (`Wsjrdp::TableState::Resolver`). Defaults live in the policy, not in the
view. Every field option is either a bare symbol (`filter: :remember`, shorthand
for `{policy: :remember}`) or a Hash `{policy:, default:, store:, …}`;
`per_page` additionally takes `max:` (the cap on a hand-written `?z=`; its
`default:` is an Integer or the symbol `:all`, which starts the table unpaged),
`cols` takes `exclude:` and `labels:` (below), and `filter` takes `schema:`,
`fixed:`, `exclude:`, `default:` and `presets:` (below).

Without an explicit policy (D6): `sort`, `cols`, `per_page` and `page` are
`:remember`; `filter` and `open` are `:url`. `open` and `level` can never be
remembered — declaring them `:remember` raises.

Two rules matter when a user wants to get *back* to a default:

- **A present-but-blank param beats the store.** `?f=` (or `?c=`, `?s=`) is an
  explicit "empty" and wins over the remembered value; only an **absent** param
  falls through to the store. That is what the column picker's "Standard-Spalten"
  link and an emptied filter apply emit.
- **Only non-default values are stored.** After resolving, the resolver writes
  back the resolved (and therefore allow-listed) wire value of every
  `:remember` field whose value differs from the table's default; a value equal
  to the default is dropped. The store entry is written even when *nothing*
  differs any more, so an explicit "back to default" replaces the old entry
  instead of leaving it behind.

Both read paths pass the same allow-lists (D8.5): sort and column tokens against
the policy's `columns:` codec, `per_page` capped, open keys bounded, filter
attributes against the bound schema. A poisoned or stale store entry is
therefore no stronger than a hand-edited URL.

#### Stores (D7)

A store maps a **store key** to a small Hash of `field short => wire value` and
implements `read(key)`, `write(key, hash)`, `delete(key)`, `delete_all(key_prefix)`.

- **`:session`** (the default) — one session slot,
  `Wsjrdp::TableStateStore::Session::SESSION_SLOT` (`wsjrdp_table_state`).
  hitobito's session store is the `active_record_store`, so this does not hit the
  4 KB cookie limit, but every change costs a session-row write; keys are grouped
  by controller and the oldest of a group are evicted beyond
  `MAX_KEYS_PER_CONTROLLER` (50), so per-row nested memory cannot grow without
  bound. A write with an empty hash removes the entry.
- **`:cookie`** — one cookie per field, for values the **browser** changes
  without a request (`pane` is the only use today: the widget writes
  `document.cookie` directly, the name coming from `state.cookie_name(:pane)`).
  **Caveat (D2d):** a `:cookie` value does *not* always travel through a request —
  the browser changes it on its own and the server only learns about it on the
  next render — and a cookie is client-controlled (editable in the browser).
  Never choose `:cookie` for anything sensitive, for anything that influences the
  row set or the scope, or wherever the controller's primacy over the value
  matters. It is for pure display chrome, only single-token values are
  accepted, and it is meant for tables with a **static** store key — it has no
  key cap, so a per-row nested table would mint one cookie per opened row.
  `write` has the same replace semantics as the session store: a field missing
  from the hash is forgotten, an empty write removes the table's cookies, an
  unchanged value is not re-set.

The store key defaults to `"<controller_path>#<action>"` plus the prefix, so two
tables on one page never share memory. An explicit `store_key:` (String or
lambda) lets several actions share — or a nested table key its memory per parent
row. A later per-person DB store implements the same four methods.

#### The filter: a schema, fixed slots, exclude (D2e)

The filter is the one field the controller can pin **partially** — some slots
fixed, the rest left to the user — and the one field that needs to know **which
dataset** it filters:

```ruby
filter: {policy: :url,
         schema: Fin::DatevBookingsFilterSchema,          # the dataset (mandatory)
         fixed: [{slots: LOCKED_FILTER_TREE, show: :readonly},   # rendered, locked
                 {slots: HIDDEN_TREE,        show: :hidden}],    # never rendered
         exclude: %i[sphere cost_center],                 # not offered in the picker
         default: [[["konto", "in", "41030"]]],           # user tree, if nothing chosen
         presets: PRESETS}                                # one-click toggles, see below
```

**`schema:`** is a module extending `Wsjrdp::Filtering::FilterSchema`
(`doc/wsjrdp/generic_filter_builder.md`, Part 4). The protocol is small and is
the whole reason the filter can be strict where it must be:

| method | input | strictness |
|---|---|---|
| `bound(except:)` → `BoundSchema` | the table's `exclude:` | implemented by the dataset module (it owns the base relation) |
| `decode(raw, schema:)` → `Query` | the `f` param **or** a store value | **tolerant**: unknown / excluded keys dropped, garbage → empty |
| `encode(query, schema:)` | a parsed query | canonicalizes to short keys |
| `encode_tree(tree, schema:)` | the builder's posted JSON tree | **tolerant** (it comes from the browser) |
| `parse_fixed!(tree, schema:, what:)` → `Query` | host code: fixed slots, `default:` | **strict**: raises, naming attribute, operator and slot index |
| `compile(query, schema:, relation:)` → relation | a parsed query (or nil) | merges the schema's own base relation, then the compiler |

`schema:` comes **only from this declaration**: never from a param, the store or
a cookie, so no request can point a table at another dataset's schema. It is
mandatory as soon as any other filter option is declared, and a table that
declares no `filter:` at all gets an **inert** filter (no catalog, no user query,
`scope` returns its argument).

**Everything is parsed by the resolver, once per request.** It binds the schema
twice — the full one and the one reduced by `exclude:` — and runs the two halves
through it with the two different levels of strictness:

| half | source | how it is parsed |
|---|---|---|
| the **user** part | the `f` param **or** the store | `decode` against the **reduced** schema — tolerant: an excluded or unknown attribute is dropped, on either path, so `exclude:` cannot be bypassed |
| the **fixed** slots | the policy (code) | `parse_fixed!` against the **full** schema — **strict**: a typo raises, naming attribute, operator and slot index |

The strictness split is the point: the compiler is neutral-on-invalid, which is
right for user input (a dropped condition only narrows the user's own filter) but
wrong for a pinned slot, where a typo would silently drop the pin and **widen**
the page scope. `spec/controllers/fin/table_policies_spec.rb` resolves every
declared table of the wagon once, so such a typo fails in CI.

**`state.filter` readers** (all of them derived from the parsed halves):

| reader | meaning |
|---|---|
| `scope(base)` | **THE** filtered relation: fixed slots (full schema) first, the user query (reduced schema) on top. The only way from a filter to a scope. |
| `user_query` / `user_slots` | the parsed user filter, and the same as a tree; `nil` / `[]` when there is none |
| `fixed_entries` / `fixed_slots` | the validated `[{slots:, show:}]` entries, and all their slots as one tree |
| `readonly_slots` / `hidden_slots` | the fixed slots the builder shows as locked chips / the ones that never reach the view. Display visibility never influences enforcement (D8.3). |
| `effective_slots` | fixed + user slots, i.e. what actually filters the rows |
| `catalog` / `full_catalog` | the picker's catalog (reduced by `exclude:`) and the wider one that labels a fixed condition using an attribute the picker hides |
| `presets` / `preset(**declaration)` | the policy's quick-select presets as `Wsjrdp::TableState::FilterPreset`s — one per slot preset, one per member of a preset group — and the same for a view-declared one (a group yields the Array of its members; see "Presets" below) |
| `exclude` | the excluded attribute keys |
| `schema` | the dataset module itself (`nil` for an inert filter) |
| `wire` (= `state.wire(:filter)`) | the canonical short-key wire form of the user part, `""` when empty |
| `encode_tree(tree)` | the filter builder's posted tree → wire form, for the apply redirect |
| `fixed?` | does the table pin anything? |

- The effective filter is `fixed slots AND user slots` (CNF), so the user part
  can never remove or widen a fixed slot; the `f` param and the store only ever
  hold the user part.
- `policy: :fixed` on the filter means "fixed slots only, no user part".
- `default:` is host-authored like a fixed slot and therefore parsed strictly —
  against the *reduced* schema, because it IS the user part. It applies only on
  the `:default` resolution path: a present-but-blank `?f=` is the user's "no
  conditions" and beats it, as does anything in the store.
- Joins are not a host's business: `compile` merges the schema's own base
  relation, so the bookings' `left_joins(:batch)` (which backs `financial_year`
  and `batch`) and the Moss expenses/bookings joins are always there.

**How a filter renders.** Three blocks, in this order — the host passes the
display options above and nothing else:

1. **The filter line** (`shared/wsjrdp/filtering/_line`): one framed strip.
   Left, in `.flt-line-left`, the "Schnellauswahl" preset bar (its DOM id is
   `et_filter_presets_id(state)`) and, after it, the applied filter's chips.
   Right, at the end of the line, the pane's toggle
   (`button.pane-toggle[data-pane-target=et_pane_id(state)]`) with the number of
   applied user conditions as a badge and the builder's "nicht angewendet" pill.
   The column hamburger is not on this line.
2. **The pane** (`shared/wsjrdp/filtering/_builder`), rendered right after the
   line and opening between it and the toolbar, so the toggle stays under the
   pointer that clicked it. Its open state is the `pane` field (`e`, stored in a
   cookie, D2a) and reaches the view as `state.pane`; the line carries
   `data-pane-line` with the pane's id and follows its open state, so line and
   open pane read as one box.
3. **The toolbar** with the summary, the paging line and the ☰ column menu,
   then the table.

**The chips** (`shared/wsjrdp/filtering/_chips`, worded by
`Wsjrdp::FilterChips`) are the applied filter at a glance: one chip per slot of
`state.filter.user_slots`, in slot order, separated by "und" — the slots are
ANDed — and each worded exactly as the builder words that condition. A chip is a
`button.flt-chip.pane-opener`: it carries no remove "×" and only ever *opens*
the pane; while the pane is open the chips hide, because the builder right below
shows the same conditions in full and editable. What is chipped follows three
rules:

- a slot equal to an **active** preset's slot gets none — the preset toggle in
  the bar to its left already shows that state (`SlotEquality`, the rule that
  decided `active?`, so an inactive preset drops nothing); likewise a slot of a
  **preset group** — one `in` condition on the group's attribute whose values
  are all member values — gets none, because the pressed member buttons show
  it (a slot holding a value outside the group keeps its chip);
- **fixed slots never become chips**: `user_slots` is the user half alone, and
  the builder renders the `readonly` ones as locked chips instead;
- with no chip at all the line reads **"Kein Filter aktiv"** only when the table
  has neither presets nor fixed slots. A table with presets shows the bar, which
  already says that none is switched on; a table whose slots are all pinned
  shows nothing, because it *is* filtered — just not by the user.

#### Presets — the filter's "Schnellauswahl"

The "Schnellauswahl" bar at the left of the filter line, above the pane, holds
the table's one-click toggles. Every one of them is a shortcut *into* the user
part — not a pin: what a toggle adds lands in the `f` param like any other user
slot, and the user can edit or remove it in the builder afterwards.

Two declaration forms stand side by side in one list:

- a **preset** — a named list of slots one button switches on and off as a
  whole;
- a **group** — several buttons sharing ONE slot `attribute in (values)`, one
  value per button. That is the form for the alternatives of a single question,
  where two pressed buttons have to WIDEN what is shown: as two presets they
  would be two ANDed slots and find nothing.

**Declared once**, either in the policy

```ruby
PRESETS = [{key: "with_bookings", label: "Nur mit Buchungen",
            slots: [[["booking_count", "nonzero"]]]},
           {key: "with_balance",  label: "Nur mit Saldo ≠ 0",
            slots: [[["booking_balance_abs", "nonzero"]]]}].freeze

filter: {policy: :remember, schema: Fin::PersonalAccountsFilterSchema, presets: PRESETS}
```

or in the view (`t.filter apply_url: …, presets: [...]`). **Declaring both is an
`ArgumentError`** naming the table — `Wsjrdp::ExpandableTableBuilder#to_locals`
is where the two sources meet. Either way the state builds the same objects
(`state.filter.presets`, and `state.filter.preset(**declaration)` for a
view-declared one), so there is one implementation.

Preset slots are **host-authored like fixed slots** and therefore parsed
**strictly** (`parse_fixed!`, `what: "filter preset <key>"`) — against the
*reduced* schema, because they are the user part. A typo raises, and
`spec/controllers/fin/table_policies_spec.rb` turns that into a CI failure.

A **group** goes into the same list, in either place — this one is the Moss
wallet's four kinds (`Fin::WsjrdpFinAccountsController#wallet_presets`):

```ruby
{group: "kind", attribute: "kind", operator: "in",
 members: [{key: "card", label: "Karte", value: "MossCardTransaction",
            icon: "credit-card", css_class: "moss-kind-card_transaction"},
           …]}
```

`group:` names the declaration and appears in every message it raises,
`attribute:` is the one attribute all its buttons filter on, `operator:` is
`in` — the only operator a group takes — and each member carries the `key:`,
`label:` and `value:` of one button plus the same optional `icon:` /
`css_class:`. It is checked as strictly as a preset's slots and against the same
*reduced* schema: an attribute that schema does not carry or does not offer `in`
on, another operator, a `value:` outside the attribute's options, a repeated
member key or value, an unknown or a missing keyword — each raises an
`ArgumentError` naming the group, and the smoke spec makes that a CI failure.

`state.filter.presets` is **flat**: a group contributes one `FilterPreset` per
member, in declaration order, so the bar renders a member exactly as it renders
a preset — one link, tick, icon, class — with no group title and no segment
around them. `group?` tells the two apart.

| reader on `Wsjrdp::TableState::FilterPreset` | meaning |
|---|---|
| `key` / `label` | the button's name and its text |
| `slots` | a preset's slots, strictly parsed (long keys); `nil` for a group's member |
| `active?` | a preset: is **every** one of its slots present in the **applied** user filter? a member: does a matching slot carry its value? |
| `toggle_wire` | the wire form of the user filter after clicking the toggle |
| `icon` / `css_class` | optional display extras, `nil` by default (below) |
| `group?` | is this button one member of a group rather than a preset of its own? |
| `group` / `attribute` / `value` | a member's group name, the group's attribute and the one value this button stands for (`nil` on a preset) |
| `group_values` | every member value of the button's group, in declaration order — what the chip and the builder rules read (`nil` on a preset) |

- **Exact slot equality decides a preset's `active?`.** Two slots are equal iff
  they hold the same **set** of conditions (attribute, operator, operands) —
  order irrelevant, operands compared canonically (`0` and `"0"` are one value).
  A user slot that carries a preset's condition **plus further OR conditions
  does NOT count**: an added OR *widens* the slot, so the preset's promise no
  longer holds. The rule lives in **one** place,
  `Wsjrdp::Filtering::SlotEquality`; the builder's JS repeats it for its
  cosmetic slot marking.
- **A sign pair counts as one attribute where the sign does not matter.** The
  two members of an amount's sign pair (`sign: :signed` / `:absolute`, the
  signed column and its `ABS()` twin) ask the same question under a
  **sign-invariant** operator — `≠ 0`, `hat Wert`, `ist leer` and `= 0` say
  nothing about the sign — so `Saldo ≠ 0` and `|Saldo| ≠ 0` are **one**
  condition: the "Nur mit Saldo ≠ 0" preset is pressed on either, its toggle
  removes whichever the user has, and neither gets a chip while it is on.
  Comparisons stay member-specific (`|Saldo| ≥ 100` and `Saldo ≥ 100` are
  different questions, as are `= 5` and `= -5`). `SlotEquality` takes the
  pairing as `aliases:`, `{signed key => absolute key}` — the table state reads
  it off the bound schema (`Wsjrdp::Filtering::Schema#sign_aliases`), the chips
  off the catalog, the builder's JS off the catalog's `variant_group`/`sign`.
- **A toggle applies at once**, as a plain GET link: `et_url(state, {filter:
  preset.toggle_wire})`, which drops the page and the open rows like any other
  filter change (D4). Turning a preset **on** adds the slots the filter is
  missing, turning it **off** removes exactly the preset's slots and leaves
  every other slot alone. Where the table remembers its filter, the store
  follows as it does for any filter change.
- **Overlapping presets follow from that** and are not special-cased: if a
  two-slot preset contains the slot of a one-slot preset, switching the first
  on shows the second as active too, and switching the second off removes the
  shared slot and deactivates both (covered by `table_state_spec.rb`).
- **A group's members read and write ONE slot.** *Matching* are the user slots
  of exactly one condition, on the group's attribute, under `in`. A slot with a
  further OR condition asks a wider question, another operator a different one,
  and fixed slots are never the user part — none of the three is ever read as
  the group's or touched by a member. A member is **active** when any matching
  slot carries its value; the buttons are therefore independent of one another,
  and a hand-written slot the group cannot read simply leaves all of them off.
- **Selecting** puts the value into every matching slot that lacks it, the other
  values untouched, and appends `attribute in (value)` as a new slot when there
  is no matching slot at all. **Deselecting** takes the value out of every
  matching slot; a slot whose set runs empty goes altogether — switch the last
  pressed button off and the filter is blank again.
- **A group's slot gets no chip** while it says nothing its buttons do not: one
  condition of the shape above, and every one of its values a member's. One
  value that belongs to no member and the chip stays — no button could show
  that one.
- **Locked while dirty.** The bar sits outside the builder's `.flt-root`, so the
  builder's JS reaches it by the id `et_filter_presets_id(state)`. While the
  builder differs from the applied filter (`.flt-dirty`), every toggle is
  disabled — `aria-disabled="true"`, no `href`,
  `tabindex="-1"`, the title "Gesperrt: erst die Änderungen im Filter anwenden
  oder verwerfen" — and the bar shows "⚠ gesperrt, bis die Änderungen angewendet
  oder verworfen sind". (A link cannot carry `disabled`; removing the `href` and
  setting `aria-disabled` is the accessible equivalent.) *Why:* a preset applies
  immediately, which would silently throw the unapplied edits away.
- **The active state is server-rendered**, from the **applied** filter — never
  live from the builder. The builder only *marks* a slot the bar speaks for (a
  left accent stripe and the tooltip "Slot des Presets „…“"): a slot equal to a
  preset's, named after the first preset that declares it, and a group's shared
  slot, recognised by the chip rule above and named after the members whose
  values it holds.
- **A button may carry an icon and a class.** Both declaration sites, and a
  group's members as well, accept the optional `icon:` (a FontAwesome 5 name
  **without** the `fa-` prefix, e.g. `"credit-card"`) and `css_class:` — the bar
  renders the icon as `<i class="fas fa-…">` between the tick and the label, and
  adds the class verbatim to the toggle link (next to `btn btn-sm
  btn-outline-secondary flt-preset`), which is how the Moss wallet colours its
  four kind buttons.
  Display only: they never touch the slots, `active?` or `toggle_wire`, both
  default to `nil`, and a preset that declares neither renders exactly as it did
  before. Any *other* key raises `ArgumentError: unknown keyword`.
- There is **no "Alle" preset**: "Filter zurücksetzen" already is that.
- A table that declares no presets renders **nothing** — no bar, no label.
- A preset goes by what the schema **accepts**, not by what its editor
  **offers** — the two lists differ (`doc/wsjrdp/generic_filter_builder.md`,
  "Accepted vs. pickable operators"). "Nur mit Saldo ≠ 0" is one `nonzero`
  condition on `booking_balance_abs`, and its slot stays editable in the builder
  afterwards like any other.

#### Reset (D3)

The filter builder itself never applies anything on its own: adding, editing
and removing conditions only change the builder's value, and while that value
differs from the applied filter a warning chip ("Änderungen noch nicht
angewendet"), the "nicht angewendet" badge on the filter toggle (visible even
when the pane is collapsed) and a highlighted "Anwenden" say so — and the preset
toggles are locked for as long. That toggle sits at the right end of the filter
line and names the pane in `data-pane-target` (`et_pane_id(state)`); the pane
opens between the line and the toolbar, and the toolbar below holds the column
hamburger (`.exp-tools`). Two controls take the builder back:

- **"Änderungen verwerfen"** (shown only while there are unapplied edits)
  restores the builder to the applied filter — pure client-side, no request.
- **"Filter zurücksetzen"** applies the table's **default** filter:
  `et_filter_reset_url(state)` sets *this table's* filter param to the policy's
  `default:` tree in wire form, or **present but blank** (`?f=` / `?bkf=`) when
  the table declares no default (`state.filter.default_wire`), and drops its
  page and open rows (D4: a filter change closes every row). Everything else
  survives untouched: sort, columns, page size, a sibling table's state and any
  non-table param. Present rather than absent is what makes it work on a page
  that *remembers* its filter — a present param is the explicit choice that
  beats the store, an absent one would fall through to it and bring the
  just-cleared filter back (same rule as the column picker's
  "Standard-Spalten", which emits `?c=`).

Beyond the filter there is one more reset, without a control in the UI:
- **The whole table — `<prefix>r=1`, page-wide `table_state_reset`.** The
  `before_action` in `Wsjrdp::TableStateful` deletes the store entry (or every
  one of the page's) and redirects to the same URL without those params.
  `et_reset_url(state)` is the one place that knows how to build such a URL, but
  **nothing in the UI calls it** — the filter's "Filter zurücksetzen"
  deliberately does not forget sort, columns or page size. Both params stay supported; fixed fields
  are unaffected either way (they are never stored and are re-fixed on the next
  render).

There is no `?clear=` any more.

A table with a `default:` filter tree (a filter applied when the user has not
chosen one) treats the blank param as the user's "no conditions" by
construction: the default only applies on the `:default` resolution path, and a
present-but-blank param resolves as `:url`.

#### Page and open rows (D4)

`page` is remembered like the rest, so returning through a tab lands where one
left — but a remembered page beyond the last one falls back to page 1 instead of
showing an empty table. The clamp needs the row count, which the resolver does
not have, so it lives in **`state.paginate`** — the one method every table pages
through, whatever its rows are made of:

```ruby
state.paginate(scope)   # an ActiveRecord relation (the bookings, the Moss transactions)
state.paginate(rows)    # a plain Array of row Hashes
```

Hosts do not call it themselves: `Wsjrdp::ExpandableTableRows#page` orders the
source and pages it through exactly this method. It applies `state.page` and
`state.per_page`, wraps an Array in `Kaminari.paginate_array` first, and returns
page 1 when the requested page is out of range. `per_page == :all` (the symbol —
`?z=all` on the wire) means "one page holding everything"; the large limit that
implements it is private to `Wsjrdp::TableState`, so no host ever compares
against a sentinel number.

`open` is `:url` only and never stored. Toggling a row writes `o` into the URL
via `history.replaceState` (no request — one of the two deliberate exceptions to
D1, the other being the cookie-stored `pane`; both are harmless because they
never touch the row set). Consequently:

- a browser reload keeps the open rows (the URL carries `o`);
- a filter, page or page-size change closes all rows — `et_url` drops `o`
  whenever it changes `f`, `p` or `z`, the paging links pass
  `params: {<prefix>o => nil}`, and the filter apply drops it too;
- a sort or column change keeps them (same rows, different order/columns);
- leaving the page and coming back starts with all rows closed;
- keys that are not on the rendered page are ignored, and their number is
  bounded so a hand-written URL cannot grow without limit.

#### Nesting: a table inside a detail row

A table embedded in another table's detail is its **own** declared table with its
own prefix, and it remembers **per parent row** (D2): two cost centers keep
separate sort/column memory for their embedded bookings tables. Each Buchhaltung
controller declares both of its tables itself: the summary list with its own
policy (filter included, see the Kreditoren example below), the embedded table
from the option hash `Fin::BookkeepingSummaries` offers:

```ruby
SUMMARY_POLICY = wsjrdp_expandable_table_policy prefix: "",
  columns: Fin::BookkeepingSummaryColumns::COST_CENTERS.codec,
  # ... sort/cols/per_page defaults, filter: {policy: :remember, schema: ...}
ITEM_BOOKINGS_POLICY = wsjrdp_expandable_table_policy(**Fin::BookkeepingSummaries
  .item_bookings_policy_options(row_param: :number, nested: true))

def summary_table_state = wsjrdp_expandable_table_state(SUMMARY_POLICY)
def item_bookings_table_state = wsjrdp_expandable_table_state(ITEM_BOOKINGS_POLICY)
```

`item_bookings_policy_options` is the embedded table (prefix `"b"`):

```ruby
{prefix: "b",
 columns:  Fin::DatevBookingsColumns.codec,
 sort:     {default: [["booking_date", "desc"]]},
 cols:     {default: Fin::DatevBookingsColumns.default_keys},
 per_page: {default: CONDENSED_DEFAULT_PER},
 store_key: -> { "#{controller_path}##{action_name}:#{params[row_param]}" },
 # only with nested: true
 level:     {default: -> { summary_table_state.level }}}
```

- the `store_key:` lambda folds the row parameter of the detail's own request
  (`params[:number]` for the Buchhaltung pages) into the key, which is what makes
  the memory per item;
- the `level:` lambda inherits the depth the parent list put into the detail's
  frame URL (`?expandable_table_level=…`), so the nesting keeps counting up (§4). It reads
  `summary_table_state`, so only a section that HAS a summary list asks for it —
  that is what `nested: true` says. The Buchungsstapel page has no summary list,
  omits `nested:` and starts at level 0.
- a lazy detail is its own request to its own controller: whatever the parent
  pins is pinned again there, from its own path id and authorization — the level is the
  only thing the frame URL carries, and it only affects nesting depth, never
  scope (D8.7).

**There is no level-2 table today**: the only nested table in the app is the
condensed bookings table inside a Buchhaltung item's detail (prefix `"b"`, level
1), and its own rows' details embed no further table. The mechanism is in place
and exercised, but the recursive case beyond one step is covered only by unit
specs.

---

## 2. Add features, one local at a time

Each of these is independent and defaults to off.

**The detail's header line of links.** Every detail row starts with one
right-aligned line that holds nothing but **double links** — no title, no other
content. A double link is a Bootstrap button group of two small outline buttons:
the LEFT one (icon + text) opens the target in the SAME tab, the RIGHT one (only
the external-link icon) in a NEW one. It lives in the detail row, never in the
summary row, so clicking it never toggles the disclosure and every link is an
ordinary focusable anchor.

```haml
  - t.detail_page { |thing| thing_path(thing) }        # the primary link
  - t.detail_link label: "In Moss", icon: :wallet,     # further links, left of it
      title: "Transaktion in Moss öffnen",
      title_new_tab: "Transaktion in Moss in neuem Tab öffnen", &moss_url
```

`t.detail_page` declares the PRIMARY link — the row's own page, labelled
"Detailseite" with the eye icon — and it is the RIGHTMOST group. `t.detail_link`
adds a further one and may be called several times; those sit LEFT of the
primary, in declaration order. A link whose block returns no URL for a row
renders no group there, so a row without that target simply shows one group less
(the Buchungen list therefore shows "In Moss" only on a booking that came from
Moss — and not even then for a top-up, the one Moss kind without a derivable
record page, see `MossTopUp#moss_record_url`). `icon:` is a FontAwesome 5 name
without the `fa-` prefix; `title:` and
`title_new_tab:` are the tooltip and the aria-label of the two halves.

Declaring a link makes a table **expandable** even when it has no detail at all:
the detail row is then the slim header-line bar alone. With a **direct** detail
the line is the first thing inside it; with a **lazy** one it sits above the
turbo frame, so it is there while the frame still says "Wird geladen …" — the
same place either way (`shared/wsjrdp/_detail_links`,
`shared/wsjrdp/_expandable_table_styles`).

**Sortable headers.** A column becomes clickable by declaring a `sort:` in its
description — `to_table_column` turns that into the widget's `sort_key:`. The
default order is the policy's, not the view's:

```ruby
sort: {default: [["total", "desc"]]}     # in wsjrdp_expandable_table_policy
```

The whole sort lives in ONE `<prefix>s` param as a comma list of the columns'
wire tokens, a trailing `~` meaning descending and the first entry being the
primary sort (`?s=bez,nr~`). Clicking a header makes that column primary and
cycles it asc → desc → off; the rank shows as a small superscript when two or
more columns are sorted. An emptied sort sets the param explicitly blank, so it
also clears a remembered sort.

Nothing in the view or the controller decodes the param — the state did that
against the policy's column codec, and `Wsjrdp::ExpandableTableRows` orders the
source from `state.sort_list` through the `sort:` map it was given (the
dataset's `sort_expressions`, which is therefore the second allow-list: a sort
key the map does not know is dropped, so only fixed, safe expressions reach
`ORDER BY`).

An **empty** `sort_list` is the normal "nobody chose anything" case, and it is
where `natural_order:` comes in:

- for a **relation**, without a `natural_order:` the rows fall back to the
  `tiebreaker:` alone (`:id` by default; a fragment that names its own direction
  is taken verbatim, e.g. `"accounting_entries.id DESC"`);
- for an **Array**, the rows keep the order they arrived in. An array-backed
  table is pre-ordered by its own SQL query, and re-sorting it in Ruby would
  apply a **different collation** than that query did — so the incoming order is
  the honest natural order;
- `natural_order: ->(source){ ordered source }` expresses an order no column
  sort can. The reconciliation entries table puts its match proposals first that
  way (`Fin::ReconciliationController#order_proposals_first`).

Do *not* declare a sort default that the query then overrides: the header arrows
are rendered straight from the resolved state, so a declared default nobody
honours puts an arrow on a column the table is not sorted by. Express the
natural order as the empty-`sort_list` case instead.

An array-backed table must give a `->(row){ comparable }` **tiebreaker** (the
constructor raises otherwise) so equal rows stay in a deterministic order —
Ruby's `Array#sort` is not stable. And its extractors have to compare the way
the producing SQL did: account and cost-center **numbers may contain letters**,
so `Fin::BookkeepingSummaryColumns::NUMBER` compares them as a **String**
(`to_i` would collapse every alphanumeric number into one value and scramble the
order).

Multi-column sort is the **default** display mode. For tables that should only
ever sort by one column, pass `t.sort multi: false` — this uses the same RISON
infrastructure but constrains to a single key (via `after_click_single`), so the
URL always has at most one sort token and the UI never shows rank numbers.

**A summary line.** It is a plain String, so it is the host that decides what to
count — normally the rows object's own totals over the WHOLE source, not the
page:

```haml
  - t.summary "#{rows.total_count} Einträge · Summe: #{rows.total_sum}"
```

`total_count` is Kaminari's count over the whole source (not the size of the
page), `total_sum` the `SUM` of the rows object's `sum:` column over the same —
`nil` when the table declares none. The summed columns carry a baked sign
(`doc/fin/money_conventions.md`), so a plain `SUM` is correct.

**Paging (above and below).** Turn it on with a bare `t.paging` — page size and
page come from the state, their defaults from the policy
(`per_page: {default: 50}`):

```haml
  - t.rows   things                     # its #page is already the current page
  - t.paging                            # or per_options: [10, 25, 50, :all]
```

`per_options` are the steps of the "pro Seite" select; the default list is
`Wsjrdp::ExpandableTableBuilder::DEFAULT_PER_OPTIONS`
(`[25, 50, 100, 200, 500, :all]`, `:all` labelled "Alle"). Pass your own only
when this table wants other steps — the reconciliation entries table drops
`:all`, the Buchhaltung summaries start at 10.

What appears where:

- **page links + a jump field**, above and below the table, whenever there is
  more than one page. The line reads `‹ › 1 … 30 31 32 33 [34] 35 36 37 38 …
  137`: two icon-only step buttons lead it and hold their place on every page
  — disabled on the first resp. the last one, so neither they nor the numbers
  behind them move as one pages on — then page 1, the last page and four pages
  either side of the current one (one fewer than Kaminari's default), with `…`
  bridging the rest. The markup is the wagon's Kaminari theme `wsjrdp`
  (`app/views/kaminari/wsjrdp/`), asked for with `theme: "wsjrdp", left: 1,
  right: 1`. "Seite [n] von N" goes straight to the typed page on Enter or on
  leaving the field (clamped to 1..N; a page change closes the open rows like
  any other);
- **the page-size select**, whenever the size is not `:fixed` — including when
  everything fits on one page. It is the only way *back* to a smaller page (or
  forward to "Alle"), so it must not vanish the moment it took effect. The
  **bottom** line therefore always carries it, the **top** one only when there is
  more than one page; a single-page table renders one paging line, below the
  table, holding just the select.

The widget does **not** order or slice the rows itself — the data must already
be the ordered current page, which is exactly what `Wsjrdp::ExpandableTableRows`
produces. Its source is an ActiveRecord relation or a plain **Array**, so an
in-memory list of row Hashes needs nothing of its own:

```haml
- t.rows   cost_centers, id: "cost_center"
- t.paging per_options: [10, 25, 50, 100, :all]
```

The widget's own sort links already drop the page param; any links or forms you
build yourself should carry the table's state with
`et_carry_params(state, except: %i[page open])` so a changed row set starts on
page 1 with the details collapsed.

**A column hamburger (show/hide + reorder).**

```haml
  - t.columns columns, menu: true
```

A right-aligned ☰ opens a picker (check to show, drag to reorder). The full
selection is encoded into the `<prefix>c` query param (shareable / bookmarkable,
never localStorage) using each column's `abbr`; whether it is also *remembered*
is the controller's policy, not the form's business. The default set is
`cols: {default: …}` in the policy — in the declared order, which is the column
order (a table may put its own column first); every other column of the set
follows, hidden. The picker's "Standard-Spalten" link returns to it by setting
`?c=` explicitly blank. `columns:` in the view is then the FULL set; the widget
renders only the visible ones in the chosen order. A column the state's codec
does not know is appended hidden.

*One description per dataset, one column set per table.* A dataset's columns are
described **once** (§1a) even when several tables show it. What a single table
makes of that description is part of its declaration — the view keeps passing
the full list:

```ruby
cols: {default: %w[booking_date signed_total_base_amount description],
       exclude: %w[kind top_up_sender],            # columns THIS table lacks
       labels:  {"party" => "Karteninhaber"}}      # ... and its own names
```

- **`exclude:`** removes those columns from the table completely: they are not
  offered in the picker, never rendered, and not part of the encoded `?c=` value.
  They are also out of the **allow-list**, so a hand-written `?c=` / `?s=` or a
  stale store entry that names one is dropped silently, exactly like an unknown
  token — the column simply does not exist on this table.
- **`labels:`** renames a column for this table alone: the header, the condensed
  header and the picker entry all follow.

Both take **long column keys** and are checked at **declaration time**: a key
that is not in the policy's codec — or a default column that is also excluded —
raises when the controller class loads, like every other declaration error.

Both may also be **lambdas**, evaluated on the controller per request like every
other request-dependent declaration value — that is how the Moss list serves its
five routes (the general tab plus one per kind) from one declaration, each tab
with its own columns. A lambda is checked when it is evaluated, with the same
errors.

The widget derives all of this from the state (`state.column_configs(configs)`,
`state.column_label(key, fallback)`), never from the view or the request.

**Row selection (remembered across pages).**

```haml
  - t.selection({
      name: "ids[]",                 # checkbox name (posted to the form)
      id_field: ->(r) { r.id },      # the checkbox value
      form: "my-form",               # id of the <form> the checkboxes belong to
      all_param: "select_all",       # (optional) enables "select all pages"
      total_count: rows.total_count,
      enabled: ->(r) { … },          # (optional) which rows are selectable
      row_data: ->(r) { { atom: …, amount: … } },   # (optional) data-* per row: `amount`
                                     #   (cents) feeds the selection sum, `atom` the
                                     #   all-pages quick-select
      remember_key: "mytable",       # sessionStorage key; the default derives from
                                     #   the state: "<state.store_key>:<prefix or
                                     #   id_prefix>", so two pages sharing a prefix
                                     #   don't collide
      filter_sig: "…",               # (optional) when this changes the remembered
                                     #   selection is cleared (default: state.wire(:filter))
    })
```

A leftmost checkbox column + a header "select page" box appear. The selection is
**remembered across paging / sorting / column changes** (sessionStorage) and
**cleared when the filter changes** — both defaults derive from the state, so
the selection follows the same per-page / per-row identity as the state itself.
With `all_param`, once a full page is selected a bar offers "select all rows of
the query (all pages)". On submit of the linked form, remembered ids that are
not on the current page are injected as hidden inputs, so a cross-page selection
posts completely.

`on_filter_change:` defaults to `:clear`. `:narrow` (keep the still-matching
rows) is reserved — passing it raises `NotImplementedError` for now.

**A filter.** Pass a `filter:` config. The filter occupies the two lines above
the table's toolbar: a framed **filter line** (presets, applied-filter chips,
and the pane's toggle at its right end) and, opening between that line and the
toolbar, the pane with the generic CNF filter builder
(`doc/wsjrdp/generic_filter_builder.md`) — see "The filter: a schema, fixed
slots, exclude (D2e)" for the layout:

```haml
  - t.filter apply_url: apply_path,          # POST target of the builder (PRG)
      condensed_locked: true,                # fixed conditions as a compact summary
      disabled: false,                       # true = read-only filter (no further input)
      presets: [{key:, label:, slots:,       # only when the POLICY declares none
                 icon:, css_class:}]         # ... last two optional, see "Presets"
```

Those are **display options — nothing else is passed** (`presets:` being the one
that carries content, and only for a host that would rather declare its
Schnellauswahl next to the table than in the policy; doing both raises). The
catalog, the applied user conditions, the pinned (`readonly`) slots and the wider
catalog that labels them, the presets' active state and toggle URLs, the pane's
open state and its cookie, the reset URL and the params an apply carries all come
from `state.filter`, i.e. from the controller's policy. `condensed_locked`
collapses the host-pinned conditions to one muted summary line (with a full-text
tooltip) while still allowing the user to add their own; `disabled` renders the
whole filter read-only (and hides the presets, which would apply at once).

The apply endpoint is generic too — one line in the controller:

```ruby
def apply = wsjrdp_apply_table_filter(booking_table_state, redirect_to: bookings_path)
```

`Wsjrdp::TableStateful#wsjrdp_apply_table_filter` encodes the posted tree through
`state.filter.encode_tree` (so the form passes the same allow-list as a URL),
drops this table's filter, page and open rows, carries every other param, and
always emits the filter param — blank when nothing survives, because a blank
param is what beats a remembered filter.

**Sub-rows: a row brings rows of its own.** A row may be several rows: the row
itself and, right below it, one **sub-row** per thing it consists of, in the
table's own columns. The kit knows nothing about what a sub-row is — the host
says which rows a row brings and what each of their cells shows:

```haml
  - t.sub_rows { |row| row.parts }                # nil / [] = this row has none
  - t.sub_cell { |sub, col| sub_cell_html(sub, col) }   # required with sub_rows
  - t.sub_row_class { |sub| "…" }                 # optional, on the sub-row's tr
  - t.group_class   { |row| "…" }                 # optional, on the group's tbody
```

`sub_cell` gets the sub-row and the **column description** the head cells get
(`col[:key]`, `col[:numeric]`, `col[:css_class]`, …), so one lambda serves every
column. Declaring `sub_rows` without `sub_cell` raises — the widget could not put
a sub-row into the table's columns without it.

Each row is rendered as one **group**, a `tbody.exp-group` of its own, holding in
this order the row's `tr.exp-row`, its `tr.exp-sub-row`s, and — when the table is
expandable — the `tr.exp-detail-row` as the group's LAST row, so the detail opens
under the whole group. A table that declares no sub-rows renders the same group,
just without the middle part. Inside a group the rows are separated by dashed
rules and the group ends with the table's normal solid one. The group is also the
unit under the pointer: hovering the head row or any of its sub-rows tints them
together (the detail row excluded).

A sub-row carries the row's `td.exp-col`s once more (as
`td.exp-col.exp-sub-col`, only the columns that are **visible**, so hiding a
column in the ☰ menu hides it in every row of the group), an empty
`td.bk-select-cell` where the table has a selection, and nothing else — no
detail and no links of the kit's own.

What it does carry, on an **expandable** table, is the head row's disclosure:
the same `role="button"`, `tabindex`, `data-bs-toggle="collapse"` and
`data-bs-target`, pointing at the group's ONE detail. So a click anywhere in the
group opens and closes that detail, and Bootstrap mirrors `aria-expanded` onto
every one of its triggers, the head row included. A table without a detail (and
without detail links) renders none of these attributes, on the head row and on
the sub-rows alike.

A link or a button the host puts INSIDE a row keeps its own click: for a click on
an `a`, `button`, `input`, `select`, `textarea`, `label` or the selection cell
inside an `.exp-row` / `.exp-sub-row`, the capture listener in
`shared/wsjrdp/_row_click_guard` takes the row's `data-bs-toggle` off for that
one dispatch, so Bootstrap's delegated data API does not find a trigger and the
detail stays as it is. Everything else about the click is untouched — the
control's own action runs, and so does a delegated handler the host has for it —
which is what lets a host's own link inside a sub-row do its work without
touching the detail.

Everything the table *computes* counts **parent rows only**: sorting, paging, the
filter, the selection, the summary and the open-rows param never see a sub-row,
and nothing about one reaches `Wsjrdp::ExpandableTableRows` or the state. A page
of 50 rows is 50 rows however many sub-rows they bring — which also means the
host must preload what its sub-rows read, or pay for it per row.

---

## 3. Namespacing: several tables on one page (`prefix`)

Every field is namespaced by the table's **prefix**, followed directly by the
field's one-character name (D2a). Single-character names cannot collide across
prefixes, which is why there is no separator:

| prefix | params | reset |
|---|---|---|
| `""` (default) | `s`, `c`, `f`, `z`, `p`, `o`, `e` | `r` |
| `"bk"` | `bks`, `bkc`, `bkf`, `bkz`, `bkp`, `bko`, `bke` | `bkr` |
| `"ae"` | `aes`, `aec`, `aef`, `aez`, `aep`, `aeo`, `aee` | `aer` |

`expandable_table_level` stands outside this scheme — it is shared, so it is
never prefixed and appears once per URL whatever tables the page carries (§4).

Page-wide, `table_state_reset` resets every table declared on the page.

Use `prefix: ""` when a page has a single table (keeps its URLs short); give a
prefix only when tables coexist. **Two tables of the same kind on one page are
two constants, two accessors and two names in the view** — there is no shared
"the page's bookings table". The reconciliation page is the example:

```ruby
BOOKINGS_POLICY = wsjrdp_expandable_table_policy prefix: "bk", …
ENTRIES_POLICY  = wsjrdp_expandable_table_policy prefix: "ae", …

def booking_table_state = wsjrdp_expandable_table_state(BOOKINGS_POLICY)
def entries_table_state = wsjrdp_expandable_table_state(ENTRIES_POLICY)

def bookings = @bookings ||= Wsjrdp::ExpandableTableRows.new(booking_table_state, …)
def entries  = @entries  ||= Wsjrdp::ExpandableTableRows.new(entries_table_state, …)
```

```haml
= render "fin/bookings/browser", rows: bookings, …
= wsjrdp_expandable_table do |t|
  - t.rows entries
```

Two tables with different prefixes **page / sort / filter independently**. The
prefix is the key of the controller's declaration *and* the namespace the widget
renders and links from, so the two halves always agree — `et_url` keeps every
OTHER param (including sibling tables') untouched, and `state.wire_params` gives
exactly the params the URL chose, for a redirect that has to reproduce the view
(`bookings.state.wire_params.merge(entries.state.wire_params)`).

Which of a page's tables a piece of code means is never a prefix string: each
host keeps its declarations in constants and resolves from them, and a foreign
piece of code that needs a table's param names asks that table's policy —
`Fin::MossTransactionsController::TRANSACTIONS_POLICY.param_name(:filter)` is how
the Moss overview's kind cards build their deep link.

---

## 4. Detail nesting: `Wsjrdp::TableContext` (lazy AND direct)

The same detail partial (a DATEV booking, a ledger account, …) is rendered both
on its own page and nested inside a table row — potentially several levels deep (a
Buchhaltung item detail embeds a bookings table, whose rows have their own
detail). `app/domain/wsjrdp/table_context.rb` makes the situation explicit:

```ruby
ctx.root?    # true on a dedicated page (level 0)
ctx.nested?  # true inside a table row's detail (level >= 1)
ctx.level    # 0 page · 1 a row's detail · 2 a table inside a detail · …
ctx.lazy?    # loaded into a turbo frame?
```

The widget hands a `Wsjrdp::TableContext` to a detail rendered **directly** (the
detail lambda may take `(row)` or `(row, ctx)`), and for a **lazy** detail it
appends the depth to the frame URL as `expandable_table_level`, which the target
controller resolves back into its own table's `state.level` — so a partial reads
its nesting the same way either way. It is the one param that is **not**
namespaced by the table prefix (`Wsjrdp::TableStatePolicy::SHARED_PARAMS`): the
table that WRITES it and the table that READS it live in different controllers
and generally carry different prefixes, so a namespaced name would leave the
reader at depth 0. One request carries one depth, so a single shared name stays
unambiguous — and since it is never concatenated with a prefix, it spells itself
out instead of being a cryptic letter in a URL that several tables share. A detail that embeds another table gets the
count going up through that table's `level:` policy option (see "Nesting" in
§1); the view threads nothing through. See `fin/bookings/_booking_detail` (takes
`table_context`) and `fin/shared/_item_detail` (rendered at level 0 as a page and
one level deeper inside the list's expandable row).

A finance detail built on the detail-partial kit reads its situation from a
`Fin::AttrFormatContext` instead, which wraps this context — a `(row, ctx)`
detail lambda hands it on as `Fin::AttrFormatContext.embedded(ctx)`, so `level` /
`nested?` / `lazy?` still answer the same (see
[`doc/fin/detail_partials.md`](../fin/detail_partials.md)).

---

## 5. Worked example A — the Buchungen list

Four partials, each with one job:

- `fin/bookings/_bookings_table` is the thin adapter onto the widget: the column
  config from `booking_table_columns(condensed:)`, the detail's header links
  (the booking's page, and "In Moss" for a booking that came from Moss), the
  inline `_booking_detail`, the count+sum summary. Its one
  required local is **`rows:`** — a bookings `Wsjrdp::ExpandableTableRows` — so
  the adapter needs no prefix and no state of its own (`t.rows rows, id: …`
  brings both). `condensed: true` switches to the compact in-detail variant
  (bare codes, the columns' `condensed_label`s, no picker).
- `fin/bookings/_browser` adds the filter and renders `_bookings_table`
  directly, passing only the filter's *display* options (`apply_url`,
  `condensed_locked`, `disabled`).
- `fin/bookings/_embedded` wraps the condensed variant with the "Buchungen"
  heading, the totals line and the "open in the bookings view" button, for the
  Buchhaltung detail views.
- `fin/shared/_item_detail` puts an item's metadata fields above that embedded
  table (`item_bookings:`), and is what `bookkeeping_item_detail` renders both
  inline and on the dedicated page.

`Fin::BookingsController` declares the page in one block: `prefix: ""`, the
`Fin::DatevBookingsColumns` codec, the default sort and columns, `per_page: 50`,
`filter: {policy: :remember, schema: Fin::DatevBookingsFilterSchema, exclude:
EXCLUDED_FILTER_ATTRIBUTES}` and `pane: {default: 1}`. Because the filter is
`:remember`, coming back through the tab lands on the last view; the filter's
"Filter zurücksetzen" (`?f=`, no default declared) clears the remembered filter,
and only the filter.

There is no shared filtering concern: each host writes the same two or three
plain methods and its own `helper_method` line.

```ruby
def booking_table_state = wsjrdp_expandable_table_state(BOOKINGS_POLICY)

def bookings
  @bookings ||= Wsjrdp::ExpandableTableRows.new(booking_table_state,
    booking_table_state.filter.scope(DatevBooking.all),
    sort: Fin::DatevBookingsColumns.sort_expressions,
    sum: :signed_base_amount, preload: :batch)
end
```

Nothing there decodes, validates, compiles or joins by hand: `filter.scope` is
the only way to the relation, and the `left_joins(:batch)` the batch-backed
attributes and the Primanota-Periode sort need comes from the schema's own base
relation. On the reconciliation page the same table is declared again as that
controller's own `BOOKINGS_POLICY`, with `prefix: "bk"` and its own fixed slots;
its `filtered_scope` is the same one-liner.

`Fin::MossTransactionsController` is the same shape for
`fin/moss_transactions/index` — one table with `prefix: ""`, a remembered filter
(`schema: Fin::MossTransactionsFilterSchema`), no excluded attributes, and one
extra step: because the Moss schema LEFT JOINs expenses and bookings, the
controller's `distinct_transactions` re-selects the matching ids so the sort and
the paging see one row per transaction.

## 6. Worked example B — the reconciliation page

`fin/reconciliation/participant_fees` renders **two** tables through the widget,
both declared in `Fin::ReconciliationController`:

- the **bookings** table (`prefix "bk"`) via `_browser`, whose filter is pinned
  by `LOCKED_FILTER_TREE` as a `show: :readonly` fixed slot (shown condensed,
  parsed strictly and compiled by `state.filter.scope`, not merely displayed),
  with `EXCLUDED_FILTER_ATTRIBUTES` removed from the picker, an injected
  match-proposal column (`t.columns …, extra:`), row selection, and a candidate
  list in each row's detail (`t.detail_top`). Its filter stays `:url`, so the
  page always shows what its link says;
- the **entries** table (`prefix "ae"`, columns and sort allow-list both from
  `Fin::AccountingEntriesColumns`) rendered through `wsjrdp_expandable_table`
  directly, with the reverse match-proposal column, its own selection and
  candidate list. It declares **no sort default**: an empty `sort_list` is its
  natural "proposals first" order, which it hands the rows object as its
  `natural_order:` (plus `tiebreaker: "accounting_entries.id DESC"`), so no
  header carries an arrow until the user picks a sort.

The view names each table once (`rows: bookings`, `t.rows entries`) and reads
`bookings.state` / `entries.state` where it needs the state itself. Both tables
share `fin/reconciliation/_connect_controls` (the "Auswahl verbinden" button +
per-tier quick-select + the count/sum confirm), which drives whichever
`.bk-select-scope` its `form_id` points at. Because the prefixes differ, the two
tables page, sort and select **independently**; the connect actions return to the
same view by re-emitting both `wire_params`.

---

## 7. Full local reference

These are the locals of `shared/wsjrdp/_expandable_table` itself; the builder
method that sets each one is in brackets.

| local | meaning |
|---|---|
| `state` | the controller-resolved `Wsjrdp::TableState` (**required**) [`t.state`, or `t.rows` from the rows object]: param namespace, sort, visible columns, page size, page, open rows, the parsed filter (catalog, user conditions, pinned slots, `scope`), pane, nesting level |
| `rows` | the collection to render — already the ordered current page [`t.data`, or `t.rows` from `rows.page`] |
| `pagination` | the paged collection the page links describe (defaults to `rows`) [`t.data(…, pagination:)`] |
| `columns` | column configs (required) — the FULL set when `columns_menu` [`t.columns`] |
| `columns_menu` | the column hamburger [`t.columns …, menu: true`] |
| `extra_columns` | injected columns appended after the menu-managed ones, never in the picker [`t.columns …, extra:`] |
| `row_key` | `->(row){ String }` unique key [`t.row_key`] |
| `detail` / `detail_src` | inline (server) or lazy (turbo frame) detail [`t.detail` / `t.detail_src`] |
| `detail_top` / `detail_extra` | `->(row){ html }` injected at the top / bottom of each detail [`t.detail_top` / `t.detail_extra`] |
| `detail_page` | `->(row){ path }` the primary "Detailseite" double link of the detail's header line, rightmost in it [`t.detail_page`] |
| `detail_links` | `[{label:, icon:, title:, title_new_tab:, url: ->(row){ url }}]` further double links, LEFT of the primary one and in declaration order; a `nil` URL renders no group for that row (§2) [`t.detail_link`, once per link] |
| `row_class` | `->(row){ css }` extra class on the row [`t.row_class`] |
| `sub_rows` | `->(row){ [sub, …] }` the rows this row brings with it, drawn right after it inside the same `tbody.exp-group`; `nil` / `[]` = none (§2) [`t.sub_rows`] |
| `sub_cell` | `->(sub, col){ html }` one sub-row cell, `col` being the same column description the head cells get; **required** as soon as `sub_rows` is declared [`t.sub_cell`] |
| `sub_row_class` | `->(sub){ css }` extra class on a sub-row's `tr` [`t.sub_row_class`] |
| `group_class` | `->(row){ css }` extra class on the row's `tbody.exp-group` [`t.group_class`] |
| `id_prefix` | DOM id prefix (default: the state's prefix, else `"exp"`) [`t.rows`/`t.state` `id:`] |
| `multi_sort` | `true` (default): multi-column sort; `false`: single-column sort on the same RISON infrastructure (§2) [`t.sort multi:`] |
| `per_options` | set by `t.paging`, so its presence **is** "this table has paging": the page-size steps (`:all` = "Alle"), defaulting to `Wsjrdp::ExpandableTableBuilder::DEFAULT_PER_OPTIONS` [`t.paging`] |
| `summary` | a summary line (HTML) [`t.summary`] |
| `selection` | row selection config (§2) [`t.selection`] |
| `filter` | filter builder DISPLAY config: `apply_url`, `condensed_locked`, `disabled`, plus `presets` when the view rather than the policy declares them (§2) — everything else comes from `state.filter`. Renders the filter line (presets, applied-filter chips, the pane's toggle) and, between it and the toolbar, the pane [`t.filter`] |
| `condensed` | compact in-detail variant [`t.condensed`]. The kit supplies only the generic behaviour of such a table (content-sized columns, no wrapping, tighter cells); the column widths and which column wraps are the dataset's own and are declared in a styles partial next to its table — for the bookings, `fin/bookings/_condensed_styles` |

Everything else — the prefix, the default sort / page size / column set, the open
keys, the open param, the detail level, and the filter's catalog and value —
comes from `state` rather than from a local. `multi_sort` is a local because it
is a display option, not state.

**All three Buchhaltung summaries — Sachkonten, Kostenstellen and Kreditoren —
are relation-backed, because they filter.**
`WsjrdpLedgerAccount.with_booking_summary`,
`WsjrdpCostCenter.with_booking_summary` and
`WsjrdpPersonalAccount.with_booking_summary` put the booking totals into the
relation as real columns (a derived table over the bookings, `LEFT JOIN`ed so an
account / a cost center without bookings still appears), which is what makes
them filterable, sortable and summable in SQL:

```ruby
def personal_accounts
  @personal_accounts ||= Wsjrdp::ExpandableTableRows.new(summary_table_state,
    summary_table_state.filter.scope(WsjrdpPersonalAccount.with_booking_summary),
    sort: Fin::BookkeepingSummaryColumns::PERSONAL_ACCOUNTS.sort_expressions,
    sum: :booking_balance, tiebreaker: :number)
end
```

The Kreditoren declare their own `filter: {policy:
:remember, schema: Fin::PersonalAccountsFilterSchema, presets: PRESETS}` and a
`pane: {default: 1}`, the view passes only `t.filter apply_url:
apply_personal_accounts_path`, and a one-line `#apply` action makes the builder's
POST a PRG. The footer counts the **filtered** relation
(`personal_accounts.total_count` Kreditoren, plus the controller's
`SUM(booking_count)` bookings — deliberately no EUR total). The two presets
("Nur mit Saldo ≠ 0", "Nur mit Buchungen") are the worked example of the
section above.

The Kostenstellen page is built the same way over
`Fin::CostCentersFilterSchema`, with one preset ("Nur mit Buchungen") and a
footer that adds the EUR sum of the filtered set. It is also the worked example
of a **hidden fixed slot**: `fixed: [{slots: [[["number", "not_in", …]]], show:
:hidden}]` pins one cost center out of the list, which keeps it out of the rows
and out of the footer totals — both read the same
`state.filter.scope(...)` relation — while never appearing as a chip or in the
URL. Its `number` attribute is declared `catalog: false`, so the slot has a
column to compile against without the picker offering it.

Its Saldo is **one picker entry with two variants**: `booking_balance_abs`
("|Saldo|", an `ABS()` column) is declared first and is therefore the default,
`booking_balance` ("Saldo") second. The magnitude leads because a creditor's
balance is negative as often as positive — `|Saldo| ≥ 100` finds the big ones on
either side, `Saldo ≥ 100` only one — and that is what turned "Nur mit Saldo
≠ 0" from an OR over both signs into a single condition.

All these pages leave row selection off — the Buchungen and reconciliation tables
exercise that.
