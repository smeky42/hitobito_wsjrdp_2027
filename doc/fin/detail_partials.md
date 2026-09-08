# Detail partials of the finance pages — guide

A finance record's detail is written **once**, as one partial per model, and
rendered in two places: on the record's own page
(`/fin/bookkeeping/personal_accounts/700000`) and inside the expandable table's
detail pane, where the same URL is lazy-loaded into the row's turbo frame. The
partial is told which of the two it is and adapts header, layout and the open
state of the raw area to it; nothing else about it changes.

The partial is meant to be **hand-edited**: one line per attribute, no markup.
How a field is formatted is declared centrally (one helper per model and
attribute), its label comes from i18n, and the whole thing mirrors hitobito's
own `format_attr` / `render_attrs`, so there is no second idiom to learn.

- Context object: `app/domain/fin/attr_format_context.rb`
  (`Fin::AttrFormatContext`)
- Formatter return value: `app/domain/fin/detail_value.rb` (`Fin::DetailValue`)
- Declaration collector: `app/domain/fin/detail_builder.rb`
  (`Fin::DetailBuilder` — what `d.…` calls)
- Formatter lookup: `app/helpers/fin/attr_format_helper.rb`
  (`fin_format_attr`, `fin_raw_format`, `fin_attr_visible?`)
- Rendering: `app/helpers/fin/detail_helper.rb` (`fin_detail`) with
  `app/views/fin/shared/_detail.html.haml`, `_detail_header.html.haml`,
  `_detail_group.html.haml`, `_detail_raw.html.haml`, `_detail_styles.html.haml`
- Worked example: `app/views/fin/personal_accounts/_detail.html.haml`,
  `app/helpers/fin/personal_accounts_helper.rb`,
  `app/controllers/fin/personal_accounts_controller.rb`
- Specs: `spec/domain/fin/attr_format_context_spec.rb`,
  `detail_value_spec.rb`, `detail_builder_spec.rb` (standalone, host-runnable),
  `spec/helpers/fin/attr_format_helper_spec.rb`, `detail_helper_spec.rb`,
  `personal_accounts_helper_spec.rb`,
  `spec/controllers/fin/personal_accounts_controller_spec.rb`

The table widget the embedded case belongs to is documented in
[`doc/wsjrdp/expandable_table.md`](../wsjrdp/expandable_table.md); the design
record behind this kit is `doc/plans/2026-09_fin-detail-partials.md`.

---

## 1. `Fin::AttrFormatContext` — where a value is being shown

Every formatter and every section sees, besides the record, one object saying
**where** it is being rendered:

```ruby
ctx.mode        # :regular  the record's own page
                # :embedded a table row's detail pane
ctx.regular?
ctx.embedded?
ctx.level       # 0 page · 1 a row's detail · 2 a table inside a detail · …
ctx.in_table?   # inside a table row's detail
ctx.lazy?       # arrived through a turbo frame
ctx.raw_source  # the jsonb column a raw block is rendering, nil elsewhere
```

`mode` is decided by the **host**, not derived from the nesting level; an
unknown mode raises. `level` / `in_table?` / `lazy?` are read off an optional
`Wsjrdp::TableContext`, so they answer the same way whether the detail arrived
through a frame or was rendered directly.

A controller's `show` builds both cases:

```ruby
def detail_format_context
  if request.headers["Turbo-Frame"].present?
    Fin::AttrFormatContext.embedded(
      Wsjrdp::TableContext.new(level: summary_table_state.level, lazy: true)
    )
  else
    Fin::AttrFormatContext.regular
  end
end
```

The level comes from the table's own state, because the widget appends the
detail's depth to the frame URL as the shared `expandable_table_level` param
(`doc/wsjrdp/expandable_table.md` §4).

A table that renders a detail **directly** — its `detail` lambda taking
`(row, ctx)`, where `ctx` is a `Wsjrdp::TableContext` — wraps that context
instead:

```ruby
t.detail { |row, ctx| render "fin/…/detail", record: row,
                             ctx: Fin::AttrFormatContext.embedded(ctx) }
```

`with_raw_source(source)` returns the same situation with `raw_source` set; the
renderer uses it per entries block of a raw area, nothing else needs it.

---

## 2. The formatter lookup — `fin_format_attr(obj, attr, ctx)`

`Fin::AttrFormatHelper#fin_format_attr` is the finance sibling of hitobito's
`FormatHelper#format_attr`: the same `respond_to?`-on-the-view-context lookup
and the same model-name rule (`base_class.name.underscore.tr("/", "_")`), plus
the context argument and a finance type layer in front of the core chain.

