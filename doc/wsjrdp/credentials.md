# Credentials (the credential store)

The credential store keeps the passwords and API keys of the services the
app talks to (a mailbox, Moss, mailcow, a helpdesk), sealed with a key of the
instance's stage. The code lives in `app/domain/wsjrdp/credentials/` and
`app/models/wsjrdp_credential.rb`.

**What exists so far:** the keys, the sealing, the kinds, the table with
its model, three write paths (`Deposit`, `Change`, `Rekey`), the lookup
(`Wsjrdp::Credentials.fetch` / `.candidates`), the overrides by variables
and a local file, the read model for the pages (`Overview`) and the reader
of typed instants ([`Wsjrdp::InstantInput`](instant_input.md)). **No
consumer reads a credential yet**, and there is no page.

## Terms

| Thing | Meaning |
|---|---|
| kind | the blueprint of a credential: its fields, and which are secret (`config/wsjrdp_credential_kinds.yml`) |
| account | one credential of a kind, named by its account key (`mail_account` / `finanzen`) |
| version | one set of an account's values in one stage: a row of `wsjrdp_credentials`, or an override |
| key | 32 random bytes a stage seals its secret fields with; known by its fingerprint |
| credential | what a consumer gets: the values of one version (`Wsjrdp::Credentials::Credential`) |

## Names and the one safety rule

- A **stage** is `[a-z0-9]+`. The stage of an instance is the one of the
  API keys: `RAILS_STAGE` (default `production`) under
  `RAILS_ENV=production`, else the Rails environment.
- A **kind** and a **field name** are lower-case snake without a double
  underscore, at most 48 characters (`Wsjrdp::Credentials.name?`).
- An **account key** is wider: lower-case letters of any script and the
  digits 0-9, joined by single characters of `_ @ , . + -` (none at the
  start or the end, never two in a row), at most 64 characters
  (`account_key?`), such as `foo@worldscoutjamboree.de`.
  Wherever a key enters the store it is folded to lower case and brought
  to Unicode NFC (`account_key_of`), so `Foo@Example.org` and
  `foo@example.org` are one account. A key holds no `/`, so the purpose of
  a sealed value reads one way only. Like a name, a key is repeated in a
  message only when it is valid.
- **Valid text** is a String of valid UTF-8 without a NUL character
  (`Wsjrdp::Credentials.text?`); a String of another encoding counts only
  when it is plain ASCII. Every value, name and comment must be one.
- **Nothing ever prints a value or a key.** Messages and logs name fields,
  entries, variables, places in the registry or a file, codes and key
  fingerprints. A name is repeated only when it is valid and a stage only
  when it is short; anything else shows as `(not a name)`, `(not a stage)`
  or "another stage", since it may be a secret typed into the wrong place
  (64 hex digits are a valid stage).
  `inspect`, `as_json` and `pp` of every object of the store follow this
  rule; Marshal and YAML refuse to dump them. Keep it that way in any new
  code.

## Keys

### `HITOBITO_CREDENTIAL_KEYS`

A comma-separated list of `<stage>:<64 hex>` entries. The 32 bytes are the
AES-256 key as they are. Make one with `openssl rand -hex 32`:

```
HITOBITO_CREDENTIAL_KEYS=production:<64 hex>,production:<64 hex>
```

It is a variable of its own, never shared with
`HITOBITO_SERVICE_TOKEN_HMAC_KEYS` ([service_tokens.md](service_tokens.md)).

- Only the entries of the instance's stage count. The **first is active**:
  new values are sealed with it. **All are accepted**: a value sealed with
  any of them opens. An entry of another stage seals and opens nothing;
  it is logged with a warning and kept by fingerprint and stage only, so
  that the pages can list it.
- A **problem** stops every stage but production
  (`Wsjrdp::Credentials::ConfigurationError`); production logs it, ignores
  the entry and starts. Problems are: a malformed entry, an entry or label
  that is not valid text, a secret given twice, a `production` entry outside
  production, and a committed public key outside the stage `test` or under
  `RAILS_ENV=production` (whatever `RAILS_STAGE` says).
