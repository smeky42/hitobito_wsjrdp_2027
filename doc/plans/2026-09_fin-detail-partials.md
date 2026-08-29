# Plan: shared detail partials for the finance pages

Status: **parts A (kit, commit `bf990c8e`) and B (Kreditoren, commit
`19b7367d`) are built; part C (§5, the other finance models) is open.** The
present state of the kit is documented in
[`doc/fin/detail_partials.md`](../fin/detail_partials.md); this document stays
as the historical brief. Section 1 records the decisions (all taken by the
user), section 3 the architecture, section 4 the first implementation
(Kreditoren), section 5 the order for the other models.

Every rule of `AGENTS.md` applies to the implementing session: only the wagon
is changed, specs run only in the test-DB environment, `bundle exec rubocop
-a .` is offence-free before each commit, commits are small `Draft: …`
commits of exactly the touched files, nobody pushes, and neither code, docs
nor specs carry real names, amounts or bank data.

---

## 0. Goal

One detail partial per finance model, rendered **both** on the record's own
page (`/fin/bookkeeping/personal_accounts/700000`) **and** inside the
expandable table's detail pane (the same URL, loaded lazily into the row's
turbo frame). The partial is told which of the two it is. It has up to four
areas:

| area | regular page | embedded pane |
|---|---|---|
| header | back link + `h1` (+ optional toolbar) | nothing — the table widget already renders the "Detailseite" link line above the pane |
| fields | label/value groups, Hitobito list layout | the same groups, compact layout |
| raw data | the `other_*_columns` of the record, monospace, open | the same, collapsed |
| host content | e.g. the embedded bookings table | the same |

The partial must be **hand-editable**: one line per attribute, no markup,
easy to drop a field or reorder. Formatting of a field is **overridable
individually but declared centrally** (one helper per model + attribute),
labels come from i18n, and the whole thing mirrors how Hitobito's own
`format_attr` / `render_attrs` work so nobody has to learn a second idiom.

Kreditoren (`WsjrdpPersonalAccount`) are built first; the other finance
models follow the same kit (section 5).

---

## 1. Decisions

| # | question | decision |
|---|---|---|
| D1 | formatter name | `fin_format_<model>_<attr>` with the model part derived exactly like Hitobito: `base_class.name.underscore.tr("/", "_")` — e.g. `fin_format_wsjrdp_personal_account_iban` |
| D2 | variants (regular / embedded) | **no** variant suffix; one helper `(obj, ctx)` branches on the context itself |
| D3 | lookup stages | `fin_format_<subclass>_<attr>` → `fin_format_<base_class>_<attr>` → `fin_format_<attr>` (model-wide fields such as `moss_status`, `iban`) → finance type rules → Hitobito's chain via `wsjrdp_format_attr` |
| D4 | return value | `String` / html-safe buffer / `nil` / `Hash` / `Fin::DetailValue`; a Hash is wrapped into `Fin::DetailValue` (`Data.define`), unknown keys raise |
| D5 | context object | new PORO **`Fin::AttrFormatContext`**: `mode` (`:regular` / `:embedded`), the `Wsjrdp::TableContext` (level, lazy) when there is one, `raw_source` while a raw block is rendered |
| D6 | per-field CanCan visibility | **postponed.** The kit gets one seam (`fin_attr_visible?`) that returns `true`; the declaration mechanism is decided later (candidates in §3.5) |
| D7 | field the viewer may not see | the row is **hidden** (no placeholder) |
| D8 | layout | regular → Hitobito's `dl.dl-horizontal` list, embedded → the compact `dl.row.small` of today's Kreditoren detail; **both tweakable** per partial and per group (`layout:` option, third layout `:grid` for cells with span/align) |
| D9 | blank values | **per field**: `:hide`, `:dash` or `:empty`; settable in the partial and returnable by a formatter (`blank:` key); default `:hide` |
| D10 | header | regular: back link + `h1` (technical part light/muted, name normal) + optional toolbar slot, one style for all finance detail pages; embedded: no header |
| D11 | raw data | initially only `other_datev_columns` and `other_moss_columns`; adding further regular columns to a raw block must be one word (`also:`) |
| D12 | raw formatting | one helper per model, `fin_raw_format_other_<model>(object, key, ctx)`; `nil` = default type formatting |
| D13 | labels | `activerecord.attributes.<model>.*` in `config/locales/wsjrdp_2027.de.yml`, resolved through `captionize` / `human_attribute_name`; `label:` overrides one field |
| D14 | partial style | builder block like the table kit: `= fin_detail(record, ctx) do |d|` … `- d.attrs :a, :b` |
| D15 | scope | kit + Kreditoren in full; Sachkonten/Kostenstellen next; then bookings, Moss, Beitragsbuchung, Kontobewegung as later sessions |