A field's helper is found in this order, most specific first:

| step | name | for |
|---|---|---|
| 1 | `fin_format_<subclass>_<attr>` | STI only, when the subclass differs from the base class |
| 2 | `fin_format_<base_class>_<attr>` | the normal case — `fin_format_wsjrdp_personal_account_iban` |
| 3 | `fin_format_<attr>` | model-wide fields (`moss_status`, `iban`, …) |
| 4 | the finance type rules | see below |
| 5 | `wsjrdp_format_attr` | hitobito's chain: enum labels, `belongs_to` / `has_one` links, booleans, decimals |

The subclass step is an extension over the core rule (which only knows the base
class); it lets an STI kind override one field without touching the others.

**Arity.** A formatter takes `(obj, ctx)`; `(obj)` alone is accepted for a
one-liner (`method(name).arity == 1` picks the short form, so a formatter with
optional parameters gets both arguments).

**The type rules** (`fin_format_attr_by_type`), for an attribute without a
formatter:

| value | result |
|---|---|
| `nil` or `""` | a **blank value** — the core chain is not entered, so a blank never becomes a non-breaking space |
| `Date` | `fin_date` |
| `Time` / `ActiveSupport::TimeWithZone` | `fin_date_time` |
| `Array` | the present entries joined with `", "`, an empty result is blank |
| `Hash` | raises — a jsonb column belongs in `d.raw_entries` |
| `*_cents` | `fin_money(value / 100)` |
| `BigDecimal` named `*_amount` | `fin_money(value)` |
| everything else | `wsjrdp_format_attr(obj, attr)` |

`false` and `0` are values, not blanks. The two money rules are deliberately
narrow — base-currency amounts only. An amount on another currency axis
([`money_conventions.md`](money_conventions.md)) gets an explicit
`fin_format_<model>_<attr>`; the rules are a fallback, not a currency model.

A **virtual attribute** is simply a formatter without a column: the lookup never
touches the record when a formatter exists, so `address` needs no model method —
only the formatter and an i18n key (§4).

---

## 3. Return values — `Fin::DetailValue`

A formatter may return a `String`, an html-safe buffer, `nil`, a `Hash` of the
keys below, or a `Fin::DetailValue`. `fin_format_attr` always answers with a
`Fin::DetailValue`, wrapping whatever came back — which is why a one-line
formatter never sees any of this.

| key | meaning | rendered as |
|---|---|---|
| `value` | the text / HTML | the value side of the row (escaped unless html-safe) |
| `help` | the field's comment | a muted line under the value (`wsjrdp_row_help`), in every layout |
| `tooltip` | explanation of the **label** | the label's `title` |
| `label` | a one-off label | in place of the i18n label |
| `blank` | what to do when `value` is blank: `:hide`, `:dash`, `:empty`, `:unset` | see §6 |
| `hide` | drop the row whatever the value is | nothing |

`blank_value?` follows hitobito's `attr_present?` rule: `nil` and `""` are
blank, `false` is a value.

Two guards: a `blank:` outside `:hide` / `:dash` / `:empty` / `:unset` raises,
and a Hash with an **unknown key** raises — `{tooltop: "…"}` must not silently vanish.

Extending the kit later is one key in the `Data.define` plus one branch in the
renderer; because `wrap` accepts a plain String, every existing one-line
formatter keeps working across such an addition.

---

## 4. Labels

The label of a field is hitobito's: `captionize(attr, object_class(record))` →
`Model.human_attribute_name(attr)`. A model therefore carries a block in
`config/locales/wsjrdp_2027.de.yml`:

```yaml
de:
  activerecord:
    models:
      wsjrdp_personal_account:
        one: Kreditor
        other: Kreditoren
    attributes:
      wsjrdp_personal_account:
        number: Nummer
        iban: IBAN
        # the Rechnungsadresse on one line, composed by Fin::PersonalAccountsHelper
        address: Adresse
```

Every attribute a partial lists needs a key, **virtual ones included**. A
`label:` in a field's options or in a formatter's Hash overrides one field;
`label:` from the formatter wins over the one in the partial, and both win over
i18n.

---

## 5. The visibility seam — `fin_attr_visible?`

`Fin::AttrFormatHelper#fin_attr_visible?(obj, attr, ctx)` is consulted for every
field and for every entries block of a raw area (with the jsonb column as the
attribute). It
returns `true`, and a field it says no to leaves **no row** behind — no
placeholder, no empty label.

Per-field authorization is not declared yet; it plugs in here and nowhere else.
Three mechanisms are on the table:

