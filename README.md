# Hitobito Wsjrdp 2027
This hitobito wagon is the registration for the [German Contingent](https://www.worldscoutjamboree.de).

## Setup Dev Environment
It is basically the [hitobito dev setup](https://github.com/hitobito/development/blob/master/doc/setup.md).
And in addition the [wagon creation for hitobito](https://github.com/puzzle/wagons).

### Pinned versions

The wagon only works with matching versions of the hitobito core and the
development environment. Do **not** use their latest `master`. Use this
known-good combination:

| Repository | Path | Checked-out state |
| --- | --- | --- |
| [hitobito/development](https://github.com/hitobito/development) | `WSJ2027Anmeldung/development` | commit `da1f3e09964bf9775f2fc533f97adeb2a9a50381` |
| [hitobito/hitobito](https://github.com/hitobito/hitobito) | `WSJ2027Anmeldung/development/app/hitobito` | tag `2.5.7` |
| [smeky42/hitobito_wsjrdp_2027](https://github.com/smeky42/hitobito_wsjrdp_2027) | `WSJ2027Anmeldung/development/app/hitobito_wsjrdp_2027` | `main` |
| [smeky42/wsjrdp_scripts](https://github.com/smeky42/wsjrdp_scripts) (optional) | `wsjrdp_scripts` | `main` |

Resulting directory layout:

```text
Worldscoutjamboree/
├── WSJ2027Anmeldung/
│   └── development/            # hitobito/development @ da1f3e0 (branch wsjrdp)
│       └── app/
│           ├── hitobito/               # hitobito core @ 2.5.7
│           └── hitobito_wsjrdp_2027/   # this wagon @ main
└── wsjrdp_scripts/             # helper scripts @ main
```

### Prerequisites (macOS)

```bash
brew install --cask orbstack   # Docker runtime (Docker Desktop works too, see below)
brew install uv                # only needed for wsjrdp_scripts
brew install postgresql@16     # pg_dump / pg_restore, matching the postgres:16 dev container
echo 'export PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH"' >> ~/.zshrc
```

### Clone and start

```bash

# hitobito development environment, pinned
mkdir WSJ2027Anmeldung && cd WSJ2027Anmeldung
git clone https://github.com/hitobito/development.git
git -C development switch -c wsjrdp da1f3e09964bf9775f2fc533f97adeb2a9a50381

# hitobito core (pinned to 2.5.7) and the wsjrdp_2027 wagon
cd development/app
git clone --branch 2.5.7 https://github.com/hitobito/hitobito.git
git clone git@github.com:smeky42/hitobito_wsjrdp_2027.git
cd ..

# docker volumes
docker volume create hitobito_bundle
docker volume create hitobito_yarn_cache

# start the hit environment (from WSJ2027Anmeldung/development)
RAILS_UID=$(id -u) ./bin/dev-env.sh
> hit up
```

The app runs at **http://localhost:3000**. It is served over plain HTTP, so
`https://` does not work. Mailcatcher runs at http://localhost:1080.

Optionally, activate the [local dev overrides](#local-dev-overrides-dev-only-overrides)
(e.g. login bypass, macOS file watcher):

```bash
cd app/hitobito_wsjrdp_2027 && ./dev-only-overrides/create_symlinks.sh
```

To create a new bare wagon instead of cloning this one:

```bash
cd development/app/hitobito
rails generate wagon wsjrdp_2027
mkdir ../hitobito_wsjrdp_2027
mv vendor/wagons/wsjrdp_2027/* ../hitobito_wsjrdp_2027
```

### Load the production database into dev (optional)

```bash
cd Worldscoutjamboree
git clone git@github.com:smeky42/wsjrdp_scripts.git
cd wsjrdp_scripts
# put the (gitignored) config-prod.yml into wsjrdp_scripts/ (ask the team for it)
WSJRDP_SCRIPTS_CONFIG=config-prod.yml uv run tools/db_dump_and_restore_into_dev.py
```

On an ARM macOS with Docker Desktop you might need to set
`DOCKER_DEFAULT_PLATFORM`, e.g., you might need to start `dev-env.sh`
like so:
```sh
RAILS_UID=$(id -u) DOCKER_DEFAULT_PLATFORM=linux/amd64 ./bin/dev-env.sh
```

### Emacs

See [doc/emacs/README.md](doc/emacs/README.md) for an Emacs-based
development setup. The setup is scripted in
[doc/emacs/setup-ruby-lsp.sh](doc/emacs/setup-ruby-lsp.sh).


## Wsjrdp 2027 Organization Hierarchy

This hitobito wagon defines the organization hierarchy with groups and roles
of Wsjrdp 2027.

    * CMT < CMT
      * CMT
        * Admin: [:layer_and_below_full, :admin, :finance]
        * Leader: [:layer_and_below_full]
        * CMT: []
        * Finance: [:layer_and_below_full, :finance]
    * Extern < CMT
      * Extern
        * Extern: []
    * IST < IST, CMT
      * IST
        * IST Manager: [:layer_and_below_full]
        * IST: []
    * Unit < CMT
      * Unit
        * Unit Manager: [:layer_and_below_full]
        * Unit Leader: [:group_full]
        * Unit Leader (unbestätigt): []
        * Youth Participant: []

<!-- roles:start -->
(Output of rake app:hitobito:roles)
<!-- roles:end -->


## Local dev overrides (`dev-only-overrides/`)

Local-only tweaks for the development environment live in
[`dev-only-overrides/`](dev-only-overrides/). The files are part of
the repo, but Rails does not load anything from this directory.  Each
override becomes active only once a developer opts in by creating a
symlink at the original path. These symlinks are gitignored. So a
fresh checkout (and any deployment) has none of them active. As a
second line of defense the initializers refuse to boot in production
and are no-ops outside development.

| Override (file in `dev-only-overrides/`) | Symlinked to | Purpose |
| --- | --- | --- |
| `local_dev_only_login_bypass.rb` | `config/initializers/local_dev_only_login_bypass.rb` | Skips the login on `:3000` and acts as the person configured in the optional, gitignored `config/dev_only_settings.local.yml` (`dev_only` → `login_bypass` → `current_user_person_id`; defaults to person 1) — unless a warden session exists (a real sign-in or an impersonation), which stays authoritative. |
| `local_dev_only_file_watcher_macos.rb` | `config/initializers/local_dev_only_file_watcher_macos.rb` | Switches to the polling file watcher: Docker Desktop's macOS bind mounts do not forward inotify events, so the default evented watcher never fires and edited views are served stale until restart. Linked on macOS only. |
| `local_dev_only_impersonate_delay.rb` | `config/initializers/local_dev_only_impersonate_delay.rb` | Shortens the wait before the admin tab's "Imitieren" button can be pressed: linking it in alone brings it down to 1000 ms, and `dev_only` → `impersonate_delay` → `milliseconds` in the same settings file sets any other value (`0` leaves the button ready at once). Without the override the wait is fixed at 3000 ms and no request parameter can change it. |
| `local_db_dump_shim.rake` | `lib/tasks/local_db_dump_shim.rake` | No-op absolute `db:_dump` / `db:_dump_rails` tasks so `rails app:db:migrate:down` run through the `app:` proxy does not abort (the wagons gem references the absolute task name). Schema dumping stays skipped on purpose. |

To (re-)create the symlinks after a fresh checkout:

```bash
./dev-only-overrides/create_symlinks.sh
```

The script is idempotent: correct links are left alone, stale links are fixed,
and it refuses to replace a real file at a target path (move that file into
`dev-only-overrides/` first). The file watcher is only linked when running on
Darwin (macOS); the links are relative, so they also resolve inside the Docker
bind mount.

To act as a person other than person 1, create the (gitignored) file
`config/dev_only_settings.local.yml` and restart the app:

```yaml
dev_only:
  login_bypass:
    current_user_person_id: 42
```