---

## 2. Current state (facts the design builds on)

**Hitobito core, `app/helpers/format_helper.rb`.** `format_attr(obj, attr,
display_link:)` looks — on the view context, via `respond_to?` — for
`format_<base_class.name.underscore>_<attr>(obj)`, then an i18n enum label,
then `format_<attr>(obj)`, then `belongs_to` / `has_many` links, then the
column type (`format_column`: dates via `l`, decimals via
`number_with_precision`, booleans via `global.yes/no`, `nil` →
`FormatHelper::EMPTY_STRING`). A formatter receives the **object**, returns a
`String`, an html-safe buffer or `nil`; nothing returns a Hash. Labels come
from `captionize(attr, object_class(obj))` → `human_attribute_name`.
`render_attrs(obj, *attrs)` wraps `labeled_attr` pairs (`shared/_labeled`:
`div.labeled-grid > dt.muted + dd`) in `dl.dl-horizontal.m-0.p-2.border-top`;
`labeled(label, content, tooltip:)` already knows a tooltip. Per-attribute
authorization exists only in `TableDisplays::Column#allowed?`
(`ability.can?(required_permission(attr), object)`); show pages use inline
`if can?(…)` around a `render_attrs` call.

**Wagon, generic helpers.** `WsjrdpFormHelper#wsjrdp_format_attr` adds the
`has_one` step in front of the core chain; `input_or_render_attrs(f, *attrs)`
is the form-side sibling with the `<attr>_display` convention;
`Fin::LabeledRowsHelper` has the form-like rows, `wsjrdp_newtab_link` and
`assoc_link_with_newtab`; `Fin::DateHelper` (`fin_date`, `fin_date_time`) and
`Fin::MoneyHelper` (`fin_money`, `fin_currency_symbol`) are the finance
formats. `Wsjrdp::TableContext` (`level`, `lazy?`, `root?`, `nested?`) is
handed to every table detail; the widget appends the detail's level to a lazy
frame's URL as the table's `l` param, and the target controller resolves it
into `summary_table_state.level`.

**Wagon, finance detail views today.** Three field renderers compete:
`shared/wsjrdp/_detail_fields` (flat `[label, value]` pairs, `dl.row.small`,
blanks dropped — Kreditoren, Sachkonten, Kostenstellen, Buchungsstapel),
`shared/wsjrdp/_kv_grid` (rows of `[label, value, span, align]` cells, blanks
→ em dash — Beitragsbuchung, Moss transaction) and an inline copy of the grid
in `fin/bookings/_booking_detail`. Labels are German string literals in
helpers (`Fin::BookkeepingHelper#supplier_detail_fields`) or in HAML;
`WsjrdpPersonalAccount` has **no** i18n attributes. The booking detail has the
only "Rohdaten" section (`booking_raw_fields`, monospace `key: value` lines,
`other_datev_columns` spread at the end); no Moss view shows
`other_moss_columns`. `_booking_detail` and the Moss `_detail` accept a
`table_context` local but never read it. Every finance controller authorizes
once, class-level, with `authorize!(:fin_admin, Model)`; the finance action
set is identical for every model (`fin_admin create log manage show update`),
there is no attribute level, and Hitobito's ability DSL compiles only
`can action, klass` (no CanCanCan attribute lists).

**Kreditoren specifically.** `Fin::PersonalAccountsController` (`param:
:number`, `Fin::BookkeepingSummaries`), index with `t.detail_src { |a|
personal_account_path(a.number) }` and `t.detail_page`, show =
`turbo_frame_tag("bkframe-supplier-#{@number}") { supplier_item_detail(@number) }`
plus, outside a frame request, the back link and an `h1` built in the view.
`supplier_item_detail` renders `fin/shared/_item_detail` (fields +
`fin/bookings/_embedded` over `supplier_bookings(number)`, i.e.
`DatevBooking.legs` of the account). The model has 35 columns
(`db/schema.rb`, `create_table "wsjrdp_personal_accounts"`), among them the
generated `display_short_name`, the array `aliases`, `visibility`,
`represented_person_id` (→ `Person`), the three jsonb columns and
`to_s = "#{number} #{display_short_name}"`. The domain background is
`doc/fin/personal_accounts.md`.

---

## 3. Architecture

### 3.1 `Fin::AttrFormatContext` — where a value is being shown