- **Without any key** the instance starts, warns once, and sealing raises
  `Wsjrdp::Credentials::NoKeyError`.
- **No stage has a committed key**, development included. Only the Rails
  environment `test` falls back to `credentials.keys_default` in
  `config/settings/test.yml`. That key and the golden-vector spec's key are
  public; the code knows them by fingerprint (`Keys::PUBLIC_FINGERPRINTS`)
  and refuses them as said above.
- Where the variable is not set, the local file's `keys` may be used (see
  "The local file" below).

### `HITOBITO_CREDENTIAL_LABEL`

Optional free text naming the instance's key (`laptop-a`). It is shown in
the boot log and written into every version a deposit or a re-key makes.

### The fingerprint

The SHA-256 of the secret, lower-cased, as 64 lower-case hex digits (the
HMAC keys of the API keys use Base64 instead). The boot log names the
active and accepted keys by fingerprint. To compute one:

```bash
printf %s "$SECRET" | tr 'A-F' 'a-f' | sha256sum    # macOS: shasum -a 256
```

### Losing a key

A key cannot be recovered from anything the app stores; losing it means
entering that stage's credentials again (the providers stay the source of
truth). Keep it with `HITOBITO_SERVICE_TOKEN_HMAC_KEYS`, not in the database
backup. Keep an old key in the list, after the active one, until every
version sealed with it is re-keyed.

## Sealing

**Each secret field is sealed by itself** with Rails'
`ActiveSupport::MessageEncryptor` (AES-256-GCM), so that one field can be
overwritten alone; fields that are not secret are not sealed. The text is
bound to its stage, kind, account and field: copied into another account
or field it does not open, but it can move between versions of the same
account and field. The stored form is called `rails-me-v1`.

**The golden-vector spec**
(`spec/domain/wsjrdp/credentials/golden_vector_spec.rb`) holds texts that
must keep opening. **Never repair it by making new texts.** If it fails
after a Rails upgrade, stored credentials can no longer be opened: stop the
upgrade and find out what changed in `MessageEncryptor`.

## Kinds: `config/wsjrdp_credential_kinds.yml`

The registry, committed and free of secrets. A further service is a
further kind.

```yaml
kinds:
  moss_api:
    title_field: client_id            # shown as the account's name in lists
    remind_days_before: [30, 14, 3]   # default lead times of an expiry reminder
    fields:
      base_url:      {type: url, required: true, default: "https://public-api.getmoss.com"}
      client_id:     {type: string, required: true}
      client_secret: {type: string, required: true, secret: true}
      scope:         {type: enum, values: [read, write], default: read}
```

| Type | Becomes | Accepted |
|---|---|---|
| `string` | String | a String, as given |
| `email` | String | a String of the form of an address |
| `integer` | Integer | an Integer that fits a bigint, or up to 19 decimal digits with an optional sign (`"587"`) |
| `boolean` | `true` / `false` | `true`, `false`, `"true"`, `"false"`, `"1"`, `"0"` |
| `enum` | String | any text; the field's `values` are suggestions for the form, its `default` one of them |
| `url` | String | an absolute `http` or `https` URL with a host and without user info |

- Nothing is stripped: `" 587"` is no integer. `nil` and `""` are not set;
  a field not set gets its default.
- The file is read strictly: anything it does not understand raises
  `Kinds::RegistryError` in every stage, production included. Reserved
  field names: `name`, `created_at`, `valid_from`, `expires_at` (they stand
  beside the fields in a variable). A secret field has no default.
- `kind.cast(values, stage:)` gives the values with `errors` and `warnings`
  as codes (`required`, `unknown`, `not_an_integer`, `not_valid_text`, ...).
  A `url` that is not `https` is a warning (`not_https`) in production only.

## The value object: `Wsjrdp::Credentials::Credential`

```ruby
credential[:smtp_host]             # a public field
credential.secret(:smtp_password)  # a secret field
```

`[]` refuses a secret field and `secret` a public one
(`Credential::WrongAccess`), so a secret is only read on purpose. An unknown
field is `Credential::UnknownField`; a field that is not set is `nil`.
`version_name` and `version_id` say which version it is.

