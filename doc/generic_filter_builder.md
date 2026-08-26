# Generic CNF filter builder — model & Rails plan

Status: **design note / work in progress.** No code is being written yet; this
document is the shared model we agree on first. Code snippets are illustrative
sketches, not final APIs.

The goal is a **generic, reusable** condition builder (à la getmoss.com's
"Bedingungen"): the user freely combines AND/OR conditions over the rows of *some*
dataset — a single table or a join of tables — and the same engine + UI works for
the DATEV bookings list, and for any other model later, just by declaring which
*attributes* (fields) can be filtered.

---

## Part 1 — The conceptual model (generic, table-agnostic)

### 1.1 Shape: Conjunctive Normal Form (AND of ORs)

A filter is a boolean predicate over rows, structured as exactly **two levels**:

```
Filter          := Slot  AND  Slot  AND  … AND  Slot          (conjunction)
Slot            := Cond  OR   Cond  OR  … OR   Cond           (disjunction)
Cond (atom)     := attribute  operator  operand(s)            (a single, negatable predicate)
```

- **Filter** = AND of **slots** ("UND" rows). Order is irrelevant (AND is commutative).
- **Slot** = OR of **conditions** ("oder"). May **mix attributes** in one slot. Order irrelevant.
- **Condition / atom** = one leaf predicate: an `attribute` (field or expression),
  an `operator`, and its `operand(s)`. Negation (`ist` / `ist nicht`) is a property
  of the **condition only** — there is no slot-level negation.

This is **Conjunctive Normal Form (CNF)**. It is deliberately *flat* (no deeper
nesting): every condition builder can be explored/collapsed in place, and it
extends horizontally (more conditions per slot) and vertically (more slots)
without new nesting UI.

**Why CNF is enough.** Every boolean formula over the atoms (arbitrary AND/OR/NOT
nesting) has an equivalent CNF, so any filter the user can imagine is expressible —
*provided* two properties hold, which this model guarantees:

1. a slot's OR may contain **arbitrary literals** (mixed attributes), and
2. **negation exists per literal** (`ist nicht`, `not_in`, complementary operators).

**The one caveat — clause blow-up.** Flattening a naturally OR-over-AND expression
into CNF can multiply the number of slots. Example:

```
(A AND B) OR (C AND D)
  ≡  (A OR C) AND (A OR D) AND (B OR C) AND (B OR D)     # 4 slots
```

Always *possible*, occasionally *verbose*. Expressiveness is otherwise bounded only
by which **atoms** (attribute × operator combinations) a dataset registers.

### 1.2 Vocabulary

| Term | Meaning |
|---|---|
| **Attribute** | A filterable field/expression on the dataset (e.g. `Betrag`, `Kostenstelle`, `Kreditor`). Has a **type**, an **explicit list of supported operators**, and a **`short_key`** used only in the URL encoding. |
| **Type** | The kind of value an attribute holds (`reference`, `decimal`, `date`, `text`, `enum`). A type is the *library* of operator implementations plus the default UI control; **which** of its operators an attribute offers is declared explicitly per attribute, never derived. |
| **Operator** | How operand(s) become a predicate (`in`, `not_in`, `gte`, `between`, `contains`, `present`, `blank`). Implemented in a type; defines operand **arity**, the SQL/Arel it produces, and a **`short_key`** (≤ 2–3 chars) for the URL encoding. Operator keys and short_keys are **globally unique** — one vocabulary across all types (§2.2). |
| **Condition / Atom** | A concrete leaf: `attribute + operator + operands`. Produces one SQL predicate (TRUE/FALSE/UNKNOWN). |
| **Slot** | An OR-group of conditions. |
| **Query / Filter** | An AND-list of slots. |

The **engine is agnostic**: it never knows "bookings". Each atom is just a factory
that yields a bound SQL predicate; the CNF layer only combines those predicates
with `AND` / `OR`. New datasets = new attribute declarations, nothing else.

### 1.3 Evaluation semantics — SQL three-valued logic (3VL)

We adopt the database's **native** semantics — no custom NULL handling. Every
predicate is TRUE, FALSE, or **UNKNOWN**; any comparison involving `NULL` is
UNKNOWN; and `WHERE` returns a row only when the expression is **TRUE** (FALSE and
UNKNOWN are both dropped). `NULL` is testable *only* with `IS NULL` / `IS NOT NULL`.

| Atom | Arel / SQL | Missing (NULL) value |
|---|---|---|
| `ist X` | `col = 'X'` | excluded |
| `ist {A,B}` | `col IN ('A','B')` | excluded |
| `ist nicht X` | `col <> 'X'` | **excluded** |
| `ist nicht {A,B}` | `col NOT IN ('A','B')` | **excluded** |
| `≥ a`, `< a`, `in [a,b]` | `col >= a` (`AND col <= b`) | excluded |
| `enthält "t"` | `col ILIKE '%t%'` | excluded |
| `hat Wert` (Beliebiger) | `col IS NOT NULL` | (this *is* the presence test) |
| `ist leer` | `col IS NULL` | matches only NULL |

Two consequences to keep in mind (and to document for users):

- **Negation excludes missing values.** `Kostenstelle ist nicht 3` does *not*
  return rows with **no** cost centre (`NULL <> 3` is UNKNOWN).
- **NULL escapes both sides of a split.** A NULL value matches neither `≥ a` nor `< a`.

Both are *expressible*, not hidden, thanks to OR-slots + a presence atom:

```
Kostenstelle ist nicht 3   ODER   Kostenstelle ist leer      # "3-excluded, missing included"
```

**One mental rule for the whole system:**

> A row is returned **iff every non-empty slot contains at least one condition that
> is definitely TRUE for that row.** A missing value simply fails to make its atom
> TRUE.

(Within a slot, `UNKNOWN OR TRUE = TRUE`, so a NULL in one alternative never spoils
a slot another alternative satisfies. Across slots, a slot with only UNKNOWN/FALSE
atoms drops the row.)

**Neutral/empty:** an empty slot (no conditions, or conditions lacking operands) is
**ignored**; a query with no effective slots ⇒ **no filter** (all rows).

### 1.4 Normalization notes

- **Multi-select is sugar for OR.** `X ist {A,B,C}` ≡ three OR-conditions
  `X ist A / X ist B / X ist C` in one slot. Stored as one condition for
  compactness; means the same.
- **De Morgan for negated sets.** `X ist nicht {A,B}` = `X ∉ {A,B}` =
  `X ≠ A AND X ≠ B` — but it is **one atom** (`NOT IN`), so it does not introduce
  an AND *inside* the OR-slot; the conjunction is internal to the atom.
- **Ranges are one atom.** `Betrag in [a,b]` is a single condition (internally
  `>= a AND <= b`, **closed** on both ends for amounts and dates alike). Several
  disjoint intervals ⇒ OR them in one slot (`in [a,b] OR in [c,d]`) or AND them
  across slots — the user's choice.

### 1.5 Hidden conditions (host-supplied)

Beyond the user-built filter, a **consumer of the filtering system** (the host
controller) may supply **hidden conditions**: conditions in the same vocabulary
that are always **AND**-combined with the user's filter, but **never rendered,
never editable, and never carried in the URL**. Because the top level is already an
AND, each hidden condition is simply an extra slot conjoined ahead of the user's
slots, so the result stays a CNF:

```
effective filter  =  hidden slot(s)   AND   user_query
```

They exist for scoping/safety that must not be user-overridable. In the bookings
case the host supplies **`status = active`** as a hidden condition, so the list
shows only active bookings; soft-deleted rows are simply not visible in the UI
(acceptable for now). Since hidden conditions come from the host, not from request
params, they **cannot be bypassed by editing the URL**.

This complements — and is distinct from — *hidden attributes* (a host may hide an
attribute so the user cannot filter on it at all; see today's `hidden_filters` in
`Fin::BookingsFiltering`): a hidden *attribute* removes a control, a hidden
*condition* forces a value. The per-account detail page uses both — it hides the
account attribute **and** fixes `account = X` as a hidden condition.

---

## Part 2 — Rails structuring plan (first parts)

### 2.1 Layers

```
                       ┌───────────────────────────────────────────┐
 declares attributes   │  Filtering::Schema  (per model / per join) │
 ──────────────────▶   │   base relation + registered Attributes    │
                       └───────────────┬───────────────────────────┘
                                       │ catalog (JSON)         ▲ options (JSON / endpoint)
                                       ▼                        │
   ┌───────────────┐   value (JSON)  ┌────────────────┐   scope ┌───────────────────────┐
   │ Generic JS UI │ ──────────────▶ │ Filtering::Query│ ──────▶ │ Filtering::Compiler   │
   │ (builder)     │ ◀────────────── │ (CNF value obj) │         │  Query+Schema → .where │
   └───────────────┘   catalog+value └────────────────┘         └───────────────────────┘
```