- a per-model map attribute → ability action (`{iban: :show_bank_details,
  other_datev_columns: :show_raw}`, default `:show`), the actions declared in the
  wagon's ability and checked with `can?(action, record)` — the idiom of
  `TableDisplays::Column#allowed?`;
- raw cancancan attribute rules (`can :show, Model, [:iban]`, then
  `can?(:show, record, :iban)`), expressible only outside hitobito's ability DSL;
- an inline `if can?` around a group in the partial — hitobito's show-page idiom.

`Fin::AccessHelper`'s `?can_fin=false` switch is the way to look at a page
without finance rights once fields are gated.

---

## 6. The builder — `fin_detail(record, ctx) do |d| … end`

Two phases, like `Wsjrdp::ExpandableTableBuilder`: the block **declares**
sections into a `Fin::DetailBuilder`, then `fin_detail` renders them through
`fin/shared/_detail` inside the shared `.bk-item-detail` card. No HTML is
produced inside the block except by `d.custom`, whose block is captured on the
spot.

```ruby
fin_detail(record, ctx, layout: nil, blank: nil) { |d| … }
```

`layout:` sets this partial's default layout — a Symbol, or a Hash naming one
per mode (`layout: {regular: :grid}`); `blank:` sets its default blank mode.

| call | what it declares |
|---|---|
| `d.header(back:, back_label:, label:, title: nil, toolbar: nil)` | the page header (§9); rendered in `:regular` mode only |
| `d.attrs(*attrs, **options)` | one group of fields, in the given order |
| `d.attr(attr, **field_options)` | a one-field group, or one more field of the open `d.section` |
| `d.section(title:, layout:, blank:) { \|d\| … }` | a titled group; the `d.attrs` / `d.attr` calls inside append to it |
| `d.raw_data(title: nil, open: nil) { \|d\| … }` | a collapsible raw area; the `d.raw_entries` calls inside append to it (§8) |
| `d.raw_entries(source, title:, also: [], exclude: [], blank: :hide)` | inside `d.raw_data`: one entries block of the area, over one jsonb column (§8) |
| `d.custom(title: nil) { … }` | captured HAML (links, forms, a model's own widgets) |
| `d.bookings(rows, show_all_path:, all_label:)` | the embedded, paged bookings list (`fin/bookings/_embedded`) |

**The options of `d.attrs`.** Three keys configure the **group** —
`layout`, `title`, `blank`. Every other key must name one of the listed
attributes and carries that field's own options:

```haml
- d.attrs :iban, :bic, bic: {blank: :dash}, iban: {label: "IBAN (Moss)", span: 2}
```

A field's options are `label help tooltip blank hide span align`; there is no
`value` — a value comes from the record through its formatter, never from the
partial.

**Typo guards.** The builder raises on: a per-field key that names none of the
listed attributes, an unknown field option (the message lists the known ones),
a `layout:` outside `:list` / `:compact` / `:grid`, a `blank:` outside `:hide` /
`:dash` / `:empty` / `:unset`, a group key (`layout` / `title` / `blank`) passed to
`d.attrs` **inside** an open `d.section`, a nested `d.section`, a nested
`d.raw_data`, a `d.raw_data` inside an open `d.section`, a `d.raw_entries`
outside a `d.raw_data`, and a `d.section`, `d.raw_data` or `d.custom` without a
block.

---

## 7. Layouts

`fin/shared/_detail_group` renders a group in one of three layouts. Value, help
line, tooltip and blank marker are produced in one place
(`fin_detail_content`), so switching layout never changes content.

| layout | markup | use |
|---|---|---|
| `:list` | `dl.fin-detail-list.m-0.p-2.border-top`, one `.row.mb-2` per field with `dt.col-md-3.col-xl-2.text-md-end.text-muted` (tooltip as its `title`) + `dd.col-md-9.col-lg-8.col-xl-8.mw-63ch.text-break` | the form-like grid of the wagon's tx/ae pages, the page default |
| `:compact` | `dl.row.small.mb-3`, `dt.col-sm-3.col-lg-2.fw-normal.text-muted` + `dd.col-sm-9.col-lg-10.text-break` | the dense rows of an embedded pane, the embedded default |
| `:grid` | `.row.g-3` cells, `col-6 col-md-4 col-lg-3` (`span: 2` widens to `col-12 col-md-8 col-lg-6`), `align: :end` right-aligns | cells with amounts |

The layout a group uses: the group's `layout:` → the partial's `layout:` (per
mode when it is a Hash) → the mode's own default (`:regular` → `:list`,
`:embedded` → `:compact`).

A group's `title:` renders above it as a small uppercase muted label. **A group
without a single visible row renders nothing at all** — no empty `dl`, no
stray title.