`app/domain/fin/attr_format_context.rb`, a PORO (standalone-spec-able):

```ruby
class Fin::AttrFormatContext
  MODES = %i[regular embedded].freeze

  attr_reader :mode, :table_context, :raw_source

  def initialize(mode:, table_context: nil, raw_source: nil)
    raise ArgumentError, "mode must be one of #{MODES.join(", ")}" unless MODES.include?(mode)
    @mode = mode
    @table_context = table_context
    @raw_source = raw_source
  end

  def regular?  = mode == :regular
  def embedded? = mode == :embedded
  def level     = table_context&.level.to_i          # 0 on a page
  def in_table? = table_context&.nested? || false    # inside a table row's detail
  def lazy?     = table_context&.lazy? || false      # arrived through a turbo frame

  def self.regular = new(mode: :regular)
  def self.embedded(table_context) = new(mode: :embedded, table_context: table_context)

  # The same situation, with the jsonb column a raw block is rendering (§3.7).
  def with_raw_source(source) = self.class.new(mode:, table_context:, raw_source: source)
end
```

`mode` is decided by the host, not derived from the level: a controller's
`show` builds `Fin::AttrFormatContext.regular` for the page and
`Fin::AttrFormatContext.embedded(Wsjrdp::TableContext.new(level:
summary_table_state.level, lazy: true))` for a turbo-frame request; a table
that renders a detail **directly** passes
`Fin::AttrFormatContext.embedded(ctx)` from its `(row, ctx)` detail lambda.
`level` / `in_table?` / `lazy?` therefore read the same way in both paths,
exactly as `Wsjrdp::TableContext` intends (`doc/wsjrdp/expandable_table.md`
§4). The kit itself stays untouched.

### 3.2 The formatter lookup — `fin_format_attr(obj, attr, ctx)`

`app/helpers/fin/attr_format_helper.rb`. It is the finance sibling of
`FormatHelper#format_attr`: the same `respond_to?`-on-the-view-context
mechanism, the same model-name rule, plus the context argument and a finance
type layer in front of the core chain.

```ruby
module Fin::AttrFormatHelper
  # Formats `attr` of `obj` for `ctx`; always returns a Fin::DetailValue.
  def fin_format_attr(obj, attr, ctx)
    name = fin_formatter_names(obj, attr).find { |n| respond_to?(n) }
    Fin::DetailValue.wrap(name ? fin_call_formatter(name, obj, ctx) : fin_format_attr_by_type(obj, attr, ctx))
  end

  # Candidate helper names, most specific first (D1, D3):
  #   fin_format_<subclass>_<attr>   (STI only, when it differs from the base class)
  #   fin_format_<base_class>_<attr>
  #   fin_format_<attr>
  def fin_formatter_names(obj, attr)
    klass = object_class(obj)
    classes = klass.respond_to?(:base_class) ? [klass, klass.base_class].uniq : [klass]
    classes.map { |k| :"fin_format_#{k.name.underscore.tr("/", "_")}_#{attr}" } << :"fin_format_#{attr}"
  end

  # A formatter takes (obj, ctx); (obj) alone is accepted for one-liners.
  def fin_call_formatter(name, obj, ctx)
    (method(name).arity == 1) ? send(name, obj) : send(name, obj, ctx)
  end

  # Finance type rules for attributes without a formatter, then hitobito's
  # chain (i18n enum labels, belongs_to / has_one links, booleans, decimals).
  def fin_format_attr_by_type(obj, attr, ctx)
    value = obj.public_send(attr)
    case value
    when Date then fin_date(value)
    when ActiveSupport::TimeWithZone, Time then fin_date_time(value)
    when Array then value.compact_blank.join(", ")
    when Hash then raise ArgumentError, "#{attr} is a jsonb column, list it in d.raw instead"
    else
      if attr.to_s.end_with?("_cents") then fin_money(value.to_d / 100)
      elsif value.is_a?(BigDecimal) && attr.to_s.end_with?("_amount") then fin_money(value)
      else wsjrdp_format_attr(obj, attr)
      end
    end
  end
end
```

Notes for the implementer:

- `object_class` is `UtilityHelper#object_class` (unwraps decorators and
  relations); `wsjrdp_format_attr` is `WsjrdpFormHelper`'s.
- The STI step is an extension over the core rule (which only knows the base
  class); it lets `fin_format_moss_top_up_display_name` differ from
  `fin_format_moss_transaction_display_name` later. The user chose the core
  rule for the **name**; subclass-first lookup is the plan's assumption (§7).