- **Schema / registry** — the registered **Attributes** of a dataset. Flavours
  (§2.2): a **template** declared without any base relation (columns as
  names/lambdas), **derived** templates refined from it (add/remove attributes,
  replace operator lists), and a **bound** schema = template + a concrete
  `ActiveRecord::Relation` (a model scope or a join), resolved via `bind(base)` —
  possibly per request. The bound schema produces the **catalog** (JSON) the UI
  renders from — a descriptive projection, never the authority (see "Schema vs.
  catalog", §2.2).
- **Value objects** — `Query → Slot → Condition`: the CNF tree. Parsed from and
  serialized to JSON; the *only* thing the UI edits.
- **Compiler** — turns `Query + Schema` into an `ActiveRecord::Relation` via Arel
  (bound params, allow-listed columns/operators).
- **Generic UI** — a JS component driven purely by `catalog` + `value`. It knows
  control *kinds* (`multiselect`, `number_range`, `date_range`, `text`, `none`),
  never the specific table.

### 2.2 Core generic classes (illustrative Ruby)

Types and operators are **reusable across datasets**; you only ever declare
attributes. A type is purely the *library* of operator implementations — every
attribute names the operators it supports **explicitly** (§2.11 #8).

```ruby
module Filtering
  # GLOBAL operator vocabulary: key <-> short_key is ONE bijection for the whole
  # system. Technically uniqueness would only be needed within one attribute's
  # operator set (a condition always names its attribute first), but the global
  # rule keeps every URL and tree readable without knowing the attribute's type,
  # and makes collisions impossible as the operator set grows. Adding an operator
  # later = one line here + its per-type implementation(s).
  OPERATOR_VOCABULARY = {
    in:       :in,   # membership ("ist")
    not_in:   :ni,   # negated membership ("ist nicht")
    present:  :pr,   # IS NOT NULL ("hat Wert")
    blank:    :bl,   # IS NULL ("ist leer")
    gte:      :ge,   # >=  (decimal, date, ...; date label "ab")
    lt:       :lt,   # <   (date label "vor")
    between:  :bt,   # closed range [a, b]
    contains: :ct,   # substring ILIKE ("enthält")
  }.freeze

  # How operand(s) become a predicate, plus UI metadata. `arity` tells the UI how
  # many operands to collect: :none | :one | :two(range) | :many(set).
  # The key MUST be in OPERATOR_VOCABULARY, and the short_key always comes from
  # there (never passed per instance) -- so key/short_key stay globally consistent.
  # The same KEY may be implemented by several types (gte on decimal and on date
  # differ only in label and operand casting): that is one operator concept with
  # per-type implementations, not a collision.
  class Operator
    attr_reader :key, :short_key, :label, :arity
    def initialize(key:, label:, arity:, &to_arel)
      @key, @label, @arity, @to_arel = key, label, arity, to_arel
      @short_key = OPERATOR_VOCABULARY.fetch(key)   # raises on unregistered key
    end
    # column: an Arel attribute / SQL expression; operands: parsed, typed values.
    def to_arel(column, operands) = @to_arel.call(column, operands)
    def as_json(*) = {key:, label:, arity:}
  end

  # A value kind: the library of operator implementations for it + the UI control
  # to render. Attributes pick from this library explicitly; nothing is offered
  # by default.
  class Type
    attr_reader :key, :control, :operators
    def initialize(key:, control:, operators:)
      @key, @control, @operators = key, control, operators.index_by(&:key)
    end
    def operator(k) = @operators.fetch(k)   # raises on unknown key (declaration-time check)
  end
end
```

Predefined, reusable types (the atom vocabulary lives here, once):

```ruby
module Filtering::Types
  REFERENCE = Filtering::Type.new(key: :reference, control: "multiselect", operators: [
    Filtering::Operator.new(key: :in,      label: "ist",       arity: :many) { |c, v| c.in(v) },
    Filtering::Operator.new(key: :not_in,  label: "ist nicht", arity: :many) { |c, v| c.not_in(v) },
    Filtering::Operator.new(key: :present, label: "hat Wert",  arity: :none) { |c, _| c.not_eq(nil) },
    Filtering::Operator.new(key: :blank,   label: "ist leer",  arity: :none) { |c, _| c.eq(nil) },
  ])

  DECIMAL = Filtering::Type.new(key: :decimal, control: "number_range", operators: [
    Filtering::Operator.new(key: :gte,     label: "≥",          arity: :one) { |c, v| c.gteq(v[0]) },
    Filtering::Operator.new(key: :lt,      label: "<",          arity: :one) { |c, v| c.lt(v[0]) },
    Filtering::Operator.new(key: :between, label: "im Bereich", arity: :two) { |c, v| c.gteq(v[0]).and(c.lteq(v[1])) },
    Filtering::Operator.new(key: :present, label: "hat Wert",   arity: :none){ |c, _| c.not_eq(nil) },
    Filtering::Operator.new(key: :blank,   label: "ist leer",   arity: :none){ |c, _| c.eq(nil) },
  ])

  # Same operator KEYS as decimal (one global concept), date-specific labels.
  DATE = Filtering::Type.new(key: :date, control: "date_range", operators: [
    Filtering::Operator.new(key: :gte,     label: "ab",         arity: :one) { |c, v| c.gteq(v[0]) },
    Filtering::Operator.new(key: :lt,      label: "vor",        arity: :one) { |c, v| c.lt(v[0]) },
    Filtering::Operator.new(key: :between, label: "im Bereich", arity: :two) { |c, v| c.gteq(v[0]).and(c.lteq(v[1])) },
    Filtering::Operator.new(key: :present, label: "hat Wert",   arity: :none){ |c, _| c.not_eq(nil) },
    Filtering::Operator.new(key: :blank,   label: "ist leer",   arity: :none){ |c, _| c.eq(nil) },
  ])

  # `text` can span several columns; `contains` matches in ANY of them (OR). No
  # present/blank for now: a multi-column "has value" would need an any-vs-all
  # aggregation decision, so add those (and settle that choice) only when a text
  # attribute actually needs them.
  TEXT = Filtering::Type.new(key: :text, control: "text", operators: [
    Filtering::Operator.new(key: :contains, label: "enthält", arity: :one) { |cols, v|
      Array(cols).map { |c| c.matches("%#{sanitize_like(v[0])}%") }.reduce(:or)
    },
  ])

  ENUM = Filtering::Type.new(key: :enum, control: "select", operators: [
    Filtering::Operator.new(key: :in,     label: "ist",       arity: :many) { |c, v| c.in(v) },
    Filtering::Operator.new(key: :not_in, label: "ist nicht", arity: :many) { |c, v| c.not_in(v) },
  ])
end
```

Operator keys and short_keys are **globally unique** — one vocabulary
(`OPERATOR_VOCABULARY`) for the whole system, deliberately stricter than the
per-attribute uniqueness resolution would require. Consequences: any condition or
URL is readable without knowing the attribute's type; a new operator is added by
extending the vocabulary (one line, collision-checked at boot) plus its per-type
implementations; and the same key implemented in several types (`gte` on decimal
and date) is *sharing one concept*, not a clash.

Notes:
- `c.in([])` (empty set) yields `1=0` in Arel; the **compiler** drops conditions
  whose operand count doesn't satisfy the operator's `arity`, so an unfinished
  condition is *ignored*, never `1=0`. (Ties into "empty is neutral".)
- `between` is one predicate (`gteq.and(lt)`) — a compound *atom*, still a single
  OR-leaf. This is the only place an internal AND appears, and by design.

An **Attribute** binds a type to a column/expression and **explicitly** lists its
operators:

```ruby
module Filtering
  class Attribute
    attr_reader :key, :short_key, :label, :group, :type, :column, :options
    # operators: REQUIRED — the explicit list of operator keys this attribute
    #          supports, resolved against the type's implementation library.
    #          Nothing is ever derived implicitly from the type; an unknown key
    #          raises at declaration time (host-authored, so fail loud).
    # short_key: short name used in the URL (Rison) encoding only; JSON tree and
    #          catalog always use the full `key`. Defaults to the key itself.
    # column:  in a BOUND declaration — an Arel attribute / SQL expression.
    #          In a TEMPLATE declaration (see Schema below) — a symbol, resolved as
    #          base.arel_table[sym] at bind time, or a lambda ->(t) { … } receiving
    #          the arel_table (return an array for multi-column, e.g. text).
    # options: for reference types — how the UI gets [value, label] pairs
    #          (inline list, or a search endpoint for large sets like Kreditor).
    # catalog: false = registered for compilation only, omitted from the catalog
    #          (so it can back a hidden condition, §1.5, without a UI control).
    # variant_group: several attributes may form ONE picker entry (labelled with
    #          this string); the editor offers the members as sub-variants and the
    #          first declared member is the default (e.g. the text search over
    #          Buchungstext / Belege / beide; see Part 4, UX iteration 2).
    def initialize(key:, label:, type:, column:, operators:, short_key: key,
      group: nil, options: nil, catalog: true)
      @key, @short_key, @label, @type, @column, @group, @options, @catalog =
        key, short_key, label, type, column, group, options, catalog
      @operators = operators.to_h { |k| [k, type.operator(k)] }  # raises on unknown key
    end

    def catalog?      = @catalog
    def operators     = @operators.values
    def operator(key) = @operators[key]    # nil if not offered on this attribute

    def as_json(*)
      { key:, label:, group:, type: type.key, control: type.control,
        operators: operators.map(&:as_json),
        options: options&.descriptor }   # {mode:"inline",values:[...]} | {mode:"remote",endpoint:"..."}
    end
  end
end
```

(`short_key`s are a codec concern: they never appear in the catalog or in the
canonical JSON tree, only in the Rison URL form, §2.8.)

A **Schema** is the attribute registry. It comes in four flavours so one
definition can serve several tables/scopes:

- **Template** — `Schema.define { |s| … }` with **no base relation**. Columns are
  declared abstractly (symbols or lambdas, see Attribute above). One template, many
  bases.
- **Derived** — `parent.derive { |s| … }`: a **new** template refined server-side
  from an existing one — **add** attributes, **remove** attributes, or **replace an
  inherited attribute's operator list** (narrow or extend). Copy-on-derive: the
  parent stays untouched; the derived template is named, reused and bound like any
  other. (Contrast `bind(only:)` below, which is just a lightweight per-bind subset
  — derive when the variant deserves a name and its own shape.)
- **Bound** — `template.bind(base)` resolves every column against a concrete
  `ActiveRecord::Relation` and yields the object the Compiler/catalog consume.
  Binding is cheap (resolve + validate), so it can happen **per request** — e.g.
  switching between `DatevBooking.all` and `DatevBooking.legs` on user input.
  `bind(base, only: […])` applies a template **partially** (only the attributes
  that make sense on that base).
- **Direct-concrete** — `Schema.define(base: DatevBooking.all) { |s| … }` is sugar
  for declare-then-bind in one go, for the common single-base case.

```ruby
module Filtering
  class Schema                                    # the TEMPLATE
    def self.define(base: nil, &block)
      template = new.tap(&block)
      base ? template.bind(base) : template       # sugar: declare + bind in one go
    end

    # Attribute keys and short_keys must be unique WITHIN the schema (checked
    # here at declaration time); re-declaring an existing key replaces it.
    def attribute(key:, **opts)
      (@attributes ||= {})[key.to_sym] = Attribute.new(key:, **opts)
    end

    # --- derivation (server-side refinement; parent untouched) ---------------
    def derive(&block) = self.class.from_attributes(@attributes.dup).tap(&block)

    def remove(*keys) = keys.each { |k| @attributes.delete(k.to_sym) }

    # Replace an inherited attribute's operator list (narrow OR extend; keys are
    # resolved against the type's implementations, so unknown keys raise here).
    def operators(key, operator_keys)
      @attributes[key.to_sym] = @attributes.fetch(key.to_sym)
        .with(operators: operator_keys)
    end

    # Template + concrete relation -> BoundSchema. Resolves symbol/lambda columns
    # against base.arel_table (multi-column lambdas return arrays); `only:` takes
    # the named subset of attributes.
    def bind(base, only: nil)
      attrs = only ? @attributes.slice(*only.map(&:to_sym)) : @attributes
      BoundSchema.new(base:, attributes: resolve_columns(attrs, base))
    end
  end

  class BoundSchema                               # what Compiler + catalog consume
    attr_reader :base, :attributes                # attributes: {Symbol => Attribute}, columns resolved
    def find(key) = @attributes.fetch(key.to_sym)
    # Only catalog:true attributes reach the UI; hidden-condition-only ones (e.g.
    # status) are registered but omitted here.
    def catalog = {attributes: @attributes.values.select(&:catalog?).map(&:as_json)}
  end
end
```

Note for `DatevBooking.legs`: the legs UNION-ALL subquery is aliased
`AS datev_bookings`, so symbol columns resolve against the same arel_table and most
of the bookings template applies unchanged; legs-only columns (`leg_amount`,
`leg_account`, `leg_side`) are added in a **derived** schema (see §2.9).

#### Schema vs. catalog

Two related but firmly separated things:

| | **Schema** | **Catalog** |
|---|---|---|
| What | The full, authoritative definition (Ruby object) | A UI-facing **projection** of a bound schema (JSON document) |
| Lives | Server only — never leaves it | Shipped to the browser with the page |
| Contains | Columns / SQL expressions, operator **implementations**, options *sources* (relations), `short_key`s, hidden (`catalog: false`) attributes, hidden conditions' backing | Only `catalog: true` attributes, and per attribute only what rendering needs: key, label, group, control, offered operators (key/label/arity), options **descriptor** (inline values or endpoint URL) |
| Role | **Authoritative**: the allow-list the compiler and URL codec enforce | **Descriptive**: tells the UI what to draw — nothing more |

The catalog deliberately contains no SQL, no column names, no short_keys and no
hidden attributes. And it grants nothing: whatever the client sends back is
re-validated against the *schema* (§2.3), so a manipulated catalog (or hand-built
request) cannot widen the filter beyond what the schema defines.

CNF **value objects** — the tree the UI edits. The wire form is deliberately
**compact and positional**: the tree is a bare array of slots, a slot is an array
of conditions, and a condition is the flat array `[attribute, operator, *operands]`
— nesting depth alone disambiguates the three levels, no key names needed. The JSON
tree uses the **regular** attribute/operator keys (short_keys are URL-codec-only,
§2.8):

```jsonc
[ [ ["amount", "between", 10000, 25000] ],     // slot 1: one condition
  [ ["cost_center", "in", "3150"] ] ]          // slot 2 (AND between slots)
```

```ruby
module Filtering
  Condition = Data.define(:attribute, :operator, :operands)   # symbols + array
  Slot      = Data.define(:conditions)                        # Array[Condition]

  Query = Data.define(:slots) do                              # Array[Slot]
    # Wire form uses strings; internally attribute/operator are symbols to match
    # the registry. parse interns at the boundary (symbols are GC'd in modern
    # Ruby, so interning arbitrary input is safe); as_json emits strings.
    def self.parse(tree)
      slots = Array(tree).map do |conditions|
        Slot.new(conditions: Array(conditions).map { |c|
          attr, op, *operands = Array(c)
          Condition.new(attribute: attr&.to_sym, operator: op&.to_sym, operands:)
        })
      end
      new(slots:)
    end

    def as_json(*)
      slots.map { |s|
        s.conditions.map { |c| [c.attribute.to_s, c.operator.to_s, *c.operands] }
      }
    end
  end
end
```

The operand count is validated against the operator's declared arity in the
compiler, so the flat `[attr, op, *operands]` form is unambiguous — the first two
elements are always names, everything after is data.

The **Compiler** — allow-listed, param-bound, 3VL-native:

```ruby
module Filtering
  class Compiler
    def initialize(schema) = @schema = schema   # a BoundSchema (columns resolved)

    # Query + base relation -> filtered ActiveRecord::Relation. `hidden` are
    # host-supplied slots (§1.5) AND-combined ahead of the user's slots; they are
    # never read from params and never serialized, so they cannot be bypassed.
    def apply(query, relation: @schema.base, hidden: [])
      (hidden + query.slots).filter_map { |slot| slot_predicate(slot) }
                            .reduce(relation) { |rel, pred| rel.where(pred) }  # AND across slots
    end

    private

    def slot_predicate(slot)
      slot.conditions.filter_map { |c| condition_predicate(c) }
          .reduce { |a, b| a.or(b) }                           # OR within slot; nil if empty -> slot skipped
    end

    def condition_predicate(cond)
      attr = @schema.attributes[cond.attribute] or return nil  # unknown attribute -> ignore
      op   = attr.operator(cond.operator) or return nil        # operator not offered here -> ignore
      operands = cast(attr.type, op, cond.operands)
      return nil unless arity_satisfied?(op, operands)         # unfinished condition -> ignore (neutral)
      op.to_arel(attr.column, operands)
    end
  end
end
```

Registration for a concrete dataset is then tiny and declarative (see §2.9).

### 2.3 Security & correctness

- **Allow-list everything symbolic.** Only registered attribute keys and the
  operators **explicitly listed on that attribute** ever reach Arel; unknown keys
  are dropped (same spirit as today's `SORTABLE`/`COLUMN_ABBREVIATIONS`
  allow-lists). The same applies to `short_key`s in the URL codec.
- **Never string-interpolate columns.** Columns are Arel attributes/expressions
  from the Schema; operands are bound values. `ILIKE` operands are `LIKE`-escaped.
- **Validate operand arity/type** in the compiler (`cast` + `arity_satisfied?`);
  invalid/half-finished conditions are ignored, matching "empty is neutral".
- **3VL is inherited** from SQL — no home-grown NULL coalescing, no implicit
  `OR IS NULL`. Users opt into NULLs explicitly with a `blank` atom.

**Hidden-condition integrity (§1.5).** The compiler drops any condition whose
attribute/operator it can't resolve — the right behaviour for untrusted *user*
input, but dangerous for a host-supplied **hidden** condition, which is usually a
*safety scope* (e.g. `status = active`). A typo there would silently disable the
scope and leak data (soft-deleted rows). Three ways to handle it:

| Option | What | Pro | Con |
|---|---|---|---|
| **A — do nothing** | hidden conditions dropped silently, like user input | simplest; one code path | a bad key disables the scope with **no signal**; only acceptable if no hidden condition is security-relevant |
| **B — validate at registration/boot** *(recommended)* | when the Schema + its hidden conditions are defined (host constants, known at boot), assert each resolves to a known attribute + operator with satisfiable arity; raise otherwise | catches typos at deploy; **zero** request-time cost; fails loud | needs hidden conditions known at schema-build time (they are) |
| **C — raise at compile time** | compiler distinguishes hidden vs user slots and *raises* (not drops) if a **hidden** condition fails | also catches dynamically-built hidden conditions | surfaces at request time, not deploy |

**Decision (v1): A — silent drop, with a documented loophole.** We take the
simplest behaviour for now: hidden conditions are dropped like user input, no extra
validation.

> ⚠ **KNOWN LOOPHOLE — hidden conditions fail silently.** A typo in a host-supplied
> safety condition (e.g. `status = active`) would be dropped with **no signal** and
> could expose data (soft-deleted rows). Tolerated for v1 only because the sole
> hidden condition is low-stakes and host-authored (constant, code-reviewed). **Come
> back and adopt Option B (boot-time validation) before any hidden condition becomes
> genuinely security-critical.**

### 2.4 The generic HTML/JS representation

The UI is a **pure function of two JSON documents** and knows nothing about any
specific table. The catalog is the descriptive projection of the bound schema —
see "Schema vs. catalog" in §2.2 for the exact boundary:

**Catalog** (server → UI), from `BoundSchema#catalog`:

```jsonc
{ "attributes": [
  { "key": "amount", "label": "Betrag", "group": "Felder", "type": "decimal",
    "control": "number_range",
    "operators": [ {"key":"gte","label":"≥","arity":"one"},
                   {"key":"between","label":"im Bereich","arity":"two"}, … ] },
  { "key": "cost_center", "label": "Kostenstelle", "type": "reference",
    "control": "multiselect",
    "operators": [ {"key":"in","label":"ist","arity":"many"},
                   {"key":"not_in","label":"ist nicht","arity":"many"},
                   {"key":"blank","label":"ist leer","arity":"none"}, … ],
    "options": { "mode": "inline", "values": [["3","3 …"],["5","5 …"]] } },
  { "key": "offsetting_account", "label": "Gegenkonto", "type": "reference", "control": "multiselect",
    "operators": [ … ], "options": { "mode": "remote", "endpoint": "/fin/bookings/filter_options/offsetting_account" } }
] }
```

**Value** (UI ⇄ server), the compact positional CNF tree from `Query#as_json`
(§2.2 — slots > conditions > `[attribute, operator, *operands]`, full keys):

```jsonc
[ [ ["amount", "between", 10000, 25000] ],
  [ ["cost_center", "in", "3150"] ] ]
```

**Rendering rules (generic):**
- Render each **slot** as a row (the "UND" separators between rows are implicit).
- Inside a slot, render each **condition** as a chip; the `⊕ oder` and `⌄` open the
  **attribute picker** (grouped by `group`), then the **operator** list for that
  attribute's type, then an operand control chosen by `control` + `arity`:
  `multiselect` (searchable; options inline or fetched from `endpoint`),
  `number_range` / `date_range` (one or two inputs by arity), `text` (one input),
  `none` (no operand, e.g. `hat Wert` / `ist leer`).
- `🗑` removes a slot; `✕` removes a condition; "'UND' Bedingung hinzufügen"
  appends an empty slot.
- On **Anwenden**, POST the **value** JSON; the server encodes it to Rison and
  redirects (PRG) to `?filter=<rison>` (§2.8). Edits before Apply mutate only the
  client-side value — nothing runs and the URL does not change until Apply.

Because the UI dispatches purely on `control`/`arity`/`options`, **adding a new
dataset or attribute needs zero UI changes** — only a new Schema declaration on
the server.

### 2.5 Control kinds and operand schemas (the UI ↔ atom contract)

Every operator declares an **arity**; the attribute's **control** decides the
widget. Operands are the **tail of the condition array** (after attribute and
operator) and are always plain JSON scalars (strings / numbers / ISO-8601 date
strings); the server casts them per attribute type.

| control | arity | example condition (JSON) | widget |
|---|---|---|---|
| `multiselect` | `many` | `["cost_center","in","3150","3160"]` | searchable chip multiselect (options inline or remote) |
| `select` | `many` | `["account_type","in","BANK"]` | plain select for a small fixed enum (e.g. Kontenart) |
| `number_range` | `one` / `two` | `["amount","gte",100]` / `["amount","between",100,500]` | one or two number inputs (accepts German comma; stored as number) |
| `date_range` | `one` / `two` | `["booking_date","gte","2026-05-01"]` / `[…,"between",from,to]` | one or two date pickers (ISO-8601 in JSON) |
| `text` | `one` | `["text","contains","Pfand"]` | single text input (ILIKE) |
| `none` | `none` | `["cost_center","blank"]` | no widget — presence atoms `hat Wert` / `ist leer` |

Rule: a condition whose operands don't satisfy its operator's arity is
**incomplete** — the UI keeps it in edit mode and does **not** emit it; if one
reaches the server anyway, the compiler drops it (§2.3, "empty is neutral").

### 2.6 The component: state, rendering, data flow

- **Single source of truth = the value JSON.** Everything else (which picker is
  open, an in-progress condition) is transient UI state.
- **Render:** for each slot → a row; for each condition → a chip
  `«attribute.label» «operator.label» «formatted operands» ✕`; a trailing
  `oder ⊕` / `⌄` opens the add/edit picker; below all rows, "'UND' Bedingung
  hinzufügen". `🗑` deletes a slot.
- **Add flow:** pick attribute (grouped by `group`) → pick operator (from
  `attribute.operators`) → fill operands via the control widget → commit into the
  slot. **Edit flow:** clicking a chip reopens the operator+operand editor
  (Speichern / Entfernen), exactly like Moss.
- **Collapse (⌄):** a slot with many conditions may collapse to a summary
  (`Betrag …, +2`) to save space — purely visual, never changes the value.
- **Data flow (apply model, §2.8):** commits mutate only the client-side value;
  nothing is submitted and the URL does not change until **Anwenden**. On Apply the
  value is POSTed and the server redirects (PRG) to `?filter=<rison>`. Debouncing
  applies only to the remote-options typeahead (§2.7) — never to running the query.
- **Framework fit:** a single Stimulus controller (hitobito already uses
  Turbo/Stimulus) receives `catalog` + `value` via a JSON `<script type>` tag or
  data attributes and renders entirely client-side; the only server round-trips
  are remote-option lookups (§2.7) and running the query. No server-rendered
  partial per keystroke.

### 2.7 Options and the label/search endpoint

Reference attributes need two things: **options** to pick from and **labels** for
already-chosen values.

- **Small, stable sets** (Kostenstelle ≈ 82, Sachkonto ≈ 61, Status): declare
  `options: {mode: "inline", values: [[value, label], …]}` — shipped in the catalog,
  no round-trip.
- **Large / growing sets** (Kreditoren 700xxx, users): declare
  `options: {mode: "remote", endpoint: "…"}` and back it with a search endpoint.

**Search endpoint contract** (scope is fixed by the attribute; the client cannot
widen it):

```jsonc
// GET /fin/bookings/filter_options/offsetting_account?q=DB&page=0
{ "options": [ ["700011", "DB Fernverkehr AG 700011"], … ],
  "has_more": true }
```

- `q` matches number **or** name (ILIKE), paged (~20/page); empty `q` = first page.
- Ordered deterministically (by number); `page` continues.

**Label resolution for selected values.** The value JSON stores only raw values
(`"700011"`); chips need labels even for values not on the current page, and a
shared URL must render correctly. Resolve them **server-side** via a `values` mode
on the same endpoint — never trust labels from the client:

```jsonc
// GET /fin/bookings/filter_options/offsetting_account?values=700011,700015
{ "labels": { "700011": "DB Fernverkehr AG 700011", "700015": "…" } }
```

- **Security:** the endpoint exposes only that attribute's own relation; `q` /
  `values` are bound params; results honour the same authorization as the listing.
- **UX:** debounce (~200 ms), cache pages per term, "lädt…" / "mehr…" affordances.

### 2.8 Serialization & persistence  — **decided**

**Interaction model (decided): apply, not live.** The builder edits a client-side
value in-place; nothing runs until the user clicks **Anwenden**. On apply, the
**URL is updated** to carry the whole filter, the results reload, and back /
forward / copy-link all work. (This differs from Moss, which is live; we chose
apply deliberately — one query per intent, cheap sharing, no debounce races.)

**Internal representation (decided): a plain Ruby array tree / JSON value.** The
filter lives as the compact positional tree of §2.2 — plain nested Ruby arrays
server-side, the same shape as JSON client-side — and is passed around, validated
and compiled from that. The URL encoding is a *separate serialization concern*
layered on top; the canonical form is always this tree, with **regular** keys:

```rb
[ [ ["amount", "between", 10000, 25000] ],       # slot 1
  [ ["cost_center", "in", "3150"] ] ]            # slot 2 (AND between slots)
```

**Apply flow (PRG, codec stays in Ruby).** On Anwenden the JS POSTs the value JSON;
the controller encodes it to the URL form and **redirects** to the canonical
`GET …?filter=…` (Post/Redirect/Get). On load, the controller decodes `filter`
back to the hash, hands it to the compiler (→ scope) *and* to the view as the
builder's initial state. So the **encoder/decoder is needed only in Ruby**; the JS
works purely in plain JSON. Shareable, bookmarkable, one source of encoding truth.

#### URL encoding — research and choice

Requirement: short, human-editable, few characters that must be %-encoded, and a
usable library on **both** the Ruby and (ideally) JS sides. Options considered
(the examples compare encodings of the earlier keyed tree; the final wire shape
below is more compact still):

| Format | Shape of our example | %-encoding | Libraries | Notes |
|---|---|---|---|---|
| **Rison** ✅ | `(slots:!((conditions:!((attribute:amount,operator:between,operands:!(10000,25000))))))` | syntax chars are RFC-3986 query-legal unencoded; only string *data* is escaped | **Ruby `rison-rb`** + JS `rison` | JSON-equivalent, compact, readable; proven in **Kibana** URL state |
| JSURL | `~(slots~(~(conditions~(~(attribute~'amount~operator~'between~operands~(~10000~25000))))))` | **zero** — output ⊂ `A-Za-z0-9_-.!*'~()` (encodeURIComponent-safe) | **JS only, no Ruby port** | foolproof vs double-encoding, but tilde-heavy + we'd port it to Ruby |
| base64url(JSON) | `eyJ2IjoxLCJzbG90cyI6…` | zero | native both sides | **not human-editable** (opaque); longest |
| `qs` brackets | `slots[0][conditions][0][attribute]=amount&…` | `[` `]` escaped; very long | Rack/JS | verbose, no nesting economy |
| OData `$filter` | `amount ge 10000 and amount lt 25000 and …` | spaces + operators escaped | — | prose-y, not compact, no clean CNF nesting |

**Decision: Rison**, via the `rison-rb` gem (`Rison.dump` / `Rison.parse`, handles
nested hashes/arrays, string keys by default; the JS `rison` lib is available too if
the client ever needs it). It is an existing, well-specified format (proven in
Kibana) that matches all requirements, so no ad-hoc encoding is needed. Maintenance
caveat: `rison-rb` is a small, low-profile gem — before depending on it we should
vet/pin it, and be ready to **vendor it or implement the codec ourselves** (the
Rison grammar is tiny, a few hundred lines) so an unmaintained dependency can't
block us. The format itself is stable regardless. One caveat to respect: Rison's
`,` and `:` are legal *unencoded* in a URI query (RFC 3986 sub-delims / pchar), but
JS `encodeURIComponent` *would* escape them — so **never pass a Rison string
through `encodeURIComponent`**; place the codec output directly as the query value
(Rison already escapes the string *data* it contains). Our operands (account
numbers, cost-centre codes, ISO dates, decimals) are alphanumeric, so data-level
escaping is rare. If we ever want *guaranteed* zero %-encoding (e.g. to survive an
accidental double-encode), JSURL is the fallback — at the cost of porting it to Ruby.

**Wire shape (decided): positional tree + short keys in the URL.** The canonical
tree is already positional (§2.2). For the URL, the codec additionally substitutes
every attribute's and operator's **`short_key`**; decoding maps them back to the
regular keys via the schema. (A short_key the schema doesn't know is dropped like
any unknown key — same allow-list rule as everywhere.) So one filter has three
equivalent spellings:

```
canonical JSON:  [[["amount","between",10000,25000]],[["cost_center","in","3150"]]]
URL tree:        [[["amt","bt",10000,25000]],[["cc","in","3150"]]]
in the URL:      ?filter=!(!(!(amt,bt,10000,25000)),!(!(cc,in,'3150')))
```

Decoding a URL therefore *requires* the schema (short_key → key) — which is fine:
a filter URL is only ever decoded by the page that owns the schema. (No format
version field for now — see below.)

**Cross-cutting rules:**
- **Forward-compatible, no version field (for now):** we deliberately omit a `v`
  version key. The compiler already ignores unknown keys and drops unknown
  attributes/operators, so the shape can gain fields without breaking old links; a
  version tag can be added later if a breaking encoding change is ever needed.
- **Length guard:** if an encoded filter would exceed a safe URL length, fall back
  to a POST-backed apply (server keeps the filter, URL carries a short handle).
- **Empty:** an absent/empty `filter` = no conditions = all rows.
- **Trust boundary:** the client may submit any hash; the server allow-lists
  attribute/operator keys, casts + validates operands, ignores anything unknown
  (§2.3). Labels are always re-resolved server-side (§2.7).

### 2.9 Worked example — the DATEV bookings dataset

Declaration (sketch): a **template** — no base relation named. Columns are symbols
(or lambdas for multi-column), every attribute lists its operators **explicitly**
and carries a **short_key** for the URL encoding.

```ruby
BOOKINGS_SCHEMA = Filtering::Schema.define do |s|
  # Konto and Gegenkonto can each hold a ledger account OR a supplier (700xxx), so
  # both label sources are merged for both attributes (as account_options does
  # today). ~150 rows -> inline; switch to a remote endpoint (§2.7) if it grows.
  account_options = Filtering::Options.merge(
    Filtering::Options.from(WsjrdpLedgerAccount.all, value: :number, label: ->(a){ "#{a.number} #{a.name}" }),
    Filtering::Options.from(WsjrdpPersonalAccount.all,      value: :number, label: ->(s){ "#{s.number} #{s.name}" }))

  s.attribute key: :amount,             short_key: :amt, label: "Betrag",        type: Filtering::Types::DECIMAL,
              operators: %i[gte lt between],          column: :amount
  s.attribute key: :booking_date,       short_key: :bd,  label: "Buchungsdatum", type: Filtering::Types::DATE,
              operators: %i[gte lt between present blank], column: :booking_date
  # Konto/Gegenkonto are NOT NULL (Part 3) -> presence operators simply not listed.
  s.attribute key: :konto,              short_key: :k,   label: "Konto",         type: Filtering::Types::REFERENCE,
              operators: %i[in not_in],               column: :account_number,            options: account_options
  s.attribute key: :offsetting_account, short_key: :gk,  label: "Gegenkonto",    type: Filtering::Types::REFERENCE,
              operators: %i[in not_in],               column: :offsetting_account_number, options: account_options
  # Kostenstelle is nullable -> explicitly lists the presence atoms too.
  s.attribute key: :cost_center,        short_key: :cc,  label: "Kostenstelle",  type: Filtering::Types::REFERENCE,
              operators: %i[in not_in present blank], column: :cost_center_number,
              options: Filtering::Options.from(WsjrdpCostCenter.all, value: :number, label: ->(c){ "#{c.number} #{c.name}" })
  s.attribute key: :text,               short_key: :q,   label: "Freitext",      type: Filtering::Types::TEXT,
              operators: %i[contains],
              column: ->(t) { [t[:description], t[:original_posting_text], t[:document_field_1]] }
  # `status` is registered but hidden from the UI (catalog: false -> catalog omits
  # it); it exists only so the hidden `status = active` condition can compile.
  s.attribute key: :status,             short_key: :st,  label: "Status",        type: Filtering::Types::ENUM,
              operators: %i[in],                      column: :status, catalog: false
end

# Hidden condition (§1.5): the bookings list only ever shows active rows -- supplied
# by the controller on every apply, never rendered, never in the URL. Uses symbols
# (attribute:/operator:) to match the registry, like a parsed user condition.
BOOKINGS_HIDDEN = [
  Filtering::Slot.new(conditions: [
    Filtering::Condition.new(attribute: :status, operator: :in, operands: ["active"])
  ])
]
```

A **derived** schema refines the template server-side — here the legs variant:
drop the one-sided account attributes, narrow Kostenstelle, add the legs-only
amount:

```ruby
LEGS_SCHEMA = BOOKINGS_SCHEMA.derive do |s|
  s.remove :konto, :offsetting_account            # ambiguous on legs (either side)
  s.operators :cost_center, %i[in not_in]         # replace inherited operator list
  s.attribute key: :leg_amount, short_key: :lam, label: "Betrag (Kontosicht)",
              type: Filtering::Types::DECIMAL, operators: %i[gte lt between],
              column: :leg_amount                 # legs-only column
end
```

Usage in a controller — base **and** schema are chosen at request time:

```ruby
base, schema = (params[:view] == "legs") ? [DatevBooking.legs, LEGS_SCHEMA]
                                         : [DatevBooking.all,  BOOKINGS_SCHEMA]
bound = schema.bind(base)

query     = Filtering::UrlCodec.decode(params[:filter], schema: bound)   # Rison + short_keys -> Query
@filtered = Filtering::Compiler.new(bound)
              .apply(query, hidden: BOOKINGS_HIDDEN)       # AND status = active (§1.5)
# … then hand @filtered to the existing sort/paginate/columns machinery unchanged.
```

(For a quick one-off subset without naming a variant, `bind(base, only: %i[…])`
does the same partially — derive is for variants that deserve a name.)

Example compiled SQL (hidden condition first, then the two user slots):

```sql
WHERE (status = 'active')                       -- hidden condition (§1.5)
  AND (amount >= 10000 AND amount <= 25000)     -- user slot 1
  AND (cost_center_number IN ('3150'))          -- user slot 2  (AND between slots)
```

### 2.10 Relationship to today's `DatevBookingsQuery`

The current filter is a **restricted CNF**: it also ANDs across fields and ORs
within a field, but each OR-clause is locked to a *single* field and the set of
"slots" is fixed. The generic engine **subsumes** it (a mixed-field OR is now
possible, slots are user-defined). Orthogonal concerns — **sorting, pagination,
column selection, the summary `total_sum`** — stay exactly as they are and simply
consume the compiled relation. So this can land as a drop-in replacement for the
`#filtered` step alone.

### 2.11 Open questions to settle before coding

1. ~~**Live vs. apply.**~~ **Decided: apply** — nothing runs until "Anwenden", and
   apply updates the URL (§2.8).
2. **Atom vocabulary v1.** Which operators ship first per type — is
   `≥ / < / im Bereich` + presence enough for `decimal`/`date`, and `ist / ist
   nicht / hat Wert / ist leer` for `reference`? Do we need `enthält`/text at all
   for v1?
3. **Bookings attributes v1.** Confirm the initial attribute set (Betrag,
   Buchungsdatum, Leistungsdatum, Konto, Gegenkonto, Kostenstelle, Sekundäre KoSt,
   Sphäre, Status, Freitext) and their groups/labels.
4. **Where the engine lives.** Wagon-local first (`app/models/filtering/…`), or
   shaped from the start for extraction/reuse across models?
5. **Options endpoint shape.** One generic controller keyed by attribute, or a
   small endpoint per attribute? Auth reuse.
6. ~~**URL format.**~~ **Decided: Rison** (`rison-rb`), codec in Ruby, PRG apply
   (§2.8). Still open: max-length fallback threshold, and migration from the
   current per-field params (redirect old links or drop them?).
7. **Legs interaction.** The account/supplier detail views wrap `DatevBooking.legs`
   with `sum_column: :leg_amount`; confirm the builder targets the plain bookings
   base there too (Konto perspective) or the legs base.
8. ~~**Per-attribute operator sets.**~~ **Decided (supersedes the earlier
   `only:`/`except:` idea): every attribute lists its operators EXPLICITLY** —
   `operators: %i[…]` is a required part of the declaration, resolved against the
   type's implementation library; nothing is derived from the type. An unknown
   operator key raises at declaration time. The catalog emits exactly the listed
   set; the compiler honours only operators listed on that attribute.
9. ~~**Schema ↔ base binding.**~~ **Decided: template + bind.** A schema can be
   declared as a **template** without any table/scope (columns as symbols/lambdas)
   and bound to a concrete relation whenever the WHERE clause is actually needed —
   `BOOKINGS_SCHEMA.bind(DatevBooking.all)`, per request if the base depends on
   user input (e.g. switching to `DatevBooking.legs`), and **partially** via
   `bind(base, only: …)`. Declaring with `base:` binds immediately (the
   direct-concrete case). See §2.2/§2.9.
10. ~~**Wire format shape.**~~ **Decided: compact positional tree + short keys.**
    The JSON tree is an array of slots; a slot is an array of conditions; a
    condition is the flat array `[attribute, operator, *operands]` with the
    **regular** keys. Attributes and operators additionally carry a `short_key`
    (operators ≤ 2–3 chars) that the Rison URL codec substitutes; decoding maps
    them back via the schema (§2.8).
11. ~~**Operator key/short_key scope.**~~ **Decided: globally unique.** One
    `OPERATOR_VOCABULARY` (key ↔ short_key bijection) for the whole system, even
    though resolution would only require per-attribute uniqueness. Types implement
    vocabulary keys (same key in several types = one concept, per-type
    label/casting); adding an operator later = one vocabulary line +
    implementations, collision-checked at boot. As part of this, the date operators
    `on_or_after`/`before` were folded into `gte`/`lt` (date-specific labels
    "ab"/"vor" stay). Attribute keys/short_keys are unique per schema.
12. ~~**Derived schemas.**~~ **Decided: `parent.derive { … }`** produces a new
    template that can add attributes, remove attributes, and replace an inherited
    attribute's operator list (narrow or extend); copy-on-derive, parent untouched,
    bindable like any template (§2.2, legs example in §2.9).

### 2.12 Draft recommendations for the open questions (for discussion)

Proposals, not decisions — each is a starting point to accept, tweak or reject.

**(2) Atom vocabulary v1 — keep it lean.**

| Type | v1 operators | Notes |
|---|---|---|
| `reference`, **nullable** (Kostenstelle, Sekundäre KoSt, Sphäre) | `ist` (in), `ist nicht` (not_in), `hat Wert` (present), `ist leer` (blank) | presence only where the column is genuinely nullable |
| `reference`, **not-null** (Konto, Gegenkonto) | `ist`, `ist nicht` | no `ist leer` — column can't be NULL (Part 3) |
| `decimal` (Betrag) | `≥`, `<`, `im Bereich` | no presence — `amount` is NOT NULL/generated |
| `date` (Buchungsdatum, Leistungsdatum) | `ab`, `vor`, `im Bereich`, `hat Wert`, `ist leer` | both are nullable (service_date 98 % NULL) |
| `enum` (small fixed set, e.g. Kontenart if exposed) | `ist`, `ist nicht` | Status is **not** a user attribute in v1 — see below |
| `text` (Freitext) | `enthält` | yes, keep it — searching Buchungstext is a core need |

Per-attribute differences (nullable vs NOT-NULL reference; text = only `enthält`)
are expressed by the attribute's **explicit `operators:` list** (§2.11 #8), not by
separate types.

Defer to later: `enthält nicht`, negated/`ist nicht` on `enum`, regex, relative
dates ("letzte 30 Tage"). Rationale: this set already covers every real query and
maps 1:1 onto the reusable `Types` in §2.2.

**Status — a hidden condition, not a user attribute (v1).** The bookings host
supplies **`status = active`** as a hidden condition (§1.5): always AND-combined,
never rendered, never in the URL. So the list only ever shows active bookings and
**soft-deleted rows are not visible in the UI — acceptable for now.** No Status
control ships in v1. (When we later want to browse soft-deleted, expose a Status
attribute and drop/parametrise the hidden condition — the engine already supports
it.) This replaces the earlier "implicit active scope" idea with the generic
hidden-condition mechanism.

**(3) Bookings attributes v1 — confirm the set, grouped like Moss.**

- *Beträge & Daten:* **Betrag** (`amount`), **Buchungsdatum** (`booking_date`),
  **Leistungsdatum** (`service_date`).
- *Konten:* **Konto** (`account_number`), **Gegenkonto** (`offsetting_account_number`)
  — labels merge account + supplier names (as `account_options` does today);
  optionally **Kontenart** (`account_type`, enum).
- *Kostenrechnung:* **Kostenstelle** (`cost_center_number`), **Sekundäre
  Kostenstelle** (`secondary_cost_center_number`), **Sphäre** (`sphere_number`).
- *Meta:* **Freitext** (over `description`, `original_posting_text`,
  `document_field_1`). *(Status is not a user attribute — it is the hidden
  `status = active` condition, §1.5.)*

Options: inline for the small sets (Kostenstelle ≈ 82, Sachkonten ≈ 61, Sphäre);
**remote** for Konto/Gegenkonto only if the merged account+creditor list grows
large (creditors are 700xxx). Defer to v1.1: **Primanota-Periode**
(`primanota_period`), **Wirtschaftsjahr** (`fiscal_year`), **Belegfeld 1** as a
standalone attribute. Keeps the first cut small while covering the common filters.

**(4) Where the engine lives — wagon-local, extraction-ready.**
Put the generic classes under an isolated namespace in the wagon
(`app/models/filtering/…`, since core `app/hitobito` is read-only). The generic
classes (`Operator/Type/Attribute/Schema/Query/Compiler`) contain **no** bookings-
or wagon-specific code; only the *registration* file names `DatevBooking`. That
single boundary makes later extraction (to core, or a gem) a move, not a rewrite.
Depend on nothing beyond ActiveRecord/Arel.

**(5) Options endpoint — one generic, attribute-keyed action.**
A single endpoint, `GET …/filter_options/:attribute?q=&page=` (plus
`?values=a,b` for label resolution, §2.7). It looks the attribute up in the Schema,
uses its declared options relation, applies `q`/paging, and returns
`{options:[[v,l]…], has_more}`. Authorisation reuses the host controller's
`authorize!` (same as the listing). One code path for all reference attributes; a
multi-dataset future just adds a `:dataset` segment. Avoids N hand-written endpoints.

**(6-rest) URL length & legacy params.**
- *Max length:* cap the generated URL at ~**1800 chars** (safe under old
  proxy/browser limits). Below it, put the Rison in `?filter=`; above it, fall back
  to a POST-backed apply (server holds the filter under a short token; URL carries
  `?filter_ref=<token>`). v1 filters are a few slots, so this rarely triggers —
  ship the guard, treat the token store as a later refinement.
- *Legacy params:* on the bookings index, if `filter` is absent but old params
  (`account_number[]`, `cost_center[]`, `q`, `status`, date/amount `_from`/`_to`)
  are present, translate them once into the equivalent Rison filter and **redirect**
  to the canonical `?filter=…` (each multi-select → one `in` slot; each range →
  one `between`/`≥`/`<` slot; `q` → `text enthält`). Preserves existing
  links/bookmarks; drop the shim after a deprecation window.

**(7) Legs interaction — main list only in v1.**
Ship the full builder on the **main bookings list** (`DatevBooking.all`, Konto
perspective, `sum :amount`). Leave the account/supplier **detail** views on their
current fixed per-account scope over `DatevBooking.legs` (`sum :leg_amount`).
Reason: `legs` doubles each booking into a Konto leg and a Gegenkonto leg, so a
generic Konto/Gegenkonto filter over it reads ambiguously ("either side"); mixing
that with the two-sided sum would confuse. If a full builder on legs is wanted
later, it is just the derived `LEGS_SCHEMA` (§2.9) bound to `DatevBooking.legs` —
no engine change.

---

## Part 3 — Data note: NULLs in the bookings table (concrete question)

Measured on the current 6 566 active bookings:

| Column | NULL rows | Meaningful "no value"? |
|---|---|---|
| `account_number` (Konto) | **0 (0.0 %)** | No — every DATEV booking has a Konto |
| `offsetting_account_number` (Gegenkonto) | **0 (0.0 %)** | No |
| `cost_center_number` | **518 (7.9 %)** — 505 of the 2026 rows | **Yes** — many bookings legitimately have no cost centre |
| `secondary_cost_center_number` | 1 702 (25.9 %) | Yes |
| `service_date` (Leistungsdatum) | 6 434 (98.0 %) | Yes (only newer exports carry it) |
| `document_field_2` | 6 566 (100 %) | Effectively unused |

**Conclusions:**

- **`cost_center_number` — keep NULL, it is real.** ~8 % of bookings have no cost
  centre (bank/balance-sheet movements etc.). The `blank` / `hat Wert` atoms are
  genuinely useful here, and "cost centre X *or missing*" must be expressible.
  Same for `secondary_cost_center_number` and `service_date`.
- **`account_number` / `offsetting_account_number` / `account_type` /
  `offsetting_account_type` — now `NOT NULL` (decided & applied).** The raw
  `original_account_number` / `original_offsetting_account_number` are *always* set
  (every booking line names a Konto/Gegenkonto). `account_number` was only ever
  NULL when a ≤2025 account had no mapping in `ACCOUNT_MAP_2025_TO_2026` — a
  *mapping gap*, not a meaningful "no account" — and the account types are derived
  from the numbers. There were **zero** such rows (0 NULL across all 6 568), so the
  constraint was safe to add. What changed:
  - The create migration declares all four columns `null: false`.
  - The importer (`import_datev_primanota.py`, `_require_complete_accounts`) **aborts
    the whole run with a clear error** listing the offending rows (file / sheet /
    Nr / raw Konto / Gegenkonto) if any would be missing — an unmapped account is a
    hard import error now, never a silently NULL row.
  - Consequence for the filter: **do not** offer "Konto ist leer" / "Gegenkonto ist
    leer" as filter atoms (the column can't be NULL); a missing account is a
    data-quality error caught at import, not a category to slice by. Contrast the
    genuinely nullable `cost_center_number` etc. above, which *do* get the `blank` /
    `hat Wert` atoms.

---

## Part 4 — Implementation notes (v1 shipped), questions & observations

The filter is implemented and live on `/bookkeeping/bookings` (the previous UI
remains frozen on `/bookkeeping/bookings_old`). Code layout, exactly along the
generic/specific boundary of §2.12(4):

- **Generic** (`app/models/filtering{,.rb}/`): `Operator`, `Type`, `Types`,
  `Attribute`, `Options`, `Schema`, `BoundSchema`, `Query`/`Slot`/`Condition`,
  `Compiler`, `Rison`, `UrlCodec` — no dataset knowledge anywhere.
  Generic UI: `app/views/shared/filtering/_builder.html.haml` (self-contained
  vanilla-JS component rendered purely from catalog+value; all DOM built via
  `createElement`/`textContent`, no injection) and `app/views/shared/_fin_panes.html.haml`
  (pane chrome / scroll restore, shared with the column picker).
- **Bookings-specific**: `app/models/datev_bookings_filter.rb` (schema declaration,
  hidden `status=active`, `bound`), ~40 lines in `Fin::BookingsController`
  (`#apply` PRG endpoint + hooks feeding the compiled scope into the unchanged
  `DatevBookingsQuery` sort/paginate/columns/sum machinery), the `post :apply`
  route, and the `_columns` pane extracted from the old `_filters` partial (which
  is deleted; the frozen copy lives on under `fin/bookings_old/`).
- **Specs**: `spec/models/filtering_spec.rb` (Rison round-trips, codec, compiler,
  derive, catalog). Plus a 27-check `rails runner` smoke suite run against the dev
  data during development (all green, including parity with the legacy query).

### Deviations from the plan (deliberate, flagged)

1. **Rison codec implemented in-wagon** (`Filtering::Rison`, ~150 lines,
   strict parser) instead of depending on the unvetted `rison-rb` gem — the
   fallback §2.8 explicitly sanctioned. No new gem, no Docker/bundler churn.
   *Question: adopt/vendor the gem later, or keep our codec permanently?*
2. **Periode ships in v1** (plus Sekundäre Kostenstelle and Sphäre), although
   §2.12(3) had deferred Periode — parity with the old filter UI seemed more
   important than the smaller v1 set. Konto/Gegenkonto/Kostenstelle/
   Buchungsdatum/Leistungsdatum/Betrag/Freitext as planned; **no Status control**
   (hidden condition, as decided).
3. **No remote options endpoint yet** (§2.7): every option set ships inline in
   the catalog — the largest (merged Konto/Gegenkonto incl. Kreditoren) is
   currently 122 entries. Revisit when creditors grow into the many hundreds.
4. **Legacy-param shim (§2.12(6)) not implemented.** Old-style URLs
   (`?account_number[]=…`) now land on the unfiltered new page; session-remembered
   old query strings self-heal on the next apply. The frozen old page still
   understands them. *Question: is the translate-once redirect needed before the
   old page is removed, or do we let old links expire?*
5. **UI is a framework-free inline component** (matches the wagon's existing
   inline-JS idiom; no Stimulus/build-pipeline dependency). *Question: migrate to
   a Stimulus controller when hitobito's JS setup makes that convenient?*

### Observations from implementation & testing

- **Verified end-to-end** (desktop + 375 px mobile): build/edit/delete conditions
  and slots, mixed-attribute OR-slots, multiselect with search, ranges, dates,
  presence atoms; Anwenden → PRG → canonical `?filter=` URL; chips restored from
  URL; hand-edited URLs with full keys work and are canonicalized to short keys on
  the next apply; sort links, pagination and per-page all preserve the filter;
  Zurücksetzen clears it; garbage `?filter=` renders the unfiltered page (no
  error); result counts/sums verified against direct SQL.
- **hitobito's global stylesheet fights embedded widgets**: labels are
  right-aligned and *every* `input` gets a fixed width (~270 px), which broke the
  checkbox list until countered with targeted CSS overrides in the builder
  partial. Expect the same for any future embedded control.
- **URL cosmetics**: the canonical apply URL is pretty Rison; browsers display
  `'` as `%27` in the address bar, and sort/pagination links (built via
  `to_query`) fully percent-encode the filter value. Both decode identically —
  accepted as cosmetic.
- **The dev spec harness would drop `hitobito_development`** (it recreates
  databases on boot and the running dev server's connections are the only thing
  blocking it). Wagon specs are therefore CI-only in this environment; local
  verification used the runner smoke suite. Worth fixing the harness config some
  day. Rubocop was likewise not runnable in the dev container (missing
  rubocop-rspec in the exec context) — CI checks style.
- **Small usability addition beyond the doc**: a dirty-state hint
  ("Änderungen noch nicht angewendet") with a highlighted Anwenden button when
  the builder state differs from the applied filter.
- Chip display for many selected values truncates to "first +n"; labels use the
  option label (number + name). *Question: good enough, or show counts
  ("3 ausgewählt") beyond a threshold?*
- *Question: on mobile, should Anwenden auto-collapse the filter pane (more
  results visible) — or keep the current always-open behaviour?*

### UX iteration 2 (implemented)

- **Empty slot**: with no conditions, one dashed "waiting" slot is shown
  (⊕ Bedingung hinzufügen + hint) instead of a bare button.
- **Panel open by default**: the builder pane got its own state cookie
  (`…_pane_flt`) — previously it shared the old page's filter-pane cookie, so a
  collapse there collapsed it here too.
- **Chips-combobox** for reference attributes (TomSelect-style, self-built):
  selected values as removable chips inside the field + search input + option
  list with ✓ markers; fully keyboard-driven (type = search, ↑↓ = highlight,
  ↵ = toggle, ↵ on empty field = commit, ⌫ = remove last, Esc = cancel).
- **Flow-oriented committing — no Übernehmen/Abbrechen buttons**: small ✓/×
  icons sit right next to the inputs as explicit fallback; a draft condition
  auto-commits (a) immediately when an operand-less operator (`ist leer`,
  `hat Wert`) is chosen, (b) on ↵, (c) on click outside the builder, (d) when
  continuing with "oder ⊕" / "'UND'-Bedingung hinzufügen" mid-edit (the draft
  is committed, then the next editor opens). Esc (or ×) discards the draft.
- **Keyboard hints** are shown contextually inside the editor (per control).
- **Text-search sub-variants**: three attributes
  `text` (Buchungstext: description + original_posting_text; **default**),
  `text_document` (Belege: Belegfeld 1 + 2, short_key `qb`) and
  `text_any` (Buchungstext & Belege, `qa`), joined by the new generic attribute
  metadata **`variant_group:`** — the picker shows one entry per group
  (labelled with the group name, first member = default) and the editor offers
  the members as a sub-variant switch that preserves the typed term
  when switching. Note: the old single text attribute searched
  description + posting text + Belegfeld 1; the new default (Buchungstext)
  deliberately excludes Belegfelder — "Buchungstext & Belege" covers the old
  scope (plus Belegfeld 2).

### UX iteration 3 (implemented)

- **ANY-of semantics made visible** for multi-selects: operators carry new
  generic metadata `label_many` / `many_hint`. Chips read
  "Kostenstelle **ist eines von** 2000 Finance, 2500 IT" (not_in: "ist keines
  von"), and while 2+ values are selected the editor shows
  "Mehrfachauswahl: es genügt, wenn EINER der Werte zutrifft (ODER)."
- **Picker order**: Suche first, then Kostenrechnung, then Beträge & Daten,
  Konten (order = schema declaration order; the Suche entry sits ungrouped at
  the top).
- **Host-side exclusion**: `bind(base, except: […])` (and
  `DatevBookingsFilter.bound(except: …)`) lets a controller hide attributes;
  the bookings page excludes **Sphäre and Periode**
  (`Fin::BookingsController::EXCLUDED_FILTER_ATTRIBUTES`). Conditions on
  excluded attributes in a URL are dropped like any unknown key. Operator-level
  narrowing per host remains available via `derive`.
- **Whole month / whole year date atoms**: new vocabulary operators
  `in_month` (`im`, operand `YYYY-MM`) and `in_year` (`iy`, operand year) on
  the DATE type, compiled to closed ranges. New generic operator metadata
  `operand_control:` ("month"/"year") drives the editor input, **prefilled
  with the current month/year** so ↵/✓ applies immediately; per-operator
  `cast:` hooks validate the operands (also used to Ruby-validate regexes).
  Switching between operators with different operand controls resets the
  typed value (bug found in testing: a month value leaked into the year
  field).
- **Variant switch is a dropdown** now (Buchungstext | Belege |
  Buchungstext & Belege), default Buchungstext; the typed term survives
  switching.
- **Text operator set**: `ist genau` (eq), `enthält` (contains),
  `enthält nicht` (not_contains) and `Regex` (regex), each in a
  case-insensitive (default) and case-sensitive variant. The pairs are linked
  by new operator metadata **`case_group`/`case_sensitive`** — the schema's
  "grouping indicator" — and the UI shows one dropdown entry per pair plus a
  separate **"Groß-/Kleinschreibung beachten"** checkbox (off = insensitive
  default). Semantics: eq = exact match (ILIKE-escaped / `=`), contains =
  substring (ILIKE/LIKE), regex = POSIX `~*`/`~` (Ruby-side syntax check;
  a PG-only-invalid pattern would still error — rare, accepted for now).
  `enthält nicht` wraps columns in COALESCE(col, '') so rows with NULL text
  fields count as "does not contain" — making contains/not_contains exact
  complements (verified: 13 + 6553 = 6566 on the live data). This is a
  deliberate, documented deviation from pure 3VL for negated text search.

### UX iteration 4 (implemented)

- **"Suche" renamed to "Textsuche"** (picker entry / variant_group label); the
  case toggle moved to sit **after the text input, before the ✓/× icons**
  (label shortened to "Groß/Klein beachten" with a full tooltip; on ~≥1600 px
  everything is one line, below that the toggle+icons wrap as a pair).
- **Date ranges on one line**: date/month inputs got compact widths, so
  attribute + operator + von–bis fit a single row on desktop widths.
- **Pane toggle bug fixed**: the old pane script ran *before* the pane elements
  existed in the DOM (the shared partial renders first), so its
  only-the-pill-toggles guard never attached and any click on the summary line
  toggled. All pane/scroll listeners are now **document-delegated**
  (position-independent, Turbo-proof); the builder and column picker also
  re-initialize on `turbo:load` and reset their init markers on
  `turbo:before-cache`, so back/forward restores keep working.
- **Pane redesign**: `<details>` replaced by a slim pill button
  (`.pane-pill`, equal width 8em for "Filter" and "Spalten") + `.pane-body`.
  Collapsed = one pill line; open = content **to the right of the pill** when
  there is horizontal room (below on narrow screens). The condition-count badge
  lives in the pill.
- **Icons switched to hitobito's FontAwesome 5 set** (`fas fa-*`, verified
  loaded): chevron (caret), `fa-plus-circle` (add), `fa-times` (remove/cancel),
  `fa-check` (commit), `fa-trash` (slot delete — same as `icon(:trash)`
  elsewhere). The column-picker drag handle keeps its ⠿ glyph (no established
  FA counterpart in use).
- **"Konto oder Gegenkonto"** attribute (`any_account`, short_key `kgk`):
  REFERENCE became multi-column-capable — `ist` matches if ANY column is in the
  set, `ist nicht` if NONE is (`present`/`blank` follow the same any/all rule).
  **Bug found in testing:** the naive `Array(column)` exploded a single Arel
  attribute (a Struct) into `[table, name]`, breaking every single-column
  reference filter — replaced by an explicit `Types.wrap` with a warning
  comment.

### UX iteration 3 (implemented, 2026-08) — reconciliation & shared table

Driven by the reconciliation page but landing mostly in shared code:

- **Read-only (host-pinned) filter slots** now render in a muted gray with a
  lighter label weight, so they read clearly as "fixed, not editable" next to
  the user's own full-contrast chips. This Bootstrap build has no
  `--bs-secondary-color` token (a 5.3 addition), so the CSS gives a concrete
  `#6c757d` fallback.
- **Chip tooltips**: every condition chip (locked and editable) now has a
  `title` with the FULL, untruncated description (`condFullText`), so a chip too
  small to show everything still explains itself; editable chips add
  "— Klicken zum Bearbeiten", locked ones "— fest vorgegeben, nicht änderbar".
- **Shared table widget consolidation** (`shared/_expandable_table`): the
  generic detail-table gained opt-in **pagination above + below** (incl. a
  per-page select), **multi-select** (shared `shared/_table_selection_js`, now
  scope-based via `.bk-select-scope` so the select-all bar can live in a
  toolbar), a right-aligned **column hamburger** (`shared/_table_hamburger` +
  `shared/_expandable_table_columns_js` — client-side show/hide + drag-reorder,
  persisted per table in `localStorage`), and click-to-sort headers. The
  bookings widget's column picker moved from a stacked pane into the same
  hamburger (toolbar: summary/paging/select-all on the left, hamburger
  bottom-right). Existing bookkeeping callers pass none of the new locals and
  are unaffected. The hamburger panel stays `position: absolute` on mobile too
  (a `fixed` element's `top: 100%` is the viewport bottom — an off-screen bug).
- **Accounting-entry detail**: a shared read-only partial
  (`fin/accounting_entries/_detail`, built on `shared/_kv_grid`) mirrors the
  edit form's useful fields (debtor/creditor, SEPA mandate, links, timestamps)
  with a `hide:` option; the reconciliation page hides the exclude-flag note.