**The column grid of `:list`.** The layout aligns label and value exactly like
the wagon's own form-like pages (`/fin/tx/:id`, `/fin/ae/:id`): the column
classes are those of `WsjrdpFormHelper#form_like_labeled` — the label right-
aligned from `md` upwards in `col-md-3 col-xl-2`, the value in
`col-md-9 col-lg-8 col-xl-8 mw-63ch`, so a detail page and a form page put their
values on the same line. The definition-list semantics stay: one `dl` per group,
`dt`/`dd` per field, only wrapped in a Bootstrap `.row`.

**The label typography.** All three layouts keep the label quiet, so the eye
goes to the value: `:compact` says so in its classes (`fw-normal text-muted`
inside a `small` list), `:grid` in `.booking-detail-label`. In `:list` the `dt`
carries `text-muted` itself, and the kit's own class `fin-detail-list` on the
`dl` takes the weight and the size off Bootstrap's bold `dt` —
`font-weight: 400; font-size: .875rem`.
The rule lives in `fin/shared/_detail_styles`, which
`Fin::DetailHelper#fin_detail_styles` emits **once per response** through an ivar
guard (the project convention for view-local styles), in front of the first
detail's `.bk-item-detail` — a list page full of detail panes therefore carries
one style block.

### Blank resolution

First hit wins: the **formatter's** `blank:` → the **field's** → the
**group's** → the **partial's** → `:hide`.

| mode | result |
|---|---|
| `:hide` | no row |
| `:dash` | the label with a muted em dash |
| `:empty` | the label with an empty value |
| `:unset` | the label with a muted, small "nicht gesetzt" (`fin.detail.unset`) |

`:dash` and `:unset` both keep a field that carries nothing visible; `:unset`
spells out that the master data has no value for it, which is what the
Kreditoren detail says of the bank details and the Moss defaults.

---

## 8. The raw area

Raw data is declared explicitly, the way a group is: `d.raw_data` opens one
collapsible area — a single `details.fin-detail-raw` element, so a reader opens
or closes all of it at once — and the `d.raw_entries` calls inside its block
become its **entries blocks**:

```haml
- d.raw_data do
  - d.raw_entries :other_datev_columns, title: "DATEV Rohdaten"
  - d.raw_entries :other_moss_columns, title: "Moss Rohdaten",
      exclude: %w[Sprache]
```

The area's `title:` heads it; without one it is "Rohdaten"
(`fin.detail.raw_title`). Its `open:` decides the state: `nil` follows the mode
— open on the record's own page, collapsed in an embedded pane — `true` /
`false` force it. The header and the field groups render first (they are what
an editable partial wraps in its form); the raw areas, custom sections and the
bookings list follow them in their declaration order, so a partial may declare
several areas and they keep their order among themselves. A `d.raw_entries`
outside a `d.raw_data` raises, as does a nested `d.raw_data` and one opened
inside a `d.section`.

An entries block puts its `title:` as a small uppercase muted label, under it
the entries of one jsonb column as monospace `Schlüssel: Wert` lines — one line
per entry, keys **verbatim** as the export wrote them, in stored order. `also:`
appends regular columns to the block, keyed by their **column name** (raw
semantics: the technical name, not the label). `exclude:` leaves keys of the
source out — compared verbatim against its keys — for entries a regular field
already shows or that are pure noise; it does not touch the `also:` columns.

A block without a single shown entry renders nothing, and neither does an area
without a single such block.

Formatting goes through one helper per model, found by the same name rule as
the field formatters (`fin_raw_format_other_<subclass>`, then
`fin_raw_format_other_<base_class>`):

```ruby
def fin_raw_format_other_wsjrdp_personal_account(account, key, ctx)
  return nil unless ctx.raw_source == :other_datev_columns

  case key
  when "Adressattyp" then datev_code_with_meaning(account, key, DATEV_ADDRESSEE_TYPES)
  end
end
```

`ctx.raw_source` names the jsonb column being rendered, so a key that occurs in
two exports is unambiguous; the `also:` columns arrive with `raw_source` unset
and are read off the record itself.

The return contract is the one of §3 with one deliberate difference: **`nil`
means "nothing special, use the default formatting"**, because the helper is
asked about *every* key of an export. (For a field formatter, `nil` is a blank
value.) A Hash still works — `{hide: true}` drops one entry.

The default formatting is "as stored": a boolean as the word `true` / `false`,
a date in the finance notation, nested JSON compact on one line, everything
else as it is.

---

## 9. The header