- The money rules are deliberately narrow: `*_cents` integers and
  `*_amount` decimals in the base currency. A model whose amount lives on a
  different currency axis (transaction amounts, `doc/fin/money_conventions.md`)
  gets an explicit `fin_format_<model>_<attr>` — the rules are a fallback,
  not a currency model.
- A virtual attribute (e.g. `address`, composed from four columns) is just a
  formatter without a column: `fin_format_wsjrdp_personal_account_address`.
  The lookup never touches the model when a formatter exists, so the model
  needs no method; `human_attribute_name(:address)` still needs an i18n key.

### 3.3 Return values — `Fin::DetailValue`

`app/domain/fin/detail_value.rb`:

```ruby
# What a formatter hands back, normalised. A formatter may return a String,
# an html-safe buffer, nil, a Hash with these keys, or a DetailValue.
Fin::DetailValue = Data.define(:value, :help, :tooltip, :label, :blank, :hide) do
  BLANK_MODES = %i[hide dash empty].freeze

  def initialize(value: nil, help: nil, tooltip: nil, label: nil, blank: nil, hide: false)
    raise ArgumentError, "blank must be one of #{BLANK_MODES.join(", ")}" if blank && !BLANK_MODES.include?(blank)
    super
  end

  def self.wrap(result)
    case result
    when Fin::DetailValue then result
    when Hash then new(**result)          # an unknown key raises ArgumentError (typo guard)
    else new(value: result)
    end
  end

  # `false` is a value (hitobito's attr_present? rule), "" and nil are blank.
  def blank_value? = value.nil? || (value.respond_to?(:empty?) && value.empty?)
end
```

| key | meaning | rendered as |
|---|---|---|
| `value` | the text / HTML | the `dd` / cell content (escaped unless html-safe) |
| `help` | the "Kommentar" of the field | muted line under the value (`form-text`, like `wsjrdp_row_help`) in every layout |
| `tooltip` | explanation of the label | `title` on the `dt` (core `labeled(tooltip:)` does the same) |
| `label` | one-off label | replaces the i18n label |
| `blank` | what to do when `value` is blank | `:hide` (no row), `:dash` (muted em dash), `:empty` (label only) |
| `hide` | suppress the row regardless of value | nothing |

Extending it later is one new key in `Data.define` plus one branch in the
renderer (§3.6) — e.g. `copy: true` for a copy-to-clipboard button, `badge:`
for a status chip, `link_new_tab:` for the new-tab companion icon. Because
`wrap` accepts a plain String, every existing one-line formatter keeps
working when a key is added.

### 3.4 Labels

`captionize(attr, object_class(obj))` → `Model.human_attribute_name(attr)`,
exactly as in the core. For Kreditoren this means a new block
`activerecord.attributes.wsjrdp_personal_account:` in
`config/locales/wsjrdp_2027.de.yml` (the `attributes:` section starts at
line 59; `moss_transaction` at line 270 shows the shape) plus
`activerecord.models.wsjrdp_personal_account` (`one: Kreditor`, `other:
Kreditoren`). Every attribute the partial lists needs a key, virtual ones
included (`address`); the German literals currently in
`supplier_detail_fields` move there verbatim. A `label:` in the partial or
in a formatter's Hash overrides one field.

### 3.5 Visibility seam (mechanism postponed, D6)

`Fin::AttrFormatHelper#fin_attr_visible?(obj, attr, ctx)` is consulted for
every field and every raw block; it returns `true` for now. A hidden field
produces no row (D7). When the declaration is decided, only this method
changes; the candidates recorded for that decision:

- a per-model map attribute → ability action (`{iban: :show_bank_details,
  represented_person: :show_full, other_datev_columns: :show_raw}`, default
  `:show`), the actions declared in `Wsjrdp2027::VariousAbility`, checked with
  `can?(action, record)` — the `TableDisplays::Column#allowed?` idiom;
- raw CanCanCan attribute rules (`can :show, Model, [:iban]`,
  `can?(:show, record, :iban)`, cancancan 3.6.1) — expressible only outside the
  Hitobito DSL;
- inline `if can?` around a group in the partial — Hitobito's show-page idiom.

`Fin::AccessHelper`'s `?can_fin=false` switch is the existing way to look at a
page without finance rights and will be the manual check once fields are
gated.

### 3.6 The builder — `fin_detail(record, ctx) do |d| … end`

