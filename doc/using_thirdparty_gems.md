# Using third-party gems in this wagon

This wagon declares its own third-party gem dependencies in
[`hitobito_wsjrdp_2027.gemspec`](../hitobito_wsjrdp_2027.gemspec) via
`add_dependency` / `add_runtime_dependency`. This document collects
the usage rules for those gems and the one rule that trips people up:
**gemspec dependencies are not auto-required**.


## The golden rule: `require` gemspec dependencies explicitly

When Rails boots it calls `Bundler.require(*Rails.groups)`. That
auto-`require`s only the gems listed directly in a `Gemfile` (the
top-level `gem "..."` entries) for the active groups. It does not
descend into a gem's own dependencies.

The gems below are declared in *our gemspec*, i.e. they are
dependencies of the `hitobito_wsjrdp_2027` gem — one level *below* the
top-level Gemfile. Bundler resolves, installs and puts them on the
load path, but never `require`s them for us. So:

> **Add an explicit `require "<gem>"` in the file (or initializer)
> that uses the gem.**

This is already the established convention in the wagon — see how
[`app/models/wsjrdp_2027/person.rb`](../app/models/wsjrdp_2027/person.rb)
requires `iban-tools` and `geocoder` at the top before using them.

Put the `require` where it belongs:

- **Used in one class** → at the top of that file (e.g. `person.rb`).
- **Used wagon-wide / wired into Rails** → in
  [`lib/hitobito_wsjrdp_2027/wagon.rb`](../lib/hitobito_wsjrdp_2027/wagon.rb)
  or a `config/initializers/*.rb`.

---

## Gem reference

| Gem | Purpose | `require` | Entry points |
| --- | --- | --- | --- |
| `rison` | RISON encode/decode | `require "rison"` | `Rison.dump`, `Rison.load` |
| `typst` | Compile Typst `.typ` → PDF/SVG/PNG/HTML | `require "typst"` | `Typst("file.typ").compile(:pdf)` |
| `iban-tools` | IBAN validation | `require "iban-tools"` | `IBANTools::IBAN.valid?` |
| `geocoder` | Address → lat/long geocoding | `require "geocoder"` | `Geocoder.search`, `Geocoder::Model::Base` |
| `chartkick` (+ `chart-js-rails`) | Charts in views | `require "chartkick"` | `Chartkick::Helper`, JS `new Chartkick.*Chart` |


### rison

RISON is a compact, URL-safe object serialization format. Used for
encoding structured values into strings (e.g. filter/query
parameters).

```ruby
require "rison"

Rison.dump({ "a" => 1, "b" => [1, 2] })   # => "('a':1,'b':!(1,2))"
Rison.load("('a':1,'b':!(1,2))")           # => {"a"=>1, "b"=>[1, 2]}
```

Other methods: `Rison.escape`, `Rison.dump_pair`.


### typst

Compiles [Typst](https://typst.app) markup (`.typ`) to PDF, SVG, PNG
or (experimental) HTML. The gem ships as a **precompiled native
extension** for the relevant platforms (`x86_64-linux`,
`aarch64-linux`, `arm64-darwin`, …), so no Rust toolchain is needed at
install time — important because the production image
(`docker/Dockerfile.prod`) has no Rust.

```ruby
require "typst"

doc = Typst("hello.typ")          # or Typst::Pdf.new("hello.typ")
        .with_root("/some/dir")   # input file must live under this root
        .compile(:pdf)            # :pdf, :svg, :png, :html_experimental

doc.write("hello.pdf")            # write the output file
pdf_string = doc.pages.first      # full PDF as a String (per page for svg/png)
```

Chainable builder methods (from `Typst::Base`): `.with_root`,
`.with_font_paths`, `.with_fonts`, `.with_inputs`,
`.with_dependencies`, plus `.query` and `.pretty`.

Gotchas:

- **Project root:** Typst refuses an input file outside its project
  root (default = the current working directory) with `input file must
  be contained in project root`. Pass `.with_root(dir)` when the
  `.typ` lives elsewhere.
- **Fonts:** provide custom fonts with `.with_font_paths(*paths)` —
  mirror the `TYPST_FONT_PATHS` used on the Python/scripts side for
  consistent output.
- `.compile(:svg)` / `.compile(:png)` return one entry per page;
  `.compile(:pdf)` / `.compile(:html_experimental)` return a single
  combined document.


### iban-tools

IBAN validation for SEPA data.

```ruby
require "iban-tools"

IBANTools::IBAN.valid?(normalized_iban)   # => true / false
```

Used in [`person.rb`](../app/models/wsjrdp_2027/person.rb) and
[`app/controllers/person/print_controller.rb`](../app/controllers/person/print_controller.rb).


### geocoder

Turns postal addresses into coordinates (`latitude` / `longitude` on
`Person`).

```ruby
require "geocoder"

Geocoder.search(full_address)             # => [Geocoder::Result, ...]
```

- Configured centrally in
  [`config/initializers/geocoder.rb`](../config/initializers/geocoder.rb)
  via `Geocoder.configure(...)`.
- Model integration is done with `extend Geocoder::Model::Base` (see
  `person.rb`).


### chartkick (+ chart-js-rails)

Renders charts in views. `chartkick` provides the Rails helpers;
`chart-js-rails` supplies the Chart.js asset backend.

- `require "chartkick"` happens in
  [`lib/hitobito_wsjrdp_2027/wagon.rb`](../lib/hitobito_wsjrdp_2027/wagon.rb),
  which also wires the view helpers in:
  `ActiveSupport.on_load(:action_view) { include Chartkick::Helper }`.
- In views, use the chartkick helpers, or the JS API directly, e.g.
  `new Chartkick.ColumnChart(container, data, options)` (see the group
  statistics views).


---


## Adding a new third-party gem — checklist

1. **Declare it** in [`hitobito_wsjrdp_2027.gemspec`](../hitobito_wsjrdp_2027.gemspec):
   ```ruby
   s.add_dependency "<gem>", "~> X.Y"      # pin per convention, cf. geocoder "~> 1.3", ">= 1.3.7"
   ```
2. **Guard transitive ripples.** If the new gem forces an incompatible
   upgrade of an existing gem, pin the affected gem explicitly with a
   short comment explaining why, so the bump is intentional and
   self-documenting rather than incidental drift.
3. **Install into the dev bundle — no root needed.** The
   `hitobito_bundle` volume's gems are owned by your host uid
   (e.g. `501`), but the `rails` container defaults to
   `RAILS_UID:-1000`. That mismatch means uid `1000` can't write
   `/opt/bundle`, so a plain restart *crash-loops* while fetching new
   gems (`Bundler::PermissionError`). Fix it by setting `RAILS_UID` to
   your `id -u` (persist it in your shell profile or
   `development/.env`).
4. **`require` it** where you use it (see also above).
5. **Native gems** (like `typst`): Make sure the gem ships precompiled
   platform gems for `x86_64-linux` (prod) and `aarch64-linux` (dev on
   Apple Silicon). Verify with `bundle lock --add-platform
   x86_64-linux` and check the lockfile shows a platform-tagged
   variant (e.g. `typst (0.15.1.5-x86_64-linux)`).
6. **Lockfile:** `Gemfile.lock` is gitignored in this wagon;
   production regenerates it during the image build (`bundle lock` in
   `docker/Dockerfile.prod`), so only the gemspec change is committed.
