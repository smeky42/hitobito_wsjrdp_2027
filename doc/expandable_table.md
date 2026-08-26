# The `expandable_table` widget — tutorial & guide

`shared/_expandable_table` is the one shared table used across the Finanzen
area (the Buchungen list, the Buchhaltung summaries, and both reconciliation
tables). Every extra element — a filter, a summary line, paging, a column
hamburger, row selection, sortable headers, expandable per-row detail — is an
**optional** local that is **off by default**. A bare call renders a plain
table; you turn on exactly the features a page needs.

This guide starts with the smallest possible table and adds one feature at a
time, then documents the full local reference, the query-param namespacing that
lets several tables share one page, the detail-nesting context, and the two
real consumers as worked examples.

- Widget: `app/views/shared/_expandable_table.html.haml`
- Helper: `app/helpers/expandable_table_helper.rb` (`et_*`)
- Sub-partials: `_expandable_table_paging`, `_expandable_table_columns_form`,
  `_table_selection_js`, `_table_hamburger`, `_expandable_table_styles`
- Detail nesting: `app/models/table_context.rb`

---

## 1. The smallest table

```haml
= render "shared/expandable_table",
  columns: [
    { key: "name",  label: "Name",  cell: ->(r) { r.name } },
    { key: "total", label: "Summe", numeric: true, cell: ->(r) { r.total } },
  ],
  rows: @records,
  row_key: ->(r) { r.id },
  detail: ->(r) { render "some/detail", record: r }
```

That renders a table with a clickable row per record; clicking a row expands an
inline **detail** (Bootstrap collapse, several can be open at once). `row_key`
must be unique — it keys the detail's DOM id and the open-state URL param.

A **column** is a Hash: `key` (stable id), `label`, `cell` (a `->(row)` that
returns the cell content), plus optional `numeric:` (right-align), `width:`
(e.g. `"7rem"`), `sort_key:`, `css_class:`, `condensed_label:`, `abbr:`.

Instead of an inline `detail:`, pass `detail_src: ->(r){ url }` to **lazy-load**
the detail into a turbo frame the first time the row opens (keeps big lists
fast — the Buchhaltung summaries do this).

---

## 2. Add features, one local at a time

Each of these is independent and defaults to off.

**Sortable headers.** Give the sortable columns a `sort_key:` and (optionally)
tell the widget the default order:

```haml
  default_sort: { key: "total", dir: "desc" }
```

The active column shows a bold `↑`/`↓`; other sortable columns show a muted
`⇅`. Clicking flips the direction. The click just changes the `<prefix>_sort` /
`<prefix>_sort_dir` URL params — **your controller** reads them to order the
query (the widget only renders the links + arrows).

**A summary line.**

```haml
  summary: "#{@records.size} Einträge · Summe: #{eur(sum)}"
```

**Paging (above and below).** Pass a Kaminari page as `pagination:` and the
page-size choices as `per_options:`:

```haml
  pagination: @page, per_options: [25, 50, 100, "all"], default_per: 50
```

The page-size select only appears when it is useful (more than one page, or a
non-default size is active) — never when everything fits on one page.

The widget does **not** slice the rows itself — `rows:` must already be the
current page. For a query-backed table that is the query's page (see §5). When
your rows are a **plain array** (e.g. the Buchhaltung summaries), wrap it with
Kaminari and read the page size through the helper so it matches the widget's own
per-page state:

```haml
- per = et_per_page("", 10)     # "" = this table's prefix; 10 = the default size
- page = Kaminari.paginate_array(my_rows).page(params[:page]).per(per)
= render "shared/expandable_table",
  rows: page, pagination: page, per_options: [10, 25, 50, 100, "all"], default_per: 10, …
```

Pass the SAME number to `default_per:` that you gave `et_per_page` (here `10`), so
the "pro Seite" select shows the right current value. For a prefixed table, read
`params[:"#{prefix}_page"]` and pass the prefix to `et_per_page` too. If you sort
or filter the array yourself, do it **before** paginating (the page must be the
final, ordered slice), and make your sort / filter links drop the page param
(`request.query_parameters.except("page")`) so a new order returns to page 1 —
`et_url` already does this for you when you use the widget's native sort links.

