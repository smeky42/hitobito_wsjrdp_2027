# Plan: sorting by measures, and the sort interaction of `expandable_table`

Status: **executed** on 2026-10-02 against the development environment only.
The user guide is [doc/wsjrdp/expandable_table.md](../wsjrdp/expandable_table.md)
(§2, "Sortable headers" and "Default sorts").

## Goal

A Budget cell shows three measures — IST, budget and the share spent — and the
Controlling page "Budget" sorts by each of them, e.g. the cost centers by how
far their budget is spent. The sort interaction of every finance table follows
one model with it.

## Decisions

### S1 — Sort variants, not extra columns

A column declares `sort_variants:`; each is a sort key of its own
(`<column key>__<name>`, wire token `<column abbr>_<name>`) and never a column:
not in `?c=`, the column picker or the codec. A table without the column cannot
sort by its variants. The policy learns them from the whole column collection
(`columns: COLUMNS`), the rows object from `sort_expressions`. Variants of one
column share that column's **level** of a multi-column sort (one measure per
column).

### S2 — Chips under the header label

Each variant is a chip ("ist", "soll", "%") with its own arrow (⇅ / ↓ / ↑). A
measure column starts descending (`sort_first: "desc"`); so does every amount
and count column of the finance tables. Names, numbers and dates start
ascending.

### S3 — Click replaces, shift-click appends

A click sorts by the clicked key alone and cycles first direction → opposite →
off. A shift-click appends a new level at the end, steps an existing level in
place, or lets another variant of the same column take over that level. The
shift URL is precomputed (`data-shift-href`), so the server stays the only
place that computes a sort; the JS only chooses which URL to follow.

### S4 — Tooltips on the arrows only

The arrow's tooltip states what exactly the next click and the next
shift-click do, including the level number ("Shift-Klick: als 3. Stufe
absteigend anfügen", "Stufe 2 durch „2026 IST“ absteigend ersetzen"). Without
any other level the shift line is left out.

### S5 — Rank boxes and the "Sortiert nach" bar

From two levels on, a sorted column shows its rank in a small outlined box after
its label (a box, since a superscript reads as a footnote); a shift-click on the box
removes the level. The bar sits in the toolbar next to the column hamburger,
which keeps its place when the bar disappears. It shows as soon as anything is
sorted: × per level; from two levels on also ‹ ›, ◎ (keep only this) and
drag-to-reorder. A condensed table shows the boxes only.

### S6 — Hidden vs. preselected default

`sort: {hidden: …}` orders the rows while nothing is chosen and is never shown;
`sort: {default: …}` is preselected, shown and removable (removal leaves an
explicit blank `?s=`, which is remembered). The finance tables all use hidden
sorts: booking lists by date ↓, batches by period ↓ and Primanota ↓, summary
lists and the Budget page by number ↑.

### S7 — Missing values last

NULL / nil sorts last in both directions, for a relation (`NULLS LAST`) and for
an Array alike: a cost center without a budget never tops a budget or share
sort.

### S8 — Highlighting the sorted measure

The Budget page outlines, in every cell of a column, the measure that column is
sorted by. This is page-specific (`Fin::BudgetsHelper` reads the state), not part
of the kit.

## Execution record

1. Sort logic: variants, `sort_first`, click / shift-click, hidden sort, nils
   last — `Wsjrdp::ExpandableTableColumn`, `Wsjrdp::ExpandableTableColumns`,
   `Wsjrdp::TableStatePolicy`, `Wsjrdp::TableState`, `Wsjrdp::ExpandableTableSort`,
   `Wsjrdp::ExpandableTableRows`.
2. Widget: chips, rank boxes, tooltips, the bar, shift-click and drag JS —
   `Wsjrdp::ExpandableTableSortHelper`, `shared/wsjrdp/_expandable_table_sort_bar`.
3. Budget page: measures per year, Gesamt and Unit-Budget, highlight.
4. Finance tables: hidden default sorts, amounts descending first.
5. This note and the guide.