`d.header` renders `fin/shared/_detail_header` in `:regular` mode only — an
embedded pane gets its "Detailseite" link line from the table widget above the
pane. One markup for every finance detail page:

```haml
= link_to back, class: "btn btn-sm btn-link px-0 mb-2" do
  = icon(:"arrow-left")
  = back_label
%h1.mb-3.d-flex.align-items-baseline.flex-wrap.gap-2
  %span.text-muted.fw-light= label
  - if title.present?
    %span= title
  - if toolbar
    .ms-auto= toolbar
```

`label:` is the technical part (light and muted), `title:` the record's name in
normal weight and optional; `toolbar:` is a captured block at the right end and
renders nothing when it is absent.

The `h1` therefore lives **in the partial**, inside the page's turbo-frame
wrapper. That is harmless: a lazy load never asks for `:regular` mode. The
page's Sheet keeps providing tabs and the left navigation.

---

## 10. How to add a model

Five pieces, none of them wired anywhere — helpers in `app/helpers` are
auto-included by the engine.

1. **The partial**, `app/views/fin/<plural>/_detail.html.haml`, with the
   record and `ctx` as its locals.
2. **The helper module**, `app/helpers/fin/<plural>_helper.rb`: one
   `fin_format_<model>_<attr>` per field that shows more than its stored value,
   plus `fin_raw_format_other_<model>` if the model has raw data. Everything
   else falls to the type rules of §2.
3. **The i18n block** `de.activerecord.attributes.<model>` (and
   `de.activerecord.models.<model>`) in `config/locales/wsjrdp_2027.de.yml` —
   one key per listed attribute, virtual ones included.
4. **The controller's `show`**: load the record and build the context, then
   render the partial inside `wsjrdp_detail_frame(<table id prefix>, <row key>)`
   — that helper answers in the frame the `Turbo-Frame` request header names and
   wraps a direct visit in `#main`, so the view never builds a frame id itself
   (`doc/wsjrdp/expandable_table.md`).
5. **The specs**: a helper spec for the formatters and a controller spec with
   `render_views` covering both modes — page (`h1`, `dl.fin-detail-list`, the
   raw area open) and frame request (no `h1`, `dl.row.small`, the raw area
   collapsed). Invent every value; a spec carries no real name, amount or bank
   datum.

The Kreditoren detail is the worked example of all five:

```haml
-#  Locals: account (WsjrdpPersonalAccount), ctx (Fin::AttrFormatContext)
= fin_detail(account, ctx) do |d|
  - d.header back: personal_accounts_path, back_label: "Zurück zu Kreditoren",
      label: "Kreditor #{account.number}", title: account.name
  - d.attrs :name, :short_name, :aliases, :moss_status
  - d.attrs :moss_account_holder_name, :iban, :bic, :moss_vat_id,
      :moss_default_payment_method, :address,
      iban: {blank: :unset}, bic: {blank: :unset}
  - d.attrs :moss_default_ledger_account_number, :moss_default_cost_center_number,
      :moss_default_sphere_number, :moss_default_team_name, blank: :unset
  - d.attrs :description, :comment, :represented_person
  - d.raw_data do
    - d.raw_entries :other_datev_columns, title: "DATEV Rohdaten"
    - d.raw_entries :other_moss_columns, title: "Moss Rohdaten"
  - d.bookings supplier_bookings(account.number),
      show_all_path: bookings_filter_path([[["any_account", "in", account.number]]]),
      all_label: "In Buchungen-Ansicht öffnen"
```

Its `show` builds the record — an account number the DATEV export never
described still shows its bookings, so a missing master-data record becomes a
stub carrying just the number — and the context of §1; `show.html.haml` is one
`render` of the partial inside `wsjrdp_detail_frame("supplier",
@account.number)`, and a frame request comes back as that frame alone, without a
layout.

---

## 11. What is not covered yet

The Kreditoren and the Kostenstellen details are built on this kit. The other
finance details render through their own partials:

- **Sachkonten** through `fin/shared/_item_detail`, and the **Buchungsstapel**
  page directly, both over `shared/wsjrdp/_detail_fields` (flat
  `[label, value]` pairs from the `*_detail_fields` helpers of
  `Fin::BookkeepingHelper`, labels as German string literals).
- **Beitragsbuchung** (`fin/accounting_entries/_detail`) and the **Moss
  transaction** detail through `shared/wsjrdp/_kv_grid`.
- **The DATEV booking** detail (`fin/bookings/_booking_detail`) through its own
  inline grid, with its own "Rohdaten (DATEV)" section.

`doc/plans/2026-09_fin-detail-partials.md` §5 records the order in which they
move onto the kit.