`app/helpers/fin/detail_helper.rb` + `app/domain/fin/detail_builder.rb`.
Two phases like `Wsjrdp::ExpandableTableBuilder`: the block **declares**
sections into the builder, then `fin_detail` renders them through
`fin/shared/_detail`. A section is a small struct (`kind`, `title`,
`layout`, `blank`, `items` / `html`); no HTML is produced inside the block
except for `d.custom`, which captures hand-written HAML.

Target partial for Kreditoren (`app/views/fin/personal_accounts/_detail.html.haml`):

```haml
-#  Locals: account (WsjrdpPersonalAccount), ctx (Fin::AttrFormatContext)
= fin_detail(account, ctx) do |d|
  - d.header back: personal_accounts_path, back_label: "Zurück zu Kreditoren",
      title: "Kreditor #{account.number}", subtitle: account.name
  - d.attrs :name, :short_name, :aliases, :moss_status
  - d.attrs :moss_account_holder_name, :iban, :bic, :moss_vat_id,
      :moss_default_payment_method, :address, bic: {blank: :dash}
  - d.attrs :moss_default_ledger_account_number, :moss_default_cost_center_number,
      :moss_default_sphere_number, :moss_default_team_name
  - d.attrs :description, :comment, :represented_person
  - d.raw :other_datev_columns, title: "Rohdaten (DATEV)"
  - d.raw :other_moss_columns, title: "Rohdaten (Moss)"
  - d.bookings supplier_bookings(account.number),
      show_all_path: bookings_filter_path([[["any_account", "in", account.number]]]),
      all_label: "In Buchungen-Ansicht öffnen"
```

The builder API:

| call | what it declares |
|---|---|
| `d.header(back:, back_label:, title:, subtitle: nil, toolbar: nil)` | the regular header (§3.8); ignored when `ctx.embedded?` |
| `d.attrs(*attrs, **opts)` | one group of fields in the given order. `opts` keys that are **reserved** (`layout`, `title`, `blank`) configure the group; any other key is an attribute name with per-field options (`bic: {blank: :dash}`, `iban: {label: "IBAN (Moss)", span: 2, align: :end}`) |
| `d.attr(attr, **field_opts)` | a one-field group (or a field of the open `section`) |
| `d.section(title: nil, layout: nil, blank: nil) { … }` | a titled group; inside, `d.attrs` / `d.attr` append to it |
| `d.raw(source, title:, also: [], open: nil, blank: :hide)` | a raw block over one jsonb column (§3.7) |
| `d.custom(title: nil) { … }` | captured HAML (links, forms, the Verknüpfungen block of a booking) |
| `d.bookings(rows, show_all_path:, all_label:)` | sugar for `fin/bookings/_embedded` |

Rendering (`fin/shared/_detail.html.haml` iterating sections,
`_detail_group.html.haml` per layout, `_detail_raw.html.haml`,
`_detail_header.html.haml`):

- **Layouts** (D8): `:list` = the core look, `dl.dl-horizontal.m-0.p-2.border-top`
  with `render "shared/labeled"` pairs (tooltip supported); `:compact` = today's
  `dl.row.small` (`dt.col-sm-3.col-lg-2.fw-normal.text-muted`,
  `dd.col-sm-9.col-lg-10.text-break`); `:grid` = the `_kv_grid` cells
  (`col-6 col-md-4 col-lg-3`, `span: 2`, `align: :end`). The mode default is
  regular → `:list`, embedded → `:compact`; `fin_detail(record, ctx, layout:
  {regular: :grid})` changes the default for one partial, `layout:` on a group
  changes one group. Help lines and blank handling render identically in all
  three, so a layout change never changes content.
- **Blank resolution** (D9), first hit wins: the formatter's `blank:` → the
  field's option → the group's option → the partial's default → `:hide`.
- **Visibility**: `fin_attr_visible?` per field and per raw block; hidden
  fields leave no trace. A group whose fields are all hidden or blank renders
  nothing (no empty `dl`).
- **Label**: formatter `label:` → field option → `captionize`.
- Every value goes through `fin_format_attr(record, attr, ctx)`; the
  builder passes the record and context once, which is the point of the
  block form over `render_attrs(record, …)` per line.

### 3.7 Raw data — `d.raw` and `fin_raw_format_other_<model>`

