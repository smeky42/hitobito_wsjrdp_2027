# Synchronisation

`/fin/sync` copies data from Moss into Hitobito, part by part. A run
fetches, shows what would change, and writes only once confirmed. Only
Admin and the manage tier (`:configure_finance`) see it.

Tabs: Übersicht (the newest runs of every source, deleting old files),
Moss API (choose, fetch, its runs), Moss CSV (empty). The runs are an
expandable table: ID, start, source (what was synchronised), parts,
status, duration, rows written (who started it and the four row counts to
choose). A row opens the run's core data (`fin/sync_runs/_fields`, the
detail kit of `doc/fin/detail_partials.md`, also on the run's page) and its
parts.

## Parts

`Wsjrdp::Sync.parts`, in the order a run handles them. The tree on the page
comes from their keys, one level per segment (Moss API >
Organisationsstruktur or Stammdaten > the parts), so a whole branch is
chosen at once; `source` says what a part reads (`moss_api`):

| Key | Moss | Table |
| --- | --- | --- |
| `moss_api.organisation_structure.departments` | `/v1/departments` | `moss_departments` |
| `moss_api.organisation_structure.teams` | `/v1/teams` | `moss_teams` |
| `moss_api.organisation_structure.users` | `/v1/users` | `moss_users` |
| `moss_api.master_data.dimensions` | `/v1/dimensions` | `moss_dimensions` |
| `moss_api.master_data.cost_centers` | items of dimension `…0001` | `wsjrdp_cost_centers` |
| `moss_api.master_data.spheres` | items of dimension `…0002` | `wsjrdp_spheres` |
| `moss_api.master_data.ledger_accounts` | `/v1/expense-accounts` | `wsjrdp_ledger_accounts` |
| `moss_api.master_data.payment_terms` | `/v1/payment-terms` | `moss_payment_terms` |
| `moss_api.master_data.tax_rates` | `/v1/tax-rates` | `moss_tax_rates` |
| `moss_api.master_data.suppliers` | `/v1/suppliers` | `wsjrdp_personal_accounts` |

- A key never changes: the history and the file names rely on it.
- Labels: `fin.sync.parts.<key>._label`.
- `depends_on` comes along automatically (Benutzer → Teams → Abteilungen;
  Lieferanten → Teams, Kostenstellen, Sphären, Sachkonten,
  Zahlungsbedingungen, Steuersätze).

A part (`Wsjrdp::Sync::Part`) has three steps:

- `fetch(client)` returns `{name => JSON}`; each entry becomes a data file.
- `plan(data)` returns a `Wsjrdp::Sync::Plan`: the changes (create, update
  with old and new value, restore, remove) and the notices. Each change names
  what it writes: `target`, the model (`MossUser`, `Person`), and
  `target_column` when its values are keys inside a jsonb column
  (`additional_info`); `ref` ties it to the change of another record of the
  part (a person's fields to their Moss user). The notices come in three levels:
  a **warning** (yellow) needs a second confirmation, an **important** hint
  (blue) and a **hint** (grey) do not. What concerns an archived team or a
  deactivated Moss user is a hint. A notice lists its records (`items`); the
  page links each one that is in its table, with its status and, for a
  user, the e-mail. It writes nothing.
- `apply(data, plan)` writes the plan and returns the rows written
  (`Wsjrdp::Sync::Stats`: inserted, updated, deleted, soft_deleted -- the
  last for rows marked as gone; marking rows seen does not count).

A part that refers to another (a user to its team) checks against what the
run fetched of it, else against the table; so writing an earlier part
never changes the plan of a later one.

### The Moss lists

`Wsjrdp::Sync::MossApi::ListPart` copies one list into one table;
`Wsjrdp::Sync::MossTable` compares and writes:

- A row Moss no longer returns is marked (`moss_removed_at`), never
  deleted, and restored when it comes back. Every row returned gets
  `last_seen_at`.
- Writing takes a few statements however many rows: one insert, one upsert,
  one update.
- Removing every row, or more than five rows and more than a tenth, is a
  warning.
- The lists come 1000 to a page (the most Moss allows); the dimensions
  come in one answer without paging.
- Moss pages by offset, so a pass may repeat a record and skip another.
  When records are missing against `totalItems`, the part reads again in
  the other order. A list still short is a
  warning, and then nothing is marked removed.

Hitobito's own: the `comment` of each row, and the person of a Moss user.
The sync fills an empty person with the one person whose `moss_email` is
the user's (ignoring case), and never replaces one.

A person whose `moss_email` is no user's is an important hint, but only
a hint when no user is to be expected: without a contract
(`contract_status` none), or deregistered with the contract ended. Each
names the person's status, contract and role (`wsjrdp_role`), and whether
a user of the same first and last name exists. A user whose person has no
contract is an important hint.

That person also gets `moss_status`, `moss_team` (the team's name) and
`moss_roles` in `additional_info`, as the CSV import of wsjrdp_scripts
writes them; an empty value removes the key, roles are sorted. One
statement writes every person, with one PaperTrail version each. The phone
comes from the CSV export only.

### The master data

The tables of cost centers, spheres, ledger accounts and creditors are
keyed by number and written by the DATEV and CSV imports too:

- A Moss record finds its row by `moss_uuid`, else by number; else it is
  new. Moss is the system of record for what it returns: name, status,
  bank details, address, the Moss columns. Text is trimmed.
- A record whose UUID belongs to a row of another number, whose number
  belongs to a row of another UUID, or whose number Moss returns twice is a
  warning naming both UUIDs and numbers, and is not written.
- A code that is no number of the table (letters in an account, a creditor
  outside 7xxxxx–9xxxxx) is a warning, and is not written; a row it already
  has keeps its status.
- A row Moss no longer returns keeps everything but `moss_status`, which
  becomes NULL. Moss's statuses are kept in lower case (`active`,
  `deactivated`, `deleted`).
- A changed name is an important hint.
- Moss drops the leading zeros of an account number; they are added up to
  `WsjrdpLedgerAccount::NUMBER_LENGTH`, DATEV's Sachkontenlänge (5 in
  SKR 42). Another length also needs the two number CHECK constraints of
  the ledger and personal accounts changed.