**A column hamburger (show/hide + reorder).**

```haml
  columns_menu: true, default_column_keys: %w[name total]
```

A right-aligned ☰ opens a picker (check to show, drag to reorder). The full
state is encoded into the `<prefix>_cols` query param (shareable / bookmarkable,
never localStorage). `columns:` is then the FULL set; the widget renders only
the visible ones in the chosen order.

**Row selection (remembered across pages).**

```haml
  selection: {
    name: "ids[]",                 # checkbox name (posted to the form)
    id_field: ->(r) { r.id },      # the checkbox value
    form: "my-form",               # id of the <form> the checkboxes belong to
    all_param: "select_all",       # (optional) enables "select all pages"
    total_count: @page.total_count,
    enabled: ->(r) { … },          # (optional) which rows are selectable
    row_data: ->(r) { { level: …, amount: … } },  # (optional) data-* per row
    remember_key: "mytable",       # sessionStorage key (default: the prefix)
  }
```

A leftmost checkbox column + a header "select page" box appear. The selection is
**remembered across paging / sorting / column changes** (sessionStorage) and
**cleared when the filter changes**. With `all_param`, once a full page is
selected a bar offers "select all rows of the query (all pages)". On submit of
the linked form, remembered ids that are not on the current page are injected as
hidden inputs, so a cross-page selection posts completely.

`on_filter_change:` defaults to `:clear`. `:narrow` (keep the still-matching
rows) is reserved — passing it raises `NotImplementedError` for now.

**A filter.** Pass a `filter:` config; the generic CNF filter builder
(`doc/generic_filter_builder.md`) is rendered above the table:

```haml
  filter: {
    catalog: filter_catalog, value: filter_value,
    apply_url: apply_path, reset_url: reset_path, carry: carried_params,
    locked: pinned_tree, locked_catalog: full_catalog,
    condensed_locked: true,   # show the fixed conditions as a compact summary
    disabled: false,          # true = read-only filter (no further input)
  }
```

`condensed_locked` collapses the host-pinned conditions to one muted summary
line (with a full-text tooltip) while still allowing the user to add their own.
`disabled` renders the whole filter read-only.

---

## 3. Namespacing: several tables on one page (`prefix`)

Everything a table reads from the request — `page`, `per`, `sort`, `sort_dir`,
`cols`, `filter`, the open-rows param — is namespaced by **`prefix`**:

| prefix | params |
|---|---|
| `""` (default) | `page`, `per`, `sort`, `cols`, `filter`, … |
| `"bk"` | `bk_page`, `bk_per`, `bk_sort`, `bk_cols`, `bk_filter`, … |
| `"ae"` | `ae_page`, `ae_per`, `ae_sort`, `ae_cols`, `ae_filter`, … |

