# AGENTS.md — hitobito_wsjrdp_2027

Guidance for AI coding agents (Cursor, Codex, Claude Code, …) working in this
Hitobito wagon. Claude Code also reads `CLAUDE.md`; keep cross-tool rules here.

## Documentation

How-to guides — authoritative, follow them:

- [`doc/using_thirdparty_gems.md`](doc/using_thirdparty_gems.md) — the golden
  rule that gemspec dependencies are **not** auto-required, and how to add and
  `require` a third-party gem in this wagon.
- [`doc/navigation.md`](doc/navigation.md) — how the main nav, the left
  sub-navigation (`fin/_left_nav` + `nav` helper), Sheets (controller→sheet
  resolution, `parent_sheet`, `always_render_parent`) and Tabs fit together, plus
  a step-by-step recipe for adding a new Finanzen section with tabs.
- [`doc/url_encoding.md`](doc/url_encoding.md) — how we encode URL query params:
  leave RFC 3986-legal, non-special characters (`! $ ' ( ) * , ;` and `~`)
  **unencoded** for readable URLs, and how each JS/Ruby encoder behaves. **Rule
  (security-critical, no exceptions):** the `%XX`→literal "relax" step must be
  encapsulated together with the encode step in one helper, so it is never run on
  a string that may contain a raw `%`. Any new/copied such helper must be
  extensively tested and documented — read the doc before touching query-string
  building or percent-decoding.
- [`doc/expandable_table.md`](doc/expandable_table.md) — the shared
  `shared/_expandable_table` widget used across Finanzen (the Buchungen list, the
  Buchhaltung summaries, both reconciliation tables): expandable per-row detail,
  paging, sortable headers, the column hamburger, row selection, filters, detail
  nesting, and the `prefix` namespacing that lets several tables share one page.

Design records — living documents; read for context, but the code is the source
of truth (parts may be proposal-only or already superseded):

- [`doc/bookkeeping_schema_review.md`](doc/bookkeeping_schema_review.md) — the
  `datev_bookings` / ledger-account / cost-center / supplier schema decisions
  (some applied, the association plan still a proposal).
- [`doc/generic_filter_builder.md`](doc/generic_filter_builder.md) — the shared
  model for the generic CNF filter builder behind the table's `filter:` config.
- [`doc/roles.md`](doc/roles.md) — the wagon's group/role types and their
  permissions, how the hitobito permission/ability system works, the wagon's
  `can?(:log, …)` "privileged view" convention, and what the `:log` grants on
  `Event` do.
- [`doc/moss_data_model.md`](doc/moss_data_model.md) — how Moss (getmoss.com) data
  is exported and imported into Hitobito: entities (DE/EN), extraction paths
  (API / CSV-Builder+SFTP / ad-hoc / DATEV), and the per-entity field reference
  (Kontobewegungen → `moss_balance_movements`; Kartentransaktionen →
  `moss_card_transactions`), incl. how DATEV bookings link back to Moss.

See [`README.md`](README.md) for the dev-environment setup.

## Moss (getmoss.com)

- **Never call the Moss API.** Do **not** perform any Moss API request (no
  `POST /oauth2/token`, no `/v1/...` calls, no live requests to
  `public-api.getmoss.com`) — not even read-only ones, and not for testing.
  API access uses real production credentials against real financial data.
- **Do** read the **local OpenAPI spec** at
  [`doc/moss_export_examples/openapi_spec/`](doc/moss_export_examples/openapi_spec/)
  as the authoritative source for endpoints and field schemas.
- **Browsing the developer docs is allowed** on the domain
  `https://developers.getmoss.com/` only (stay on that domain). The per-operation
  pages follow `https://developers.getmoss.com/api/<operation-in-kebab-case>`
  (e.g. `.../api/search-bank-transactions`); use WebFetch to read them.
- See `doc/moss_data_model.md` → "Wie extrahiere ich Infos aus der Moss-Doku" for
  the extraction method and the same rules.

## Ruby environment on the macOS host (direnv & friends)

Host-side Ruby tooling (`bundle exec rubocop`, `gem`, `ruby`) uses ONE
project-local gem store: `vendor/bundle/ruby/3.2.0` in this wagon
(gitignored; `3.2.0` is the RubyGems API version — correct for Ruby 3.2.6).
Three mechanisms address it and must stay in sync:

- `.bundle/config` in this wagon (`BUNDLE_PATH: vendor/bundle` plus the
  charlock_holmes ICU build flags): every `bundle …` uses the store,
  independent of any shell environment. **`bundle exec` is therefore always
  the safest way to run tools.**
- `.ruby-version` (3.2.6) and `.rbenv-gemsets` (project gemset pointing at
  the store, plus `-global`) at the umbrella checkout root (three directories
  above this wagon): every rbenv **shim** call gets the right Ruby and the
  store even without direnv.