A raw block lists the entries of one jsonb column (keys are the original CSV
headers, kept verbatim) as monospace `Schlüssel: Wert` lines, the style of the
booking's "Rohdaten (DATEV)". `also: [:datev_short_name,
:datev_nummer_fremdsystem]` appends regular columns to the block, keyed by
their column name (raw semantics: the technical name, not the label). The
block is a `<details>` element: open on the regular page, collapsed in the
embedded pane (`open:` overrides). Blank entries are dropped by default.

Formatting goes through one helper per model (D12):

```ruby
# Returns nil to fall back to the default (dates as stored, numbers as stored,
# true/false, nested JSON compact), a String/HTML for a value, or a Hash /
# DetailValue (e.g. {hide: true}) — the same contract as fin_format_attr.
def fin_raw_format_other_wsjrdp_personal_account(account, key, ctx)
  case [ctx.raw_source, key]
  when [:other_datev_columns, "Zahlungsträger"] then datev_payment_carrier_label(account.other_datev_columns[key])
  when [:other_moss_columns, "VAT Rate"] then "#{account.other_moss_columns[key]} %"
  end
end
```

`ctx.raw_source` names the jsonb column, so a key that occurs in both
exports is unambiguous; regular columns added with `also:` arrive with
`raw_source: nil`. The helper name follows the same model rule as
`fin_format_*` (subclass first, then base class); the STI subclass step
matters for Moss later. `nil` meaning "use the default" is the deliberate
difference to `fin_format_attr` (where `nil` is a blank value): a raw helper
is called for every key and must be able to answer "nothing special" cheaply.

### 3.8 Header

Regular mode only (D10). One markup for every finance detail page, replacing
the three variants that exist today (`personal_accounts/show`,
`bookings/show` + `moss_transactions/show`, `booking_batches/show`):

```haml
= link_to back, class: "btn btn-sm btn-link px-0 mb-2" do
  = icon(:"arrow-left")
  = back_label
%h1.mb-3.d-flex.align-items-baseline.flex-wrap.gap-2
  %span.text-muted.fw-light= title
  - if subtitle.present?
    %span= subtitle
  - if toolbar
    .ms-auto= toolbar