## The table: `wsjrdp_credentials`

One row is **one version of one account in one stage**
(`WsjrdpCredential`). Each column carries its comment in the database.

| Columns | What they hold |
|---|---|
| `kind`, `account_key`, `stage` | the account and the stage; fixed once written |
| `name`, `comment` | the version's own name and comment |
| `public_data` | the fields that are not secret, plain: `{"smtp_port" => 587}` |
| `secret_data` | each secret field sealed by itself: `{"smtp_password" => "<sealed text>"}` |
| `scheme`, `encryption_key_fingerprint`, `encryption_key_label` | the version's one key |
| `valid_from`, `expires_at`, `revoked_at` | instants in UTC |
| `remind_days_before`, `remind_emails`, `reminded_at` | reminder data; no mail is sent yet |
| `last_success_at`, `last_failure_at`, `last_failure_message` | feedback from use; nothing writes them yet |
| `author_id`, `author_type` | who deposited it |

Nothing is unique beyond the id: versions of an account may overlap.

**One key per version.** Every sealed value of a row uses the key the row
names, and a new version names the active key even without a secret field.
Who can write the database but has no key cannot read a sealed value. He
can change any plain field (point `base_url` elsewhere), and he can put a
made-up value for a secret field into the plain column: reading never
depends on the column, and a plain value is not authenticated. Only a
sealed value of the same name wins over it.

## The model: `WsjrdpCredential`

- **Fixed once written:** `kind`, `account_key`, `stage`, the author and
  `created_at`. Everything else can change; the key columns through a
  re-key.
- **Instants:** `valid_from=`, `expires_at=` and `revoked_at=` take a `Time`
  or `nil`, nothing else (else `not_an_instant`). A version counts **from
  `valid_from` on, up to but not including `expires_at`**, and is revoked
  from `revoked_at` on. A typed instant is read by
  [`Wsjrdp::InstantInput`](instant_input.md). Do not use
  `write_attribute` for instants: it parses a text in the app's time zone.
- **Reading a field never depends on its column** (`field_values`); a
  changed kind cannot hide a field. If a name is in both columns, the
  sealed value wins over the plain one; a plain value is not
  authenticated.
- **Writing a field** (`write_field`) puts it into the column named and
  removes it from the other; the write paths name the column the kind says
  now.
- `field_report` lists, by name, which fields are sealed, plain, in both
  columns, in the wrong column, unknown to the kind, or do not open: for
  the pages. `secret_key_problem(keys)` says why secret fields cannot be
  changed with these keys (see `Change` below), or nil.
- Validation messages are fixed texts; `errors.details` holds codes only.
- **Hygiene:** `as_json` and `to_xml` leave `secret_data` out; `inspect`
  and the SQL log mask both value columns (initializer
  `wsjrdp_2027.credential_log_filter`).

### The states of a row

`row.examine(at:, keys:, kinds:)` gives the state and, where the values
open and fit, the `Credential` and the kind's warnings (`not_https`).
It never raises for the row's content.

Checked in this order:

| State | Meaning |
|---|---|
| `other_stage` | a row of another stage |
| `key_missing` | sealed with a key this instance does not have |
| `kind_unknown` | its kind is no longer in the registry |
| `unreadable` | a sealed value does not open, the scheme is unknown, or the row is malformed |
| `kind_mismatch` | it opens, but no longer fits its kind |
| `revoked` | `revoked_at` is reached |
| `expired` | `expires_at` is reached |
| `not_yet_valid` | `valid_from` lies ahead |
| `active` | usable here |

Content comes before the lifecycle, so that a planned version that will not
open says so before its time comes. When the registry changed since a
version was written, its fields are cast again with the kind as it is now;
a version that no longer fits is `kind_mismatch`, until `Change` gives the
field anew.

### The trail: PaperTrail

PaperTrail records creating, changing, re-keying and deleting a version
(`item_type` `WsjrdpCredential`, no `main`).

