# Plan: table state handling for `expandable_table`

Status: **executed** on 2026-09-05 against the development environment only —
see the [Execution record](#execution-record) for the commits, the verification
and the open follow-ups.

## Goal

One model for the per-table UI state (sort, columns, filter, page size, page,
open rows) that

- can be reset,
- lets the **controller** decide where each piece is stored (URL, session,
  DB, cookie, …) — the view, the widget and the builder never touch storage,
- supports several tables per page, several of the same type, and tables
  nested in a detail view (recursively), with explicit keys per level,
- lets the controller **fix** parts of the state so that the view renders
  them and a user cannot override them via URL or any other channel.

Out of scope: the row *selection* (checkboxes) stays client-side
(sessionStorage, posted with its form) and is not a state field.

## Decisions

### D1 — Three layers: transport, policy, resolved state

- **Every change travels as a request to the controller.** A header click, the
  column picker, a filter apply or a page link produces a GET with a namespaced
  param `<prefix><short>` (D2a; the filter builder POSTs and is redirected). The
  widget only *emits* those links and forms; it never reads `params`, `session`,
  cookies or any store. The URL builders (`et_url`, `et_carry_params`) keep
  merging `request.query_parameters` so a generated link carries sibling state
  along — link construction, not state resolution, and never trusted there.
  *Why:* keeps the widget storage-agnostic.
- **Policy per table and per field, declared in the controller** (one line
  each): `:url` (the value lives in the URL, nothing remembered), `:remember`
  (the URL carries it, the store mirrors the last value and restores it when the
  param is absent), `:fixed` (value given by the controller, params and store
  ignored, widget renders it read-only). Stores are pluggable (D7). *Why:* one
  widget then serves "shareable URL", "memory" and "locked" without a view
  change. A `:store_only` variant (absorb into the store, redirect to a clean
  URL) is deliberately not offered: an extra redirect per click, and links that
  no longer reproduce the view.
- **Resolution order per field:** `fixed` › URL param › store › default, in the
  one place that does it (`Wsjrdp::TableState::Resolver`). A param that is
  *present but blank* (`?f=`) is an explicit "empty" and beats the store; only an
  *absent* param falls through to the remembered value — otherwise the column
  picker's "Standard-Spalten" link and an emptied filter could not undo a
  remembered value. Defaults are part of the policy
  (`sort: {default: [["booking_date", "desc"]]}`, `per_page: {default: 50}`),
  never of the view.
- **The resolved state is a frozen value object** (`Wsjrdp::TableState`: sort
  list, column states, the parsed filter, page size, page, open keys, pane,
  level, plus `fixed?(field)` and `wire(field)`). The controller builds it once
  per request, builds the table's `Wsjrdp::ExpandableTableRows` from it and
  exposes **that** under a name of its own; the view hands the rows object to
  `t.rows`, which sets both halves the widget needs (`rows.state` and
  `rows.page`). `state.wire_params` re-emits exactly the params the URL chose,
  for a redirect that has to reproduce a view (the reconciliation connect
  actions): fixed fields are re-fixed by the controller, remembered ones restore
  themselves. *Why:* the view can only render what the controller resolved — the
  security requirement (D8) falls out of the structure instead of being a
  convention.

### D2 — Keys

- A table's key is its **prefix** (`""`, `"bk"`, `"ae"`, `"b"`).
- The **store key** is `<controller_path>#<action>` plus the prefix by default
  (`Wsjrdp::TableStatePolicy#store_key_for`), so two tables on one page never
  share memory. The controller may pass an explicit `store_key:` (String or
  lambda) so that several actions or a nested table share — or deliberately do
  not share — memory.
- **Nested tables** (a table inside a detail row) are separate requests when
  lazy-loaded (turbo frame) and share the parent request when inline. Either way
  they get their own explicit prefix per level; nothing is inherited implicitly.
- **Nested tables remember per row.** The embedded bookings table's `store_key:`
  lambda folds the detail's own row param into the key
  (`"#{controller_path}##{action_name}:#{params[row_param]}"`), so two cost
  centers keep separate sort/column memory for their embedded bookings tables.
  *Why:* user decision; the embedded view of one item is looked at as that item's
  view, not as a global preference. Consequence: the store grows with every
  opened row — the session store keeps a bounded number of keys per controller
  and drops the oldest
  (`Wsjrdp::TableStateStore::Session::MAX_KEYS_PER_CONTROLLER`, 50).
- The remembered row **selection** (sessionStorage, out of scope as state)
  derives its key from `"<state.store_key>:<prefix or id_prefix>"`, so it follows
  the same per-page / per-row identity as the state itself instead of a
  hand-written string.

### D2a — Fields and their query-param names

A query param is `<prefix><short>`: the prefix followed directly by a
**one-character** field name (no underscore). Prefix `""` gives bare letters
(`?s=bez,nr~&c=nr,~bez&p=2`), prefix `bk` gives `bks`, `bkc`, `bkp`, …
Single-character names cannot collide across prefixes: `P1 + x == P2 + y`
forces `P1 == P2`. *Why:* shorter URLs.

| field | short | value on the wire | reader on the state | default policy |
|---|---|---|---|---|
| `sort` | `s` | RISON list `bez,nr~` (`~` = descending, first = primary) | `state.sort_list` → `[[key, dir], …]` | `:remember` |
| `cols` | `c` | `nr,~bez,sum` (`~` = hidden), order = display order | `state.column_states` / `state.visible_column_keys` | `:remember` |
| `filter` | `f` | Rison CNF tree, the **user** part only | `state.filter` → a parsed `Wsjrdp::TableState::Filter` (D2e) | `:url` |
| `per_page` | `z` | integer or `all` | `state.per_page` → `Integer` or the symbol `:all`; `state.per_value` is the wire form | `:remember` |
| `page` | `p` | integer | `state.page`, applied by `state.paginate` (D4) | `:remember` |
| `open` | `o` | comma list of row keys | `state.open_keys` (a Set) | `:url`, never remembered (D4) |
| `level` | `expandable_table_level` | integer (nesting depth of a lazy detail) | `state.level` | `:url`, never remembered, never prefixed |
| `pane` | `e` | `1` / `0` | `state.pane` | `:remember`, store `:cookie` |

`Wsjrdp::TableStatePolicy::FIELD_DEFINITIONS` is that table in code: adding a
field means adding one row there, and the letter must stay unique. Two params are
commands, not state (D3): `<prefix>r` resets that table, `table_state_reset`
(`PAGE_RESET_PARAM`, its value ignored) every table of the page.

### D2b — Long names in code, short names on the wire

Everything a developer writes — policy defaults, fixed values, the state's
readers, what the rows object receives — uses the **long** names: column keys
(`booking_date`), attribute keys. The one-letter field names and the column
`abbr` tokens exist only on the wire (URL params) and in the stores.

A dataset's columns are described **once**, in a `Wsjrdp::ExpandableTableColumns`
collection of `Wsjrdp::ExpandableTableColumn` descriptions (one module per
dataset: `Fin::DatevBookingsColumns`, `Fin::MossTransactionsColumns`,
`Fin::AccountingEntriesColumns`, `Fin::BookkeepingSummaryColumns`). The three
consumers derive their view of it:

```ruby
BOOKINGS_POLICY = wsjrdp_expandable_table_policy prefix: "",
  columns: Fin::DatevBookingsColumns.codec,        # key => abbr, both directions
  sort:    {default: [["booking_date", "desc"]]},
  cols:    {default: Fin::DatevBookingsColumns.default_keys}
```

- the **policy** takes `codec` — which doubles as the allow-list of the `?c=` and
  `?s=` params (D8.5) — and `default_keys`;
- the **rows object** takes `sort_expressions`, the `ORDER BY` allow-list (an SQL
  String per column for a relation-backed table, a `->(row){ comparable }`
  extractor for an array-backed one);
- the **rendering helper** maps each description to the widget's column Hash
  through `#to_table_column(cell:)`, adding only the cell.

*Why:* code stays greppable and readable; a renamed abbreviation touches one
description, not every controller, and the three views of a column cannot drift
apart because there is only one list.

**One description, several tables.** A dataset keeps ONE description even when
two tables show it differently: the policy's `cols:` field shapes that
description per table. `exclude:` names the columns THIS table does not have —
they are not offered in the column picker, never rendered, not part of the
encoded `c` value, and out of the codec's ALLOW-LIST as well, so a hand-written
`?c=` / `?s=` or a stale store entry naming one is dropped silently like an
unknown token. `labels:` gives a column a name for this table alone (header,
condensed header and picker entry alike). Both take long keys, and both may be
lambdas — that is how the Moss list serves its five routes from one declaration,
each kind tab with its own columns — so the shaped set is a per-request value
(`TableState::ColumnSet`), never state on the shared, frozen policy. The
validation is the same either way: a key that is not in the codec, or a default
column that is also excluded, raises when the controller class loads, or when the
lambda is evaluated. The view does not change — it keeps passing the full column
list, and the widget takes the effective set and the labels from the state
(`TableState#column_configs`, `#column_label`), never from params or the view.

### D2c — Names: declaration vs. resolved state

Two things exist per table, and they are different in kind:

1. the **declaration** (policy): static per controller/action — which tables the
   page has, their prefixes, defaults, what is fixed, which store. It is written
   **once at class level**, like `before_action`, `layout`, `rescue_from`,
   Kaminari's `paginates_per` or hitobito's `self.sort_mappings`. Class level is
   needed because the reset `before_action` (D3) must know every table of the
   page *before* the action runs. Values that depend on the request (a nested
   store key from `params[:number]`, a fixed filter value from the path) are
   given as lambdas and evaluated on the controller instance.
2. the **resolved state**: computed per request from declaration + params +
   store (D1), memoised, frozen, and exposed to the view by the **host**, under a
   name of its own choosing.

This "class-level declaration declares, instance method resolves" split is the
standard Rails shape (`has_many :posts` → `posts`, `paginates_per 25` →
`default_per_page`, `layout` → `_layout`); the two halves conventionally have
**different names**. The declaration `wsjrdp_expandable_table_policy prefix: "bk", …`
**returns the policy object**, the host keeps it in a **constant**, and the
resolved state is `wsjrdp_expandable_table_state(BOOKINGS_POLICY)` — the object
is the link, so a table's prefix is written exactly **once**:

```ruby
class Fin::ReconciliationController < Fin::FinController
  include Wsjrdp::TableStateful

  BOOKINGS_POLICY = wsjrdp_expandable_table_policy prefix: "bk", …
  ENTRIES_POLICY  = wsjrdp_expandable_table_policy prefix: "ae", …

  def booking_table_state = wsjrdp_expandable_table_state(BOOKINGS_POLICY)
  def entries_table_state = wsjrdp_expandable_table_state(ENTRIES_POLICY)
end
```

- `wsjrdp_expandable_table_state` takes the policy **positionally** and checks it
  by IDENTITY against the tables declared on that controller: another
  controller's policy, or one whose prefix a later declaration took over, raises
  an `ArgumentError` instead of resolving against the wrong table.
- The prefix-keyed registry (`wsjrdp_expandable_table_policies`) exists, but is
  **private to the concern**: the page-wide reset and
  `spec/controllers/fin/table_policies_spec.rb` need to enumerate a page's
  tables; nothing else looks a table up by its prefix.
- There is **no** `helper_method :wsjrdp_expandable_table_state`. A view never
  resolves a state; it reads the rows object its host exposes (`t.rows`, D1).

**Every table is declared by its own controller**, and no concern owns one: a
shared concern cannot know which of a page's tables is "its" listing, and a class
attribute pointing back at one of the host's own tables is the signal that the
concern does not belong to a table at all. `Fin::BookkeepingSummaries` therefore
keeps the shared summary *logic* (`summary_rows`, `item_bookings`,
`leg_summaries`, the totals, `render_item_detail`) but **declares nothing**: it
offers `summary_policy_options(columns)` and
`item_bookings_policy_options(row_param:, nested:)`, and each of the four
Buchhaltung controllers writes its own `SUMMARY_POLICY` / `ITEM_BOOKINGS_POLICY`
and the matching one-line state accessors. `nested: true` says "this table sits
inside a summary list's detail row" and adds the `level:` lambda that inherits
the depth the list put into the detail's frame URL; the Buchungsstapel page has
no summary list, omits `nested:` and starts at level 0. *Why:* a shared option
hash must not assume a method its host may not have, and naming the condition
also names the precondition of the lambda.

### D2d — Store selection

The declaration takes a `store:` (default `:session`); a field may override it
(`filter: {policy: :remember, store: :db}`) once a second general store exists. A
bare symbol (`filter: :remember`) is shorthand for `{policy: :remember}`.

The stores today are `:session` (D7) and `:cookie`; the store registry maps the
symbol to an object implementing the D7 interface. *Why:* the controller, not the
widget, decides where each piece lives — including mixed combinations per table.

The cookie store is for tiny UI-chrome values the browser may change **without a
request**: the widget writes `document.cookie` directly (the name comes from
`state.cookie_name(:pane)` and travels to the JS as a `data-` attribute), and the
controller reads it on the next render through the same resolver and allow-list
as any other input. Only single-token values (`1`/`0`, a short enum) may use it.

**Caveat, documented with the API:** a `:cookie` value does **not** always travel
through a request — the browser changes it on its own and the server only learns
about it on the next render — and a cookie is client-controlled (editable in the
browser). `:cookie` must therefore never be chosen for anything sensitive, for
anything that influences the row set or the scope, or wherever the controller's
primacy over the value matters. It is for pure display chrome (`pane` is the only
use today), and only for tables with a **static** store key: it has no key cap,
so a per-row nested table (D2) would mint one cookie per opened row and run into
the browser's per-domain cookie limit.

### D2e — The filter: a declared schema, fixed slots, exclude

`:fixed` is all-or-nothing for every field except `filter`, where the controller
can fix **slots** while leaving the rest to the user — and the filter is also the
one field that has to know **which dataset** it filters:

```ruby
filter: {policy: :url,
         schema: Fin::DatevBookingsFilterSchema,                 # the dataset (mandatory)
         fixed: [{slots: LOCKED_FILTER_TREE, show: :readonly},    # rendered, not editable
                 {slots: HIDDEN_TREE, show: :hidden}],            # never rendered
         exclude: EXCLUDED_FILTER_ATTRIBUTES,                     # not offered in the picker
         default: [[["konto", "in", "41030"]]]}                   # user tree, if nothing chosen
```

- **`schema:`** is a module extending `Wsjrdp::Filtering::FilterSchema`: it
  answers `bound(except:)`, `decode`, `encode`, `encode_tree`, `parse_fixed!` and
  `compile`. It comes **only from this class-level declaration** — never from a
  param, the store or a cookie — and is mandatory as soon as any other filter
  option is declared (`ArgumentError` at declaration otherwise). A table that
  declares no `filter:` at all gets an **inert** filter: no catalog, no user
  query, `scope` hands its argument straight back.
- **The resolver parses everything**, once per request, binding the schema twice
  (lazily per resolve, never at class load):
  - the **full** schema for the fixed slots → `parse_fixed!`, **STRICT**: an
    unknown attribute or operator, a wrong operand count, an operand that does
    not cast, or a blank/malformed tree raises an `ArgumentError` naming
    attribute, operator and slot index;
  - the schema **reduced by `exclude:`** for the user part → `decode`,
    **TOLERANT**, applied to the URL value *and* the store value alike, so an
    excluded attribute is dropped on either path.
- The effective filter is `fixed slots AND user slots` (CNF, so fixed slots are
  simply conjoined ahead of the user's and the user part can only narrow).
- `show: :readonly` slots appear in the builder as locked chips (condensed or
  full, a display option); `show: :hidden` slots never reach the view. Display
  visibility never influences enforcement.
- `exclude:` removes attributes from the user's catalog. A readonly fixed slot
  may use an excluded attribute; the widget labels it from `filter.full_catalog`.
- `default:` is the user tree shown when neither the param nor the store provided
  one. Host-authored, so parsed strictly too — against the *reduced* schema,
  since it IS the user part. It applies only on the `:default` path: a
  present-but-blank `?f=` and anything in the store beat it.
- **`presets:`** are named slot lists (`{key:, label:, slots:}`) offered as
  one-click toggles in the filter line above the pane ("Schnellauswahl").
  Alternatively the view declares them (`t.filter presets:`); **both at once
  raises**, naming
  the table. They are host-authored, so parsed strictly — against the *reduced*
  schema, because they are shortcuts INTO the user part, not pins: a toggle
  writes the resulting user tree into `?f=` and applies at once (a GET link,
  page and open rows dropped as for any filter change). A preset is **active**
  when every one of its slots is present in the APPLIED user filter under exact
  slot equality — the same SET of conditions, order irrelevant, operands
  compared canonically, and an OR-widened slot deliberately NOT counting, since
  an added OR widens what the preset promised. That rule lives in ONE place
  (`Wsjrdp::Filtering::SlotEquality`), the state exposes it as
  `filter.presets` → `TableState::FilterPreset` (`key`, `label`, `slots`,
  `active?`, `toggle_wire`), and the builder's JS repeats it only for the
  cosmetic marking of a preset's slot. Overlapping presets follow from slot
  semantics and are not special-cased. While the builder has unapplied edits
  every toggle is locked (`aria-disabled`, no `href`) — a preset applies at
  once, which would otherwise throw those edits away.
- **The state carries the parsed halves**, not strings: `schema`,
  `fixed_entries`, `fixed_slots`, `readonly_slots`, `hidden_slots`, `user_query`,
  `user_slots`, `effective_slots`, `exclude`, `catalog`, `full_catalog`, `wire`,
  `encode_tree(tree)`, `fixed?` and `scope(base)`. The URL param `f` and the store
  only ever hold the **user** part, canonically encoded. `policy: :fixed` means
  "fixed slots only, no user part".
- **Enforcement is `filter.scope(base)` — the only way from a filter to a
  relation** (D8.3): fixed slots compiled with the full schema, the user query
  with the reduced one on top; both compiles merge the schema's own base
  relation, so the joins the attributes need (the bookings' `left_joins(:batch)`,
  the Moss expenses/bookings joins) are never a host's business.

*Why the schema:* `Wsjrdp::Filtering::Compiler` is deliberately
neutral-on-invalid, which is right for user input and wrong for host input — a
typo in a fixed slot, or an attribute later removed from the schema, would
silently drop the pin and widen the page scope. Naming the dataset in the policy
is what lets the resolver tell the two apart and apply the right strictness to
each, and it makes `exclude:` a property of the construction instead of every
host remembering to pass `except:`.

### D3 — Reset

- Per table: `?<prefix>r=1` clears the store for that key and redirects to the
  current URL without any of that table's params.
- Page-wide: the param key `table_state_reset` (no prefix, no short name; its
  value is ignored) does the same for every table registered on the page. A bare
  `r` cannot serve page-wide because it is the reset of the table with prefix
  `""`.
- Fixed fields are unaffected by either: they are never stored and are re-fixed
  by the policy on the next render.
- **Neither reset command has a control in the UI.** The filter builder has two
  controls of its own, both **filter-only**: "Änderungen verwerfen" (shown only
  while the builder differs from the applied filter; restores the applied
  filter client-side, no request) and "Filter zurücksetzen"
  (`et_filter_reset_url(state)`: this table's filter param set to the policy's
  `default:` tree in wire form, `state.filter.default_wire`, or explicitly
  **blank** — `?f=` / `?bkf=` — when no default is declared; page and open rows
  dropped (D4); sort, columns, page size, the sibling tables and non-table params
  untouched). Nothing in the builder applies on its own — not even removing a
  condition or a slot; while there are unapplied edits, a warning chip, a badge
  on the filter toggle in the filter line and a highlighted "Anwenden" say so.
  *Why:* a user who clears
  a filter wants the rows back, not their column layout and page size thrown
  away; and an edit that applies itself is a surprise with no way to undo it.
  Present rather than absent because a present param beats the store (D1) —
  dropping it would restore the just-cleared filter on the remembering pages.
  `et_reset_url` stays as the one place that knows how to build a whole-table
  reset URL and says in its comment that nothing calls it.

### D4 — Remembered page and page size, transient open rows

`page` is remembered like the rest; a remembered page beyond the current last
page falls back to page 1. *Why:* coming back through the tab lands where one
left, without the failure mode of an empty page.

The clamp needs the row count, which the resolver does not have, so it lives in
**`Wsjrdp::TableState#paginate(source)`** — the one method every table pages
through (`Wsjrdp::ExpandableTableRows#page` calls it; no host repeats the
`page`/`per`/`out_of_range?` dance). `source` is a relation or a plain Array
(wrapped in `Kaminari.paginate_array`), page and page size come from the state,
and Kaminari's `out_of_range?` answers the clamp for both kinds of source.
`paginate` is also where `per_page == :all` becomes "one page with everything",
so the big-number limit behind `:all` stays private to `Wsjrdp::TableState`.

The **page-size select is always available**: rendered whenever a table has
paging and its size is not `:fixed`, including when everything fits on one page.
*Why:* it is the only way back to a smaller size (or forward to "Alle"), so it
must not vanish the moment it took effect — and what the widget renders must not
depend on where a value came from.

`open` is `:url` only and never stored. Toggling a row writes `o` into the URL
via `history.replaceState` (no request — one of the two deliberate exceptions to
D1, the other being the cookie-stored `pane`; both are harmless because they
never touch the row set). Required behaviour:

- a browser reload keeps the open rows (the URL carries `o`);
- a filter, page or page-size change closes all rows: `et_url` drops `o`
  whenever it changes `f`, `p` or `z`, the paging links pass
  `params: {<prefix>o => nil}`, and the filter apply drops it too;
- a sort or column change keeps them (same rows, different order/columns);
- leaving the page and coming back starts with all rows closed.

Open keys that are not on the rendered page are ignored, and their number is
bounded so a hand-written URL cannot grow without limit.

### D5 — Precedents and conventions

The shape "controller resolves params (+ memory) into an object, the view
renders and links from that object" is the established Rails pattern:
Ransack (`@q = Model.ransack(params[:q])` → `sort_link(@q, …)`), Pagy
(`@pagy` → `pagy_nav(@pagy)`), Administrate (`Order` built in the
controller), and Redmine's `SortHelper` (`sort_init`/`sort_update` in the
controller read `params[:sort]` or the session and write the session; the
view only calls `sort_header_tag`). Redmine also remembers the last query in
the session on GET, so "GET updates memory" has a long-standing precedent.
Hitobito core itself is looser (its `sort_header` reads `params[:sort]` in
the view); this plan is stricter than core, not in conflict with it.
Security-wise it matches the Rails trust boundary: params are untrusted
input, allow-listed in the controller; the view never widens what the
controller resolved. Hitobito's session store is `active_record_store`, so
remembered state does not hit the 4 KB cookie limit, but each remembered value
still costs a session-row write on first change — keep the per-table footprint
small (tokens, not trees).

### D6 — Default policy

When the controller says nothing: `sort`, `cols`, `per_page` and `page` are
`:remember`; `filter` and `open` are `:url`. `open` and `level` can never be
remembered (`Wsjrdp::TableStatePolicy::NEVER_REMEMBERED`) — declaring them
`:remember` raises. A controller opts in per field (`filter: :remember`), opts
out (`sort: :url`) or fixes it (`filter: :fixed`). *Why:* a remembered filter is
the least visible piece of state, so it stays in the URL unless a host (the
Buchungen and the Moss transactions list) turns memory on explicitly.

**Do not declare a default that the query then overrides.** The header arrows are
rendered straight from the resolved sort list, so a declared sort default that
something else re-orders puts a misleading arrow on a column the table is not
sorted by. An order no column sort can express is the empty-`sort_list` case
instead: the rows object takes it as `natural_order:` (the reconciliation entries
table declares no sort default and puts its match proposals first that way).
Without a `natural_order:`, a **relation** falls back to its `tiebreaker:` and an
**Array** keeps the order it arrived in — an array comes pre-ordered from its own
SQL query, and re-sorting it in Ruby would apply a different collation than that
query did, so "leave it alone" is the honest natural order.

### D7 — Stores: session (and cookie)

Session (`active_record_store`) is the general store, the cookie store (D2d) the
special case for JS-written chrome; the store interface — `read(key)`,
`write(key, hash)`, `delete(key)`, `delete_all(key_prefix)` — is what a later
per-person DB store implements. `write` **replaces** the entry in both stores (an
empty hash removes it).

**Only non-default values are stored.** After resolving, the resolver compares
each `:remember` field's resolved wire value against the same table with nothing
chosen and drops the ones that are equal, so "remembered" means "differs from the
default" and the session stays small. The store entry is written even when
*nothing* differs any more, so an explicit "back to default" replaces the old
entry instead of leaving it behind.

*Why:* smallest first step, no schema; persistence across logout/devices is added
when it is missed.

### D8 — Security: a fixed field cannot be overridden

The guarantee is structural, not a UI convention:

1. **One resolver, one order.**
   `Wsjrdp::TableState.resolve(policy, params:, stores:, controller:)` is the
   only place that turns input into state. For a `:fixed` field (or a fixed
   filter slot, D2e) it takes the value from the policy and **does not look at**
   the param or the store at all — there is no code path from user input to a
   fixed field, so there is nothing to bypass.
2. **The state object is frozen.** It is a value object built once per request in
   the controller; the view, the builder and the helpers receive it read-only and
   cannot replace or mutate a field.
3. **Enforcement happens in the data path, not only in the display.**
   `Wsjrdp::ExpandableTableRows` receives the *state*, not `params`: a fixed sort
   is the `ORDER BY`, and fixed filter slots are compiled into the scope by
   `state.filter.scope`. Whether a fixed slot is shown (`show: :readonly`) or not
   (`show: :hidden`) never influences enforcement. A hand-edited URL therefore
   changes neither the rows nor their order, whatever the widget shows.
4. **Widget and helpers read no request state.** Sort list, column states, page
   size, open keys and the parsed filter are readers on the state object, and the
   partials get the state through the builder.
   `spec/domain/wsjrdp/expandable_table_state_guard_spec.rb` greps every
   `app/views/shared/wsjrdp/**/*.haml` partial and
   `Wsjrdp::ExpandableTableHelper` for `params[`, `session[`, `cookies[` and
   `request.` and fails on any hit; it additionally tracks which method a
   `request.` use sits in and allows it only in `et_carry_params` /
   `et_current_path` (link construction). Widening that list needs a plan change,
   which is the point.
5. **Allow-lists on both read paths.** Values from the URL *and* from the store
   pass the same allow-lists: sort and column tokens against the policy's
   `columns:` codec, a sort key again against the rows object's `sort:` map,
   filter attributes and operators against the bound schema, `per_page` capped
   (`max:`), open keys bounded. A poisoned or stale store entry is therefore no
   stronger than a hand-edited URL, and neither reaches a fixed field (point 1).
6. **The store only receives non-fixed, validated values.** Writes happen after
   resolution, only for `:remember` fields, with the resolved (allow-listed)
   value.
7. **Nested requests re-fix on the server.** A lazy detail is its own request to
   its own controller; whatever the parent fixes (e.g. the cost center of an
   embedded bookings table) is fixed again by that controller from its own path
   id and authorization, never taken from a frame-URL param. `level`
   (`expandable_table_level`) is the
   only thing a frame URL carries, and it only affects nesting depth, never
   scope.
8. **Reset skips fixed fields** (D3), and the widget renders fixed fields without
   links or menus — as a courtesy, not as the protection.
9. **Specs per point.** For every policy, a fixed field with a conflicting param
   *and* a conflicting store entry resolves to the fixed value; the rows objects
   are constructed with a state and ignore `params` entirely; and the guard spec
   of point 4.
10. **The filter's dataset comes only from the declaration; host-authored
    conditions are validated, user input is not trusted.** A table's `schema:` is
    read from the class-level `wsjrdp_expandable_table_policy` and from nowhere
    else — no param, store entry or cookie can point a table at another dataset's
    schema — and declaring any other filter option without it raises at
    declaration time. Fixed slots and a `default:` tree are parsed **strictly** at
    resolution, for the reason given in D2e; the compiler therefore only ever sees
    a query the state has already parsed, and there is no remaining way to hand it
    a raw tree. `exclude:` is enforced by construction: the user half is decoded
    against the reduced schema on both read paths, so no code path decodes it
    against the full one. `spec/controllers/fin/table_policies_spec.rb` resolves
    every declared table of the wagon once, so a typo in a pinned slot or a filter
    option without its `schema:` fails in CI, not in production.

## What was built

- `Wsjrdp::TableState` (with `TableState::Filter` and the `Resolver`),
  `Wsjrdp::TableStatePolicy`, and the two stores
  `Wsjrdp::TableStateStore::Session` / `::Cookie` behind the D7 interface.
- The controller concern `Wsjrdp::TableStateful`:
  `wsjrdp_expandable_table_policy` / `wsjrdp_expandable_table_state`, the reset
  `before_action` and the generic filter apply `wsjrdp_apply_table_filter`.
- One column description per dataset: `Wsjrdp::ExpandableTableColumns` /
  `Wsjrdp::ExpandableTableColumn` plus `Fin::DatevBookingsColumns`,
  `Fin::MossTransactionsColumns`, `Fin::AccountingEntriesColumns` and
  `Fin::BookkeepingSummaryColumns`.
- One rows object per table: `Wsjrdp::ExpandableTableRows` (order, page,
  `total_count`, `total_sum`), named in the view by
  `Wsjrdp::ExpandableTableBuilder#rows`.
- The filter-schema protocol `Wsjrdp::Filtering::FilterSchema` with
  `Fin::DatevBookingsFilterSchema`, `Fin::MossTransactionsFilterSchema` and
  `Fin::PersonalAccountsFilterSchema`.
- Filter **presets** (D2e): `Wsjrdp::TableState::FilterPreset`,
  `Wsjrdp::Filtering::SlotEquality`, the "Schnellauswahl" bar and its dirty
  lock. The Kreditoren list is their first host — and the first Buchhaltung
  summary that is relation-backed
  (`WsjrdpPersonalAccount.with_booking_summary`) so that it can be filtered at
  all.
- The filter's **line and pane**: one framed line above the table's toolbar
  carries the "Schnellauswahl" presets and the applied filter's chips
  (`Wsjrdp::FilterChips`, one chip per user slot) on its left and the pane's
  toggle at its right end; the column hamburger stays in the toolbar. The pane
  (the builder) opens BETWEEN that line and the toolbar, so the toggle keeps its
  place when the pane opens and nothing above it moves. Line and pane are both
  rendered in either state — only the pane appears and disappears — and the open
  state is the `pane` field (`e`, D2a, stored in a cookie), which the line
  follows via `data-pane-line`.
- **Follow-up (2026-09):** the `lte` / `nonzero` operators, an attribute's
  editor-only `pickable:` operator subset, and the magnitude variants
  |Betrag| / |Saldo| — which turned "Nur mit Saldo ≠ 0" into one condition. See
  `doc/wsjrdp/generic_filter_builder.md`, UX iteration 6.
- The widget, the builder and `Wsjrdp::ExpandableTableHelper` render and link
  from the state alone; the `et_*` URL builders are the only code there that
  touches the request.
- The hosts: `Fin::BookingsController`, `Fin::ReconciliationController` (two
  tables), `Fin::MossTransactionsController`, and the four Buchhaltung
  controllers on top of `Fin::BookkeepingSummaries`' option hashes.
- Docs: the guide `doc/wsjrdp/expandable_table.md` and Part 4 of
  `doc/wsjrdp/generic_filter_builder.md`.

## Execution record

Executed on 2026-09-05 against the **development** environment only (the dev
database and the dev server); nothing here ran against production.

### Commits (`2e7e4a00..HEAD`, oldest first)

| commit | subject |
|---|---|
| `a00ecea1` | Add the expandable table's state value object, policy and stores |
| `2a7b6d5b` | Add the Wsjrdp::TableStateful controller concern |
| `57f2d1ec` | Render the expandable table from its state instead of the params |
| `76b1ee1b` | Move the Buchungen and Abstimmung tables onto the table state |
| `6b9523bc` | Keep the remaining expandable-table hosts running on the state API |
| `3a7024f5` | Complete the Moss transactions migration onto the table state |
| `1999ca5c` | Write the table-state store even when every field is back at its default |
| `c49c74f0` | Declare the Buchhaltung summary tables completely |
| `3769c570` | Cover the Buchhaltung summary table state with a controller spec |
| `d7bad24e` | Document the expandable table's state model |
| `b422649f` | Record the execution of the table-state plan |
| `122761ec` | Scope the open-rows URL sync to each table's own wrapper |
| `844b041b` | Split the filtering spec into a standalone engine spec and a Rails spec |
| `186aa6f0` | Give the cookie store the same replace semantics as the session store |
| `2a678402` | Reset only the filter from the filter builder's button |
| `f125cfea` | Emit a blank filter param when the last condition is applied away |
| `2500c280` | Make "proposals first" the entries table's natural order |
| `f8b0dfac` | Page every expandable table through one state method |
| `4412641e` | Document the one paging method and the always-available page-size select |
| `3233cae5` | Resolve every table filter through its declared filter type |
| `6546b228` | Document the filter type behind the table's filter policy |
| `564ddc6f` | Name the table filter's dataset a schema, not a type |
| `b8454138` | Link a table's declaration and its state by the policy object |
| `212203ed` | Give every expandable table its own explicit declaration |
| `e90699a1` | Describe every expandable table's columns in one place |
| `c059e998` | Page every expandable table through one rows object |
| `ee3793fb` | Name an expandable table in the view with one method |
| `4b376fc2` | Let a Buchhaltung section say whether its bookings table is nested |
| `e71ebc3c` | Document the expandable table as one declaration, one rows object |
| `0ccfb6aa` | Apply a filter removal at once instead of waiting for "Anwenden" (reverted by the next row) |
| `e2efb5f3` | Keep the filter builder apply-only, with a visible hint and two resets |
| `cfe6ca91` | Rewrite the table-state plan as the current design record |
| `acfc414c` | Offer a table's filter as one-click presets |
| `7ded64c6` | Filter the Kreditoren list instead of ticking a grid |
| `56b0f4dd` | Document the filter presets and the relation-backed Kreditoren list |
| `6d5db45b` | Trim the Kreditoren presets and footer, offer every cost center in both pickers |
| `714c2e01` | Consume the typed search on a picker click; tick indicator on preset toggles |
| `4dff2dcd` | Mute the filter editor's hints and secondary text with a real fallback colour |
| `b695b237` | Add ≤ and ≠ 0 operators and an editor-only operator subset |
| `7db3b49a` | Filter an amount by its magnitude, next to its sign |
| `ac9b01f2` | Document the magnitude variants and the pickable operator subset |
| `32a434ac` | Tint the active preset instead of filling it, keeping the theme's dark button text |
| `c077e011` | Move the filter toggle into the table toolbar, joined with the column hamburger |
| `c9401960` | Let a table drop and rename columns of the shared description |
| `10a94537` | Keep path parameters out of the filter apply redirect |
| `b1d78d18` | Order a table's default columns as declared |
| `4ab3c57b` | Give the Moss list one tab per kind, pinned by a route default |
| `eda50f1a` | Stub Arel.sql in the rows spec only when no Rails is loaded |
| `27fb0fde` | Order the Moss kinds as Karte, Erstattung, Rechnung, Einzahlung |
| _(this commit)_ | Put the filter's presets, chips and toggle into one line above the table |

### Bugs found and fixed on the way

1. **The store was not written when every field was back at its default**
   (`1999ca5c`). The write-back skipped a store entirely if nothing differed from
   the defaults, so an explicit `?f=` left the old entry behind and the next bare
   visit restored the just-deleted filter. Fixed by touching the store even when
   the resulting hash is empty (an empty write deletes the entry).
2. **`to_i` comparison of alphanumeric numbers** in the summary sort (`c49c74f0`).
   Account and cost-center numbers may contain letters, and `to_i` collapsed all
   of those into one value, so sorting by number scrambled them. They are compared
   as a STRING now, exactly like the SQL `ORDER BY` that produces the natural
   order; the extractor lives in `Fin::BookkeepingSummaryColumns::NUMBER`.
3. **A lazily loaded detail's embedded table wrote the OUTER table's open rows**
   under its own `bo` param (`122761ec`, found on review). The open-rows URL sync
   is scoped to each table's own wrapper.
4. **The reconciliation entries' column picker emitted the LONG column key.** Its
   column configs were written inline in the view, without the `abbr:` the
   picker's JS builds the `?aec=` value from, so it fell back to the key and
   emitted `description` where the codec says `descr` — it still resolved, but the
   URL was not the canonical one. Fixed by construction with the one column
   description (`e90699a1`), which carries the abbreviation to the widget.

### Finding: no level-2 nesting exists today

The only nested table in the app is the condensed bookings table inside a
Buchhaltung item's detail (prefix `"b"`, level 1), and its own rows' details embed
no further table. The mechanism is in place and exercised (the `level:` lambda,
the `expandable_table_level` frame param, the per-item `store_key:`), but the recursive case beyond one
step is untested by anything but the unit specs.

### Verification

Example counts are what `rspec` prints for that file. In the wagon test container
six of them come from `spec/support/**`, which `spec_helper` auto-loads and which
defines top-level guard examples of its own (see `AGENTS.md`, "Running tests");
the standalone specs have none of that.

| spec | examples | what it covers |
|---|---|---|
| `spec/domain/wsjrdp/table_state_spec.rb` | **125** | standalone (no Rails, no DB): every policy; the D8.9 conflict case (a fixed field against a conflicting param *and* store entry); allow-list rejection from the URL *and* the store; `#paginate` over a relation double and an Array (the clamp on both, `:all` declared and on the wire, the private limit behind it); open-key bounding; the store cap and eviction; the cookie store's single-token rule; `wire_params`; the frozen state. The filter half (D2e, D8.10) runs against a **fake filter schema** — a plain object implementing the protocol and recording its `compile` calls, so the value object stays testable without a schema, a database or Arel: `exclude:` cannot be bypassed from either read path, a fixed-slot typo raises, `#scope` compiles fixed-then-user with the full-then-reduced schema, a missing `schema:` raises at declaration, `policy: :fixed` yields no user query, a present-but-blank param empties it, `default:` applies only on the `:default` path, and the wire round-trip. The PRESETS half covers the exact slot equality (order-independent, canonical operands, the OR-widened slot that does NOT count), the on/off toggle wires incl. the blank one, a multi-slot preset adding only what is missing, two overlapping presets deactivating together, the view-declared preset going through the same builder, and a typo or an excluded attribute raising. The per-table COLUMN SET (`cols: exclude:` / `labels:`, D2b) covers the declaration errors, an excluded column arriving from the URL *and* from the store, its absence from the `c` wire value and from the sort allow-list, the shaped column configs the widget renders, and the lambda form evaluated on the controller |
| `spec/controllers/fin/table_policies_spec.rb` | **25** | every controller of the wagon that declares a table (7 controllers, 11 tables) resolves each of its policies once with empty params, so a fixed-slot typo or a filter option without its `schema:` fails in CI (D8.10); plus, per controller, that a policy it did not declare is refused |
| `spec/domain/wsjrdp/expandable_table_state_guard_spec.rb` | **5** | the D8.4 grep over every `app/views/shared/wsjrdp/**/*.haml` partial and the helper, plus a "guard the guard" example proving the patterns still match |
| `spec/domain/wsjrdp/expandable_table_builder_spec.rb` | **36** | the builder's locals, `t.rows` setting `state` + `rows` together, the retired keys no longer being produced, a bare `t.paging` falling back to `DEFAULT_PER_OPTIONS`, and `t.filter` taking keywords -- including the raise when presets are declared in the policy AND in the view |
| `spec/domain/wsjrdp/expandable_table_columns_spec.rb` | **20** | standalone: the `define` block, the derived `codec` / `default_keys` / `sort_expressions`, `to_table_column(cell:)`, and the token and uniqueness rules a description has to pass |
| `spec/domain/wsjrdp/expandable_table_rows_spec.rb` | **23** | standalone against a relation double that records what it was asked for: the multi-column `ORDER BY` with its tiebreaker, the array sort with its extractors, `natural_order:` on both kinds of source, the sort allow-list, `#total_count` / `#total_sum` / `#limit`, and the raise when an array-backed table has no lambda tiebreaker |
| `spec/domain/wsjrdp/expandable_table_sort_spec.rb` | **35** | the RISON sort codec and the click cycle (multi and single) |
| `spec/domain/wsjrdp/filtering_engine_spec.rb` | **15** | standalone: vocabulary (the strict `gt` included), value objects, schema definition/derive/bind against a Hash-backed fake relation, the URL codec and the catalog projection |
| `spec/domain/fin/datev_bookings_filter_schema_spec.rb` | **19** | Rails: the Arel compiler against the real bookings schema, plus the strict `parse_fixed!` / `compile` half of the protocol |
| `spec/domain/fin/personal_accounts_filter_schema_spec.rb` | **18** | Rails: the same protocol against the Kreditoren schema and its relation -- the two aggregate columns of `with_booking_summary` (compared against the plain per-account totals), `gt` / `between` / two ANDed slots, the text search over both name columns, and the COALESCEd Moss status counting a NULL as inaktiv on both `in` and `not_in` |
| `spec/controllers/fin/moss_transactions_controller_spec.rb` | **19** | `?s=`, `?c=`, a Rison `?f=`, the remembered sort and filter on a bare revisit, the blank-param apply, the "Zurücksetzen" href (filter-only, D3), `?r=1`, and a page beyond the last one |
| `spec/controllers/fin/personal_accounts_controller_spec.rb` | **26** | the relation-backed Kreditoren page end to end: a `?f=` per attribute (a NULL Moss status showing and filtering as inaktiv), the sorts on the aggregates, `?z=all`, the remembered filter and the filter-only reset, the footer totals against a direct SQL sum, the `post :apply` PRG, the lazy detail -- and the presets: their hrefs and `aria-pressed`, toggling on and off through the URL, the overlapping pair activating and deactivating together, and an OR-widened slot not counting |
| `spec/controllers/fin/ledger_accounts_controller_spec.rb` | **15** | standing in for the two array-backed Buchhaltung summary pages (they share `Fin::BookkeepingSummaries`): the natural order, `?s=` and its memory, the blank param clearing a remembered sort or column selection, the D4 page clamp, `?r=1`, the lazy detail with its `?expandable_table_level=1`, and the per-item memory of the embedded bookings table |

Everything under `spec/domain/wsjrdp/` runs on the macOS host from the wagon root
(**311 examples**, all standalone since `844b041b`); the `spec/domain/fin/` and
`spec/controllers/fin/` specs need the wagon test database (see `AGENTS.md`,
"Running tests") — **118 examples** together with
`spec/abilities/finance_ability_spec.rb`. Beyond that, every round was checked in
the running dev app: the three Buchhaltung summary indexes, an item detail as
its own page *and* as a lazily loaded turbo frame with `?expandable_table_level=1`, and a
Buchungsstapel page all render 200 with their embedded `b…` table, and the
resolved nesting levels were read back per controller.

The presets round added a pass over the Kreditoren page in the dev app: the bare
page lists every creditor with the Moss column showing only aktiv/inaktiv and no
preset pressed; each toggle's href carries exactly the expected Rison and its
row count matches a `rails runner` count of the same condition; toggling one off
returns a blank filter param; switching one of two active presets off leaves
the other's slot in place; hand-written `?f=` values for a
balance range, a name search and the Moss status narrow correctly; a bare
revisit restores the remembered filter and "Filter zurücksetzen" clears it;
sorting by the two aggregates and by the status, `?z=all` and the lazy detail all
work; and the three other Buchhaltung pages render unchanged, with no preset bar
where no presets are declared. The dirty lock is client-side and was checked in
the browser: removing an applied condition's chip marks the builder dirty, at
which point every toggle carries `aria-disabled="true"`, no `href`,
`tabindex="-1"` and the locked title, the bar shows its note, and "Änderungen
verwerfen" restores all of it.

### Open follow-ups

1. **Not everything can be checked on the host.** The pure-PORO half of the
   design is deliberately standalone, but the two `spec/domain/fin/*_filter_schema_spec.rb`
   and the three `spec/controllers/fin/` specs boot Rails and need the wagon test
   database, so a host-only run never covers the Arel compiler, the real schemas
   or the rendered pages. Anything that can be a standalone spec should keep
   being written as one. The presets' **dirty lock** is JS and is covered by
   neither: it was verified by hand in the browser (see above), and a feature
   spec would be the only way to hold it.
2. **The per-person DB store is not built.** D7 defined the four-method store
   interface (`read` / `write` / `delete` / `delete_all`) for exactly this, but
   only `:session` and `:cookie` exist; remembered state therefore does not
   survive a logout or move between devices.
3. **A small unused API surface came with the generalisation.** Nothing calls
   `Wsjrdp::ExpandableTableRows#limit(n)` (kept as the replacement for the former
   query objects' `#limited`, for an inline preview inside another table's
   detail), `Wsjrdp::ExpandableTableHelper#et_sort_list`,
   `Wsjrdp::TableState#column_token` / `#column_key`,
   `Wsjrdp::ExpandableTableColumns#to_a` / `#fetch` / `#key?` / `#size`, or the
   stores' `delete_all` (the D7 contract). `et_reset_url` is the deliberate
   exception, already recorded in D3. Either a caller turns up or they go — decide
   once, not per reader.
4. **Level ≥ 2 is still only a unit-tested mechanism** — see the finding above.
5. **The two array-backed Buchhaltung summaries cannot be filtered.** Sachkonten
   and Kostenstellen still aggregate into an Array of Hashes, so they have no
   relation for the filter to compile against, and their footer shows the grand
   totals over every booking rather than what is on screen. Kreditoren shows what
   the relation-backed shape buys (`WsjrdpPersonalAccount.with_booking_summary`);
   the same move is open for the other two, at which point
   `Fin::BookkeepingSummaries.summary_policy_options` / `#summary_rows` /
   `#leg_summaries` and the array `sort:` extractors of
   `Fin::BookkeepingSummaryColumns` would all go.