A supplier keeps each Moss reference as a UUID (`default_moss_*_uuid`)
and, next to it, what it names: the account, cost center and sphere
number, the team name. A reference no list has is an important hint.
Account holder, type, the second address line and `other_moss_columns`
come from the CSV export only; the ledger accounts' category and the cost
centers' manager too. A new ledger account keeps `account_kind` UNKNOWN
until DATEV sets it.

## A run

1. **Start** (`Wsjrdp::Sync::Start`), in the request: fetch every part,
   write the files, plan every part; the run is `planned`. When no part
   changes anything, the run ends at once as `unchanged` (only marking the
   rows seen); the page has no buttons then. When anything
   fails, the run is `failed`: the failing part keeps the error, the others
   are `skipped`.
2. **Write** (`Wsjrdp::Sync::Apply`): the parts in order, each in its own
   transaction, planned again first. Only the digest shown is written.
   - Another digest: the part is `stale` with the new plan, the run
     `stopped`.
   - An error: the part is rolled back and `failed`, the run `stopped`.
   - Another run already wrote the part with data fetched later: the part
     `failed`, so older data never undoes newer. A lock on the part key
     lets only one run at a time write a part.
3. **After a stop**: go on (stale parts with their new plan; parts that
   depend on a failed one are `skipped`) or cancel (`Wsjrdp::Sync::Cancel`).

Every phase is timed (`Wsjrdp::Sync::Timing`): the run's (`start`,
`apply`) and each part's (`fetch`, `plan`, `apply`), with start, end, duration
and `status` (`succeeded`, `failed` with `error_message`, or `stale` when a
part's plan had changed), in `timings`.

A run's detail is one partial (`fin/sync_runs/_detail`), on its page and
in a row of the runs table: the core data, „Ablauf“ (the phases), and the
parts as an expandable table (status, changes, rows written, duration, a
badge per notice level). A part opens its notices (each unfolds its
records), its changes and its files.

The changes are a table of their own per part (Aktion, Datensatz, Ziele,
Hinweise), paged when there are more than 25: 50 a page on the run's page,
25 in a row. One row per record: a Moss user's row also carries the Moss
fields of its person (`ref`). „Datensatz“ links the record once it is in
its table. „Ziele“ says per model what is written: „MossUser neu“,
„Person: 2 Felder neu“, „Person: 1 Feld geändert“, „MossUser unverändert“.
A row opens one group of fields per model; a notice's chip stands at its
field, else below the fields. On the run's page the header
is shown, everything is open and the buttons follow; in a row everything
is closed and there are no buttons. The tables come from
`Fin::SyncTables`, which both controllers include.

The run ends `applied`, `partly_applied` or `unchanged`, with the rows
written per part and summed up for the run (`stats` → `modified_rows`; the
top-level key leaves room for further figures). Runs may be open side by side.
An error outside a part stops the run; only a request that dies while
writing leaves it `applying`, and once no part has been written for 10 minutes
it may be cancelled.

## Tables

- `wsjrdp_sync_runs`: source, the credential read with
  (`credential_source` DB, ENV or YAML; `credential_kind`, `account_key`,
  `credential_id` -- NULL for an override), `selected_parts`, `status`, who
  started, confirmed and confirmed the warnings, when, `error_message` (only
  when it failed or stopped), timings, stats.
- `wsjrdp_sync_run_parts`: part key, position, status, times
  (`fetch_started_at`, `applied_at`; the end of each phase is in `timings`),
  the plan shown, its digest, counts, file entries (name, size, SHA-256),
  when the files were deleted, `error_message` (only when it failed),
  timings, stats.

Both have `additional_info`; every column that may be NULL says so.

Last start and write of a part: `WsjrdpSyncRunPart.last_started_at(key)`,
`.last_applied_at(key)`.

## Files

Raw data never goes into the database. Each part has data files and a meta
file (requests and answers, secrets cut out), flat in
`<wagon>/private/sync/` (backed up with `private/`; in tests `tmp/sync/`):

```
20261123T142501Z_run-42_moss_api.organisation_structure.users.data-users.json
20261123T142501Z_run-42_moss_api.organisation_structure.users.meta.json
```

The name starts with the run's start in UTC, so an old file is known by
name. A file is checked against its SHA-256 before use.

„Dateien älter als 90 Tage löschen“ (`Wsjrdp::Sync::Purge`) asks first,
then deletes the files of older runs; runs and plans stay.

## Moss

`Wsjrdp::Moss::Client` reads every page of a list (`each`, `all`), renews
its token before it runs out or once after a 401, tries a read again after
no answer or 429/502/503/504 (twice, after `Retry-After` or 1, 2 seconds),
and keeps every request and answer in its transcript. A run reads with the
newest usable version of the chosen `moss_api` account.

AI agents never start a run (it calls Moss) unless the user asks for it.