- **No sealed text is ever in the trail**: `secret_data` is skipped, so an
  old secret cannot be restored, on purpose. `wsjrdp_data` names the secret
  fields that were set, changed, re-sealed or removed
  ([log_entries.md](log_entries.md)).
- A change of secret fields alone is recorded too (names only).
- The health columns and `updated_at` make no entry.
- Do not use `row.paper_trail.update_columns`: it writes the changes
  without the skip.

## The write paths

Each gives a `Wsjrdp::Credentials::WriteResult` and writes nothing on an
error:

```ruby
result.saved?        # the row was written
result.record        # the row as written, nil when nothing was written
result.field_errors  # Kind::Problem(field, code), e.g. client_secret: key_not_active
result.errors        # Kind::Problem(attribute, code), e.g. expires_at: not_after_valid_from
result.warnings      # e.g. base_url: not_https in production
```

They raise only for a programming error (values that are not a Hash, an
instant that is not a `Time`, a record that is not saved). `Deposit` and
`Rekey` also raise `NoKeyError` when the instance has no key; `Change`
answers `key_missing` for a secret field instead. `Change` and `Rekey` lock
the row; a row of another stage is `stage: other_stage` and is not changed
at all. A value column that is not a hash (a row written past the
validations) is `not_field_values`: `Rekey` changes nothing, `Change`
writes no field.

### `Deposit`: a new version

```ruby
Wsjrdp::Credentials::Deposit.call(kind: "moss_api", account_key: "default",
  values: {"client_id" => "...", "client_secret" => "..."}, name: "key of May",
  valid_from: Time.utc(2027, 5, 1), expires_at: Time.utc(2027, 11, 1), comment: "...", author: current_person)
```

Casts the values with the kind and seals each secret field with the active
key. Always for the instance's own stage, and always needs a key.

### `Change`: change a version

```ruby
Wsjrdp::Credentials::Change.call(record: row, values: {"client_secret" => "...", "scope" => ""},
  name: "key of June", valid_from: Time.utc(2027, 6, 1), expires_at: nil)
Wsjrdp::Credentials::Change.call(record: row, revoked_at: Time.current)  # revoked_at: nil takes it back
```

- **Only what is given changes.** A field given as `nil` or `""` is
  removed, so a form must leave out a secret field nobody touched.
- **The kind's rules are checked for the fields given only.** A version a
  changed registry left stale can still be revoked, renamed and
  re-windowed.
- **A secret field** can be changed only while the version's key is the
  active key. Otherwise: `key_not_active` (re-key first), `key_missing` (a
  new version is the way to new secrets) or `unknown_scheme`. Plain fields,
  name, comment and window change whatever the key.
- **`expected_updated_at:`** (optional): the row's `updated_at` when the
  form was drawn. A row changed since is refused as `base: stale`; the
  check runs under the lock.

### `Rekey`: seal a version with the active key

```ruby
Wsjrdp::Credentials::Rekey.call(record: row)
```

Every sealed value is opened with the version's key and sealed again with
the active key; every field moves into the column the kind names now. **All
or nothing:** a value that does not open (`not_opening`), a missing key
(`key_missing`) or an unknown scheme changes nothing. With the active key
already, only misplaced fields move (warning `already_active`).

## The lookup: `Wsjrdp::Credentials.fetch` and `.candidates`

```ruby
moss = Wsjrdp::Credentials.fetch(:moss_api, "default")    # or Wsjrdp::Credentials::NoCredentialError
moss[:client_id]
moss.secret(:client_secret)
Wsjrdp::Credentials.candidates(:moss_api, "default")      # the usable versions, newest first
```

- The sources are asked in the order of "Overrides" below; the first that
  names an account answers for it as a whole.
- A usable row is in state `active`. **The newest wins** (by `created_at`);
  the others are the fallbacks. The window decides *whether* a version
  counts, never *which* one wins.
- Nothing is remembered: each call reads the rows again.
- `NoCredentialError` names the account, the stage and the states found:
  `moss_api/default: no usable version in stage test (database: 2 versions,
  none usable: expired 1, other_stage 1)`.

