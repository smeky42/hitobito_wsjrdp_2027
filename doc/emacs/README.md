# Emacs development setup (core + wagon)

How to work on hitobito core and the `hitobito_wsjrdp_2027` wagon from
Emacs with full IDE features — LSP, cross-repo navigation, RuboCop
diagnostics, and rspec from inside Emacs. Everything runs **on the
host** (rbenv Ruby 3.2.6 + direnv); only the services (postgres,
webpack, mailcatcher, the running app) stay in Docker.

## Files in this directory

| File | Purpose |
| --- | --- |
| `setup-ruby-lsp.sh` | Does the whole project-side setup. Idempotent, re-run it any time. |
| `Gemfile` | Gemfile of the combined core+wagon LSP workspace. `development/app/Gemfile` is a symlink to it. |
| `example-ruby.el` | Example Emacs config: Ruby/Rails/HAML/rspec stack. |
| `example-treesit.el` | Example Emacs config: tree-sitter (optional). |

## Setup

```bash
./doc/emacs/setup-ruby-lsp.sh
```

It can be run from anywhere; it re-executes itself through `direnv` to
pick up the project environment. Steps, each skipped when already done:

1. Verify the active Ruby matches hitobito's `.ruby-version`.
2. `gem install ruby-lsp` into the project `GEM_HOME`.
3. Link `development/app/Gemfile` → `doc/emacs/Gemfile` (see
   *combined workspace* below) and seed `app/Gemfile.lock` from the
   wagon's lock, so the workspace resolves to the same gem versions the
   containers use.
4. `bundle install` in `development/app`.
5. Add `.ruby-lsp/` to the local `.git/info/exclude` of core and wagon.
6. Build ruby-lsp's composed bundle and index everything once
   (`ruby-lsp --doctor`) as a smoke test.

Then configure Emacs (next sections) — and mind the one manual step.

## ⚠ The one manual step: the workspace root

Open any Ruby file from core **or** wagon. When lsp-mode asks for the
project root ("Import project root"), answer with

    development/app

**not** the core or the wagon directory. Both repos have to live in
ONE workspace — that is the entire point of the setup. lsp-mode
remembers the answer in `~/.emacs.d/.lsp-session-v1`.

Wrong choice? `M-x lsp-workspace-folders-remove`, then
`M-x lsp-workspace-folders-add` with `development/app` (or delete the
session file and answer again), followed by `M-x lsp-workspace-restart`.
Check what is active with `M-x lsp-describe-session`.

## Emacs configuration

`example-ruby.el` and `example-treesit.el` in this directory are
working example configs — copy them into your Emacs config, or lift
the forms into your `init.el`. They assume `use-package` and pull
these packages from MELPA: `envrc`, `haml-mode`, `rspec-mode`,
`inf-ruby`, `projectile-rails`, `lsp-mode` (plus `expreg` for
tree-sitter).

`envrc` is the load-bearing one: it applies the project's direnv
environment per buffer. Without it Emacs finds neither `ruby-lsp` nor
the database.

If you already configure `lsp-mode` elsewhere, add Ruby to
`lsp-disabled-clients` so lsp-mode reliably starts ruby-lsp and not one
of the other Ruby servers it knows (`ruby-ls` is Solargraph):

```elisp
(lsp-disabled-clients
 '((ruby-mode . (ruby-ls rubocop-ls typeprof-ls steep-ls sorbet-ls semgrep-ls))
   (ruby-ts-mode . (ruby-ls rubocop-ls typeprof-ls steep-ls sorbet-ls semgrep-ls))))
```

`example-treesit.el` is optional; it switches Ruby buffers to
`ruby-ts-mode` (better font-lock and structural navigation). It is
written for Emacs 31 but guards every 31-only feature, so Emacs 29/30
fall back to a manual `major-mode-remap-alist` entry.

Eglot users: point it at the same server with

```elisp
(add-to-list 'eglot-server-programs '((ruby-mode ruby-ts-mode) "ruby-lsp"))
```

and open `development/app` as the project.

## Why this works on the host

- `WSJ2027Anmeldung/.envrc` (direnv) initializes rbenv, points
  `GEM_HOME` at `development/app/hitobito_wsjrdp_2027/.bundle/ruby/3.2.0`
  and exports `RAILS_DB_*` towards the postgres container
  (`127.0.0.1:5432`), so gems, `rspec` and the language server all run
  host-side against the containerized services.
- ruby-lsp does not need to be in any project Gemfile: its executable
  generates a *composed bundle* under `app/.ruby-lsp/` that wraps the
  project's own bundle.

## The combined core+wagon workspace