```

`toolbar:` is a captured block (a future "Bearbeiten" button); nothing renders
without it. The page's `Sheet::Fin::PersonalAccount` keeps providing tabs and
the left nav; the `h1` stays in the view as today.

### 3.9 Does it fit Hitobito / Rails, and how does it grow?

- **Same idiom as the core.** Method-name lookup on the view context,
  base-class model names, `captionize` labels, helpers auto-included from the
  engine's `app/helpers` (no wiring in `wagon.rb`), `shared/_labeled` for the
  list layout. Somebody who knows `format_person_email` reads
  `fin_format_wsjrdp_personal_account_iban` without explanation. The `fin_`
  prefix keeps the two chains apart, as `wsjrdp_` does for the wagon's generic
  helpers (`Fin::LabeledRowsHelper` header comment).
- **Two deliberate extensions.** The context argument (Hitobito formatters
  see only the object) and the structured return. `Data.define` is the Ruby
  3.2 way to do the latter; the core's own precedent for "a value plus an
  extra" is `labeled(tooltip:)`. Wrapping plain strings keeps the extension
  invisible to the simple case.
- **Same idiom as the table kit.** The builder block, the two-phase
  declare-then-render, the PORO domain objects under `app/domain/fin`, the
  partial-per-layout under `app/views/fin/shared`.
- **Growth paths.** A new presentation need is a `DetailValue` key; a new
  place a value is shown is a `mode` (or a flag on the context); a new group
  kind is a `section.kind` with one partial; a new model is one partial, one
  helper module and one i18n block; per-field authorization plugs into
  `fin_attr_visible?`; forms can share the partial later by letting a section
  render an input instead of a value when a form builder is present (the
  `input_or_render_attrs` idea, out of scope now).

---

## 4. Implementation, part A + B: kit and Kreditoren

Suggested split into Opus subagents (each with an exclusive file list, each
ending in a `Draft:` commit): **(1) kit domain + helpers + partials + their
specs**, **(2) Kreditoren partial/helper/controller/i18n + controller spec**,
**(3) docs + browser check + rubocop over the whole tree**. (2) depends on
(1); (3) on both.

### A. Kit

New files:

| file | content |
|---|---|
| `app/domain/fin/attr_format_context.rb` | §3.1 |
| `app/domain/fin/detail_value.rb` | §3.3 |
| `app/domain/fin/detail_builder.rb` | the section collector (§3.6): `Section = Data.define(:kind, :title, :layout, :blank, :items, :html, :options)`, `Field = Data.define(:attr, :options)`, reserved keys, `section` nesting, `to_sections` |
| `app/helpers/fin/attr_format_helper.rb` | `fin_format_attr`, `fin_formatter_names`, `fin_call_formatter`, `fin_format_attr_by_type`, `fin_attr_visible?`, `fin_raw_format(obj, key, ctx)` (finds `fin_raw_format_other_<model>` the same way, applies the default) |
| `app/helpers/fin/detail_helper.rb` | `fin_detail(record, ctx, layout: nil, blank: nil, &block)`, label/blank resolution, `fin_detail_layout_for(ctx, override)` |
| `app/views/fin/shared/_detail.html.haml` | iterates sections, dispatches by kind |
| `app/views/fin/shared/_detail_header.html.haml` | §3.8 |
| `app/views/fin/shared/_detail_group.html.haml` | the three layouts; one place that renders `value`, `help`, `tooltip`, the dash |
| `app/views/fin/shared/_detail_raw.html.haml` | §3.7 |

Specs (all green before the commit):

- `spec/domain/fin/attr_format_context_spec.rb`, `detail_value_spec.rb`,
  `detail_builder_spec.rb` — **standalone** (`require_relative`, `module Fin;
  end` first; see `spec/domain/wsjrdp/relaxed_url_query_spec.rb`), run on the
  host with the `spec/domain/wsjrdp/` command. Cover: mode validation,
  `level`/`in_table?`/`lazy?` with and without a table context,
  `with_raw_source`; `wrap` of String/buffer/nil/Hash/DetailValue, unknown key
  raises, `blank_value?` with `false`; reserved-key split, per-field options,
  nesting through `section`, `also:` on raw.
- `spec/helpers/fin/attr_format_helper_spec.rb` — in the test container:
  lookup order with three stub helpers defined in the spec (subclass, base
  class, attribute-only), arity 1 and 2, the type rules (Date, time, Array,
  `_cents`, `_amount`, jsonb raises), fallback into `wsjrdp_format_attr`,
  `fin_raw_format` default vs helper vs `{hide: true}`.
- `spec/helpers/fin/detail_helper_spec.rb` — a `fin_detail` render against a
  stub record: each layout's markup, hidden blank rows vs dash vs empty, the
  header only in regular mode, an all-blank group renders nothing.

### B. Kreditoren

| file | change |
|---|---|
| `app/views/fin/personal_accounts/_detail.html.haml` | **new**, the partial of §3.6 |
| `app/helpers/fin/personal_accounts_helper.rb` | **new**: `fin_format_wsjrdp_personal_account_moss_status` (→ `fin_status_label`), `…_address` (street, `post_code city`, country — today's `bookkeeping_address`, which moves here), `…_iban` (grouped in blocks of four for reading; the same string as stored), `…_represented_person` (→ `assoc_link_with_newtab`), `…_moss_default_ledger_account_number` / `…_cost_center_number` (code + name through `datev_account_names` / `datev_cost_center_names`, i.e. `datev_code_cell`), `…_moss_default_sphere_number`, `…_aliases` (joined; empty array is blank); `fin_raw_format_other_wsjrdp_personal_account` with the two DATEV code fields that have a known meaning (`Adressattyp`, `Zahlungsträger`, codes in `doc/fin/personal_accounts.md`); everything else falls to the defaults |
| `app/controllers/fin/personal_accounts_controller.rb` | `show` loads the record and builds the context: `@account = WsjrdpPersonalAccount.find_by(number: params[:number]) \|\| WsjrdpPersonalAccount.new(number: params[:number])` (a number without master data still shows its bookings, as today), `@ctx = turbo_frame_request? ? Fin::AttrFormatContext.embedded(Wsjrdp::TableContext.new(level: summary_table_state.level, lazy: true)) : Fin::AttrFormatContext.regular` |
| `app/views/fin/personal_accounts/show.html.haml` | the frame wraps `render "fin/personal_accounts/detail", account: @account, ctx: @ctx`; the page branch is `#main= frame` — back link and `h1` now come from `d.header` |
| `app/helpers/fin/bookkeeping_helper.rb` | `supplier_item_detail`, `supplier_detail_fields`, `bookkeeping_address` removed (Sachkonten/Kostenstellen keep `_item_detail` until part C step 1) |
| `config/locales/wsjrdp_2027.de.yml` | `activerecord.models.wsjrdp_personal_account`, `activerecord.attributes.wsjrdp_personal_account.*` for every listed attribute incl. `address` |
| `spec/controllers/fin/personal_accounts_controller_spec.rb` | show as a page: `h1` with the number, `dl.dl-horizontal`, no `dl.row.small`, the raw `<details open>`; show as a frame request (`Turbo-Frame` header, `?l=1`): no `h1`, `dl.row.small`, `<details>` closed, the embedded bookings table present; a blank field leaves no `dt`; an unknown number still renders (fixtures: create records in the spec, no real names or bank data) |
| `spec/helpers/fin/personal_accounts_helper_spec.rb` | the formatters above, incl. the address composition with missing parts |