## Overrides: variables and the local file

An account can be overridden by environment variables and by a local YAML
file. Both are read once at boot; a change needs a restart. In development
a code reload reads the local file (and the keys) again at the next lookup;
the variables stay as the boot took them.

**Which source wins, per account as a whole:** the variables, then the
file, then the database. If any variable names an account, the variables
are its credential; else the file's entry; else the database. An override
without a usable version still answers for its account: `fetch` raises,
and the database is not asked.

| | production | staging, development | Rails env test |
|---|---|---|---|
| Key from | variable | variable, else file | variable, else committed |
| Overrides from | variables | variables, else file | variables |

### The variables

```bash
HITOBITO_CREDENTIAL__<STAGE>__<KIND>__<ACCOUNT>__<FIELD>=<value>
HITOBITO_CREDENTIAL__<STAGE>__<KIND>__<ACCOUNT>__NAME=<the version's name>
HITOBITO_CREDENTIAL__<STAGE>__<KIND>__<ACCOUNT>__CREATED_AT=2026-11-20T09:00Z   # also VALID_FROM, EXPIRES_AT

HITOBITO_CREDENTIAL__STAGING__MOSS_API__DEFAULT__CLIENT_ID=made-up-client
HITOBITO_CREDENTIAL__STAGING__MOSS_API__DEFAULT__CLIENT_SECRET=made-up-secret
```

- The names in upper case, separated by a double underscore. The variables
  of an account describe **one** version.
- `<ACCOUNT>` is the account key in upper case, each of `_ @ , . + -`
  as `_`: `default` is `DEFAULT`,
  `foo@worldscoutjamboree.de` is `FOO_WORLDSCOUTJAMBOREE_DE`
  (`Variables.account_part`). Keys that come out the same (`a.b`, `a-b`,
  `a_b`) share their variables, which then answer for whichever is asked
  for.
- Not every system allows letters beyond A-Z in the name of an
  environment variable.
- Only the instance's own stage counts. A `PRODUCTION` variable outside
  production stops the boot; a variable of another stage is ignored with a
  warning.
- Values are strings, cast with the kind; an empty value is not set.

### The local file: `config/wsjrdp_credentials.local.yml`

Git-ignored, never written by the app; it holds keys and secrets in plain
text, so keep it readable for yourself alone. A made-up example:

```yaml
stage: development                 # required: the stage this file is for
keys: ["development:<64 hex>"]     # optional, as HITOBITO_CREDENTIAL_KEYS
label: laptop-a                    # optional, as HITOBITO_CREDENTIAL_LABEL
credentials:                       # kind -> account key -> versions
  moss_api:
    default:
      versions:
        - name: Key December 2026
          created_at: 2026-11-20T09:00Z
          valid_from: 2026-12-01
          expires_at: 2027-05-19
          vars:
            base_url: https://moss.example.org
            client_id: made-up-client-new
            client_secret: made-up-secret-new
        - name: Key June 2026
          created_at: 2026-06-18
          expires_at: 2026-12-15T12:00+01:00
          vars: {base_url: https://moss.example.org, client_id: made-up-client-old, client_secret: made-up-secret-old}
```

- An account key is a YAML key, quoted where YAML needs it
  (`"foo@worldscoutjamboree.de":`); two keys that fold to the same are a
  problem.
- **Production never reads it**, and neither does the Rails environment
  `test`. In production a file lying there is not opened; the log warns.
- **A file whose `stage` is not the instance's own is skipped** with a
  warning, a file saying `stage: production` included: no key and no
  credential is taken from it, and the boot goes on.
- **Every value is text, quoted or not**; YAML's own typing does not
  happen. `smtp_port: 0465` is 465 (cast by the kind, not octal), `yes` is
  no boolean, `12345` as a password is the text `"12345"`. Only an empty
  value, `null` and `~` are not set. Aliases are refused, and so is every
  tag but the standard ones for text, a mapping and a list (`!!str`, `!`,
  `!!map`, `!!seq`).