Two tables with **different prefixes page / sort / filter independently** on the
same page (the reconciliation page runs `bk` + `ae`). The **same prefix is used
by your controller** (to read the params and build the query) **and by the
widget** (to render the current state and build links), so they always agree —
the URL builders (`ExpandableTableHelper#et_url`) keep every OTHER param
(including sibling tables') untouched.

Use `prefix: ""` when a page has a single table (keeps its URLs short); give a
prefix only when tables coexist.

For a `DatevBookingsQuery`-backed listing, pass the prefix to the query too
(`DatevBookingsQuery.new(params, prefix: "bk")`); `Fin::BookingsFiltering`
controllers set it via `booking_param_prefix`.

---

## 4. Detail nesting: `TableContext` (lazy AND direct)

The same detail partial (a DATEV booking, a ledger account, …) is rendered both
on its own page and nested inside a table row — sometimes several levels deep (a
Buchhaltung item detail embeds a bookings table, whose rows have their own
detail). `app/models/table_context.rb` makes the situation explicit:

```ruby
ctx.root?    # true on a dedicated page (level 0)
ctx.nested?  # true inside a table row's detail (level >= 1)
ctx.level    # 0 page · 1 a row's detail · 2 a table inside a detail · …
ctx.lazy?    # loaded into a turbo frame?
```

The widget hands a `TableContext` to a detail rendered **directly** (the detail
lambda may take `(row)` or `(row, ctx)`), and for a **lazy** detail it puts the
depth in the frame URL as `_lvl`, which the target reads back — so a partial
reads its nesting the same way either way. A detail that embeds another table
passes `ctx.level` on as that table's `detail_level`, so the count keeps going
up. See `fin/bookings/_booking_detail` (reads `table_context`) and
`fin/shared/_item_detail` (reads `_lvl`, threads `detail_level`).

---

## 5. Worked example A — the Buchungen list

`fin/bookings/_bookings_table` is a thin adapter: it maps the booking specifics
(column config from `booking_table_columns`, the eye/soft-delete action cell,
the inline `_booking_detail`, the count+sum summary) onto the widget, and passes
`condensed:` for the compact in-detail variant. `_browser` assembles the
`filter:` config from `Fin::BookingsFiltering`; `_embedded` wraps the condensed
variant for the account/supplier/cost-center detail pages. The standalone page
uses `prefix: ""`; the same table on the reconciliation page uses `prefix: "bk"`.

## 6. Worked example B — the reconciliation page

`fin/reconciliation/participant_fees` renders **two** tables through the widget:

- the **bookings** table (`prefix "bk"`) via `_browser`, with a locked filter
  shown condensed, an injected match-proposal column (`extra_columns:`), row
  selection, and a candidate list in each row's detail (`detail_top:`);
- the **entries** table (`prefix "ae"`) via `expandable_table` directly, with
  the reverse match-proposal column, its own selection and candidate list.

Both share `fin/reconciliation/_connect_controls` (the "Auswahl verbinden"
button + per-level quick-select + the count/sum confirm), which drives whichever
`.bk-select-scope` its `form_id` points at. Because the prefixes differ, the two
tables page, sort and select **independently**.

---

## 7. Full local reference

| local | meaning |
|---|---|
| `columns` | column configs (required) — the full set when `columns_menu` |
| `extra_columns` | injected columns appended after the menu-managed ones, never in the picker |
| `rows` | the collection to render |
| `row_key` | `->(row){ String }` unique key |
| `detail` / `detail_src` | inline (server) or lazy (turbo frame) detail |
| `detail_top` / `detail_extra` | `->(row){ html }` injected at the top / bottom of each detail |
| `action` | `->(row){ html }` trailing action cell |
| `row_class` | `->(row){ css }` extra class on the row |
| `prefix` | query-param + DOM-id namespace (`""` / `"bk"` / `"ae"`) |
| `id_prefix` | DOM id prefix (default: the prefix, else `"exp"`) |
| `sortable` / `default_sort` | enable sort links / the default column+dir |
| `pagination` / `per_options` / `default_per` | paging above & below |
| `columns_menu` / `default_column_keys` | the column hamburger |
| `summary` | a summary line (HTML) |
| `selection` | row selection config (see §2) |
| `filter` | filter builder config (see §2) |
| `condensed` | compact in-detail variant |
| `detail_level` | this table's nesting level (for `TableContext`, default 0) |
| `open_keys` | Set of open row keys (default: read from the open param) |

The Buchhaltung summary pages (Sachkonten / Kostenstellen / Kreditoren) render
array-backed rows (`Kaminari.paginate_array`, see §2) and turn on **paging**
(`default_per: 10`), the **column hamburger** (`columns_menu: true`) and the
widget's **native sortable headers** (`sort_key:` per column; the controller
orders the in-memory array in `sort_summary_rows` from `?sort` / `?sort_dir`).
Kreditoren adds its own preset / visibility controls above the table. They still
leave row selection and the filter off — the Buchungen and reconciliation tables
exercise those.