Index view: unchanged (`detail_src` + `detail_page` already point at the show
URL; the frame id `bkframe-supplier-<number>` must stay in sync with
`t.rows …, id: "supplier"`).

### Docs

- `doc/fin/detail_partials.md` (**new**): the how-to — context, lookup
  order, return values, builder API, layouts, raw blocks, header, how to add a
  model (partial + helper + i18n) — written for the present state, without
  change narration; link it from `AGENTS.md`'s documentation list.
- `doc/wsjrdp/expandable_table.md` §4: one sentence pointing finance details
  to `Fin::AttrFormatContext` as the object a `(row, ctx)` lambda should wrap.

### Manual check (in-app browser, dev DB)

`/fin/bookkeeping/personal_accounts` — expand a row: link line, compact
fields, collapsed raw blocks, bookings table; `/fin/bookkeeping/personal_accounts/700000`
— back link, `h1`, list layout, open raw blocks, bookings. Reset the browser
viewport afterwards if it was resized.

---

## 5. Part C: the other models, in this order (later sessions)

1. **Sachkonten and Kostenstellen** — same shape as Kreditoren
   (`account_item_detail`, `cost_center_item_detail`); afterwards delete
   `fin/shared/_item_detail`, `shared/wsjrdp/_detail_fields` and the
   `*_detail_fields` helpers, and the Buchungsstapel page
   (`booking_batch_detail_fields`) moves along.
2. **DATEV booking** — `_booking_detail`: the field grid becomes `:grid`
   groups with `span`/`align`; the raw section becomes `d.raw
   :other_datev_columns, also: [...]` plus the Beleginfo/Zusatzinformation
   expansion as a `d.custom` (or a raw helper that answers with several
   lines — decide then); Verknüpfungen stays `d.custom`; the `top`/`extra`
   host slots stay as captured sections around the partial.
3. **Moss transaction** — `_detail`: the inline row building becomes `d.attrs`
   with `fin_format_moss_transaction_*`, STI overrides per kind, and — new —
   raw blocks for `other_moss_columns` on all three levels.
4. **Beitragsbuchung** (`accounting_entries/_detail`) and **Kontobewegung**
   (`/fin/tx`, a `standard_form` page with read-only rows): read-only parts
   through the builder, editable fields stay in the form — how the two mix is
   the open design point of that step.
5. Retire `shared/wsjrdp/_kv_grid` once nothing renders it.

---

## 6. Rules for the implementing session

- Specs only in the test container (`docker exec -e RAILS_ENV=test -e
  RAILS_TEST_DB_NAME=hitobito_test_wsjrdp_2027 -e
  RAILS_DB_NAME=hitobito_test_wsjrdp_2027 -e SKIP_INIT=1 -e
  DISABLE_TEST_SCHEMA_MAINTENANCE=1 -e DISABLE_SPRING=1 -e NO_COVERAGE=1
  development-rails-1 bash -c 'cd /usr/src/app/hitobito_wsjrdp_2027 && bundle
  exec rspec <paths>'`), standalone domain specs on the host; never the whole
  suite, never the dev DB. Known pre-existing failures:
  `spec/models/datev_booking_legs_spec.rb` (test-DB schema drift).
- `bundle exec rubocop -a .` from the wagon root, offence-free.
- One `Draft:` commit per agent with exactly its files; no push, no branch
  switch, no stash; do not touch `doc/TODOs/*`.
- No real names, amounts, IBANs or supplier names in code, specs or docs;
  account numbers such as `700000` are fine.
- Present-state wording in docs and comments (no "previously/now").

---

## 7. Assumptions to confirm at the start of the implementing session

1. STI subclass name is looked up **before** the base class (§3.2) — an
   extension of Hitobito's base-class-only rule.
2. A formatter may take `(obj)` or `(obj, ctx)`; a raw helper always
   `(obj, key, ctx)`.
3. `ctx.raw_source` is the way a raw helper tells the two jsonb columns
   apart (the user's signature names only `object, key, context`).
4. `nil` from a raw helper means "default formatting"; `nil` from a field
   formatter means "blank value".
5. A number without a master-data record still renders (stub record), as
   the page does today.
6. The `also:` columns of a raw block are keyed by their column name, not by
   the i18n label.
7. The header's `h1` lives in the partial (regular mode), inside the page's
   turbo frame wrapper — harmless, since a lazy load never asks for regular
   mode.