A ruby-lsp instance indexes the files under its workspace root plus
all gems in the bundle. Rooted at the **core** repo it sees the wagon
(the `Wagonfile` loads `../hitobito_*` as path gems), but rooted at
the **wagon** it would not see core. Hence one workspace rooted at
`development/app`, driven by the [`Gemfile`](Gemfile) in this
directory.  It lives here (tracked) and is symlinked as
`development/app/Gemfile`, because `app/` is entirely gitignored — the
file would otherwise be invisible to everyone else. Bundler resolves
the relative paths inside it from the symlink's location (`app/`),
which is what we want.  `app/Gemfile.lock` and `app/.ruby-lsp/` stay
untracked.

Result: go-to-definition, references, rename etc. work across core ↔
wagon in both directions. RuboCop still picks the nearest
`.rubocop.yml` per inspected file, so core and wagon keep their own
lint rules.

## Day-to-day

- **Diagnostics/format**: RuboCop runs through ruby-lsp automatically
  (`.rubocop.yml` present, rubocop ≥ 1.4 in the bundle). Format a
  buffer via lsp-mode (`C-c l = =`).
- **Specs**: rspec-mode — `C-c , v` (file), `C-c , s` (example at
  point), `C-c , t` (toggle spec ↔ target), `C-c , r` (rerun),
  `C-c , f` (rerun failures). Runs `bundle exec rspec` on the host
  against the container database (`RAILS_TEST_DB_NAME=hitobito_test`
  keeps it away from the dev DB). `hit test` in a terminal remains the
  container-side alternative.
- **Console**: `M-x inf-ruby-console-auto` in the core repo, or
  `hit rails attach` in a terminal to reach a `binding.pry` inside
  Docker (the project uses pry-byebug, not the `debug` gem — so no
  DAP debugging; pry is the way).
- **Rails navigation**: projectile-rails (`C-c r ...`) — most useful
  inside the core repo.

## The `ruby-lsp-rspec` add-on

[ruby-lsp-rspec](https://github.com/st0012/ruby-lsp-rspec) teaches
ruby-lsp about the RSpec DSL and is part of the workspace
[`Gemfile`](Gemfile). It adds three things — and in Emacs two of them
pay off:

| Feature | Emacs |
|---|---|
| **Document symbols** — `describe`/`context`/`it` blocks as symbols | ✅ Real win: imenu and symbol pickers show the spec structure instead of just the class |
| **Go to definition for `let` / `subject`** | ✅ Works, plain `textDocument/definition` (`M-.`) |
| **CodeLens** ("Run", "Run In Terminal", "Debug" above each example) | ⚠️ Not usable in this setup, see below |

Why CodeLens does not help here: lsp-mode does implement the lens
commands (`rubyLsp.runTest` and `rubyLsp.runTestInTerminal` in
`lsp-ruby-lsp.el`; `rubyLsp.debugTest` has no handler at all), but it
runs them with `default-directory` set to the **workspace root** — and
from `development/app` rspec cannot resolve its own config:

```
$ cd development/app && bundle exec rspec hitobito_wsjrdp_2027/spec/models
LoadError: cannot load such file -- spec_helper
```

`.rspec` and `spec_helper` are found relative to the repo root, so
specs must be started from core or wagon. rspec-mode does exactly that
(it derives the root from the visited file), which is why running specs
stays rspec-mode's job (`C-c , v` / `C-c , s`) regardless of this
add-on. It is here for the navigation, not for the buttons.

Declaring it in the workspace `Gemfile` (like `ruby-lsp-rails`) keeps
it to the language server; the containers never see it. The
alternative would be the wagon `Gemfile` in the `:development` group,
which is team-wide: no lock churn (the wagon `.gitignore` ignores
`Gemfile.lock`), but everyone would install the gem, including inside
the container.

The `debug` gem that the "Debug" lens would need is already added by
ruby-lsp's composed bundle.

## Updating & troubleshooting

- Update the server: `gem update ruby-lsp` (direnv active); the
  composed bundle refreshes itself on the next start. Note that the
  add-ons pin the server to a minor version (`ruby-lsp-rspec` wants
  `~> 0.26.0`), so a jump to the next minor waits until they follow.
- After gem changes: re-run `./doc/emacs/setup-ruby-lsp.sh`, then
  `M-x lsp-workspace-restart`.
- Server misbehaves / stale state: `rm -rf development/app/.ruby-lsp`
  and re-run the script; `M-x lsp-doctor` checks the Emacs side.
- `ruby-lsp` not found in Emacs: check that the buffer really has the
  direnv environment (`M-x envrc-reload`) — envrc must be active before
  lsp starts.
- `WARN: Unresolved or ambiguous specs ... stringio` while installing
  gems: harmless rubygems noise, caused by the project gemset and the
  rbenv gems both being on `GEM_PATH`.