- Where `HITOBITO_CREDENTIAL_KEYS` is not set, the file's `keys` and
  `label` are the instance's (never merged with the variables; the log says
  when one of them is not used). A `label` without `keys` is not used
  either, with a warning.

### Which version of an override is used

- A version counts from `valid_from` on and up to, not including,
  `expires_at`, and only if its values fit the kind.
- Of those the newest wins, the others are fallbacks: by `created_at` if
  every version states it, else by the order of the list (the first wins,
  as for the key list). If only some state it, that is a problem: the boot
  stops.
- Instants are ISO 8601, read by [`Wsjrdp::InstantInput`](instant_input.md):
  without a zone UTC, and **a bare date is 00:00 UTC** -- `expires_at:
  2027-05-19` ends the version at the start of the 19th.
- Nothing is sealed: a credential from an override has no row and no key.

| State of an override's version | Meaning |
|---|---|
| `refused` | production found a problem in the account (below); it gives no credential at all |
| `kind_mismatch` | its values do not fit the kind |
| `expired` | `expires_at` is reached |
| `not_yet_valid` | `valid_from` lies ahead |
| `active` | usable here |

### Strictness

Every variable whose name begins with `HITOBITO_CREDENTIAL` and every key of
the file must be understood: an unknown key, a name outside the grammar, an
unknown kind or field, an instant that is none, an expiry not after the
start. The message names the variable or the place in the file
(`credentials.moss_api.default.versions[2].expires_at: not an instant: ...`),
never a value.

- **Every stage but production refuses to start**
  (`Wsjrdp::Credentials::ConfigurationError`).
- **Production logs the problem, starts, and fails safe:** an account with
  a problem is refused -- it answers with no usable version, and the
  database is not asked. A broken variable of this stage refuses the
  account it names; when no account can be read from it, every account of
  the variables. The log line says which.
- Values that do not fit the kind (a required field missing) are no
  problem at boot: the version is not usable, and `fetch` says why.
- **What cannot be caught:** a typo in the stage (`…__PRODUKTION__…` reads
  as another stage) or in the letters of the prefix (`HITOBITO_CREDENTAIL…`
  is not looked at); a broken variable at an instance whose variables name
  no account (the database answers); a misspelt account key that is still
  a name (`…__MOSS_API__DEFAUL__EXPIRES_AT` names an account `defaul`,
  which does not fit the kind, while `default` is used without its
  expiry). Check the boot log after changing a variable.

### A development instance with a key and a file

1. `openssl rand -hex 32` makes a key.
2. Write `config/wsjrdp_credentials.local.yml` with `stage: development`,
   the key as `"development:<64 hex>"`, a label and the credentials you
   need; `chmod 600` it.
3. Restart. The log names the key by fingerprint and the accounts the file
   overrides; anything not understood stops the boot.

The key also opens what you deposit in this instance's database: keep it.

### For the pages: `Wsjrdp::Credentials::Overview`

`Overview.new.account(kind, account_key)` and `.accounts` describe every
source of an account: its versions with their states, the source in use,
the active version and its fallbacks, and what is overridden by which
source. `#file` says what became of the local file, `#keys` where the key
came from and every key by fingerprint, those of other stages included.
Values come only through the `Credential` objects; nothing
prints a version's name, a value or a key.

## Specs

`spec/domain/wsjrdp/credentials/` and
`spec/domain/wsjrdp/instant_input_spec.rb` are standalone (no Rails, no
database):

```bash
bundle exec rspec spec/domain/wsjrdp/credentials spec/domain/wsjrdp/instant_input_spec.rb
```

The model, the write paths, the lookup with the database and the boot
wiring need the test database; run them by the rules of `AGENTS.md`
("Running tests"): `spec/models/wsjrdp_credential_spec.rb`,
`spec/domain/wsjrdp/credentials_store_spec.rb`,
`spec/domain/wsjrdp/credentials_keys_boot_spec.rb`,
`spec/domain/wsjrdp/credentials_overrides_spec.rb`. No spec reads the local
file, but the boot reads the environment: set no `HITOBITO_CREDENTIAL*`
variable in the shell that runs the specs.