- `.envrc` (direnv, also at the umbrella root): exports `GEM_HOME` (store)
  and `GEM_PATH` (store + rbenv base — the base is the fallback so bundler
  itself stays findable) and puts the rbenv shims first in `PATH` — covers
  bare `gem`/`ruby` calls.

Notes for AI agents (non-interactive shells do not load direnv on their own):

- A PreToolUse hook may direnv-load Claude's shells, but it evaluates the
  `.envrc` at the shell's **starting** directory: `cd <this tree> && …`
  started elsewhere gets the wrong environment. Run from within this tree,
  or prepend `eval "$(direnv export bash 2>/dev/null)"` after the `cd`.
- Without direnv, plain `gem`/`ruby` may resolve to a non-rbenv Ruby
  (Homebrew). Use `bundle exec`, or call the shims explicitly
  (`~/.rbenv/shims/gem`, `~/.rbenv/shims/ruby`).
- Never run `gem cleanup` or `bundle clean` (both delete gems from the
  store), and never `bundle update` here — the wagon `Gemfile.lock` is
  derived from the container lock (see `development/bin/hit/test/env`,
  which re-adds the `arm64-darwin` platform after copying it).

## Running tests (specs)

**DANGER — read before any `rspec` run:** the test database resolves as
`RAILS_TEST_DB_NAME || RAILS_DB_NAME || "hitobito_test"`. In the dev container
`RAILS_DB_NAME=hitobito_development` is set, so running rspec without
`RAILS_TEST_DB_NAME` points the test env at the **development DB**, and
Rails' test-schema maintenance may drop/reload it. Always set BOTH
`RAILS_TEST_DB_NAME` and `RAILS_DB_NAME` to the dedicated test DB and add
`DISABLE_TEST_SCHEMA_MAINTENANCE=1`.

Wagon specs use the dedicated DB **`hitobito_test_wsjrdp_2027`**, normally
created by `hit test env wsjrdp_2027` (see `development/bin/hit/test/env`).
Manual bootstrap if it is missing or stale: create the DB, run core
`rake db:migrate`, then `rake app:wagon:migrate` from the wagon (its trailing
`wagon:schema_dump` enhance step errors — harmless, migrations are applied).

Two equivalent runners, verified to produce identical results. Both start
from the wagon directory (the core `Wagonfile` skips wagons when
`RAILS_ENV=test`; the wagon under test loads via its own `Gemfile`).

In the dev container:

```bash
docker exec -e RAILS_ENV=test -e RAILS_TEST_DB_NAME=hitobito_test_wsjrdp_2027 \
  -e RAILS_DB_NAME=hitobito_test_wsjrdp_2027 -e SKIP_INIT=1 \
  -e DISABLE_TEST_SCHEMA_MAINTENANCE=1 -e DISABLE_SPRING=1 -e NO_COVERAGE=1 \
  development-rails-1 bash -c \
  'cd /usr/src/app/hitobito_wsjrdp_2027 && bundle exec rspec spec/models'
```

On the macOS host (talks to the docker postgres via the mapped port):

```bash
RAILS_ENV=test RAILS_TEST_DB_NAME=hitobito_test_wsjrdp_2027 \
RAILS_DB_NAME=hitobito_test_wsjrdp_2027 RAILS_DB_HOST=127.0.0.1 \
RAILS_DB_PORT=5432 RAILS_DB_USERNAME=hitobito RAILS_DB_PASSWORD=hitobito \
DISABLE_TEST_SCHEMA_MAINTENANCE=1 DISABLE_SPRING=1 NO_COVERAGE=1 \
bundle exec rspec spec/models
```

Gotchas:

- `spec/spec_helper.rb` auto-requires every file in `spec/support/**`; some
  define top-level guard examples (e.g. `EVENT_ACTIONS` in
  `shared_event_ability_examples.rb`) that run — and can fail — in every
  invocation, unrelated to the specs you targeted.
- Ability specs assert against the combined core+wagon permission state, so
  **uncommitted changes in the (read-only) core checkout** show up as spec
  failures here. Check `git status` in `app/hitobito` before chasing them.
- Feature specs (`spec/features`, Capybara) need compiled webpack assets and
  chromium — run them in the container via the `hit test env` flow
  (`hit test prep` builds the assets), not on the host.

## Before committing

Run RuboCop with safe autocorrect from the wagon root and make sure it
passes:

```bash
bundle exec rubocop -a .
```

- `-a` applies **safe** autocorrections only. Do **not** use `-A`
  (unsafe fixes can change behavior) unless a human reviews the
  result.
- The working tree must be **offense-free** before you commit.
- `require:` → `plugins:` deprecation warnings can come from the
  upstream (read-only) core config and are harmless — ignore them.
