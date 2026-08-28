# Hitobito Wsjrdp 2027
This hitobito wagon is the registration for the [German Contingent](https://www.worldscoutjamboree.de).

## Setup Dev Environment
It is basically the [hitobito dev setup](https://github.com/hitobito/development/blob/master/doc/setup.md).
And in addition the [wagon creation for hitobito](https://github.com/puzzle/wagons).

```bash
# create hitobito development environment
mkdir WSJ2027Anmeldung
cd WSJ2027Anmeldung
git clone https://github.com/hitobito/development.git

# clone hitobito core and wsjrdp_2027 wagon
cd development/app
git clone https://github.com/hitobito/hitobito.git
git clone git@github.com:smeky42/hitobito_wsjrdp_2027.git
cd ..

# OR create a new wagon if you want to start bare
cd development/app/hitobito
rails generate wagon wsjrdp_2027
mkdir ../hitobito_wsjrdp_2027
mv vendor/wagons/wsjrdp_2027/* ../hitobito_wsjrdp_2027
cd ../..

# add docker volumes
docker volume create hitobito_bundle
docker volume create hitobito_yarn_cache

# start docker in hit environment
./bin/dev-env.sh
> hit up
```

If needed (as it was in my MacOS env)
    - add `export RAILS_UID=$(id -u)` to `.bashrc`
    - [install new ruby version](https://mac.install.guide/faq/change-ruby-version/) and [configure your shell env](https://mac.install.guide/ruby/13)
    - install `brew install postgresql` and run `brew services start postgresql@14`  postgress

On an ARM macOS with Docker desktop you might need to set
`DOCKER_DEFAULT_PLATFORM`, e.g., you might need to start `dev-env.sh`
like so:
```sh
RAILS_UID=$(id -u) DOCKER_DEFAULT_PLATFORM=linux/amd64 ./bin/dev-env.sh
```

This hitobito wagon defines the organization hierarchy with groups and roles
of Wsjrdp 2027.

## Wsjrdp 2027 Organization Hierarchy

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
