# Credentials (the credential store)

The credential store keeps the passwords and API keys of the services the
app talks to (a mailbox, Moss, mailcow, a helpdesk), sealed with a key of the
instance's stage.

**What exists so far** are the building blocks, in plain Ruby under
`app/domain/wsjrdp/credentials/`: the instance's keys, the sealing, the kind
registry with the casting of values, and the value object a consumer will
get. **Nothing reads a credential yet**: there is no table, no lookup, no
override and no page. The key variable is read and checked at boot, and
that is all an instance notices.

## Terms

| Thing | Meaning | Code |
|---|---|---|
| kind | the blueprint of a credential: its fields, which are secret | `Wsjrdp::Credentials::Kind`, `config/wsjrdp_credential_kinds.yml` |
| account | one credential of a kind, named by its account key (`mail_account` / `finanzen`) | -- (comes with the table) |
| version | one set of an account's values | -- (comes with the table) |
| key | 32 random bytes a stage seals its credentials with; known by its fingerprint | `Wsjrdp::Credentials::Keys` |
| sealed text | the fields of one version, encrypted and authenticated | `Wsjrdp::Credentials::Sealer` |
| credential | what a consumer gets: the values of one version | `Wsjrdp::Credentials::Credential` |

## Names

- A **stage** is `[a-z0-9]+`, as for the HMAC keys of the API keys
  (`production`, `staging`, `development`, `test`).
- A **kind**, an **account key** and a **field name** are lower-case snake,
  `[a-z][a-z0-9]*(_[a-z0-9]+)*`: no capital, no hyphen, no double
  underscore, no leading digit -- and at most 48 characters
  (`Wsjrdp::Credentials.name?`, `NAME_LENGTH`). The registry, the sealer's
  purpose and the value object all check this one rule. A message repeats
  any valid name and shows anything else as `(not a name)`, since it may be
  a value put in the wrong place (64 hex digits never fit). The one
  exception are the registry's errors: they name the place with the name
  as written in the file (`kinds.Kx: ...`), which is committed and holds
  no secret.

The stage of an instance is the one of the API keys: `RAILS_STAGE` (default
`production`) under `RAILS_ENV=production`, else the Rails environment
(`Wsjrdp2027::ServiceTokenHmacKeys.stage`).

## Keys: `HITOBITO_CREDENTIAL_KEYS`

A comma-separated list of `<stage>:<secret>` entries. The secret is
**exactly** 32 random bytes as 64 hex digits; its bytes are the AES-256 key
as they are, nothing is derived from them:

```bash
openssl rand -hex 32
```

```
HITOBITO_CREDENTIAL_KEYS=production:<64 hex>,production:<64 hex>
```

It is a variable of its own, so that the credential store and the API keys
(`HITOBITO_SERVICE_TOKEN_HMAC_KEYS`, see [service_tokens.md](service_tokens.md))
never share a key.

- Only entries of the instance's stage are used. The first is **active**:
  new credentials are sealed with it. All of them are **accepted**: a
  credential sealed with any of them can be opened.
- An entry of another stage is ignored with a warning in the log.
- A **problem** -- a malformed entry, an entry (or a label) that is not
  valid UTF-8 text, a secret given twice (in any stage), a `production`
  entry outside production, a committed, public key in any stage but
  `test` (below) -- stops every stage but production from starting
  (`Wsjrdp::Credentials::Keys::ConfigurationError`). Production logs it,
  ignores the entry and starts.
- **Without the variable** an instance has no key. That is valid: the log
  says so in one warning, and sealing raises
  `Wsjrdp::Credentials::NoKeyError`. Nothing else changes.
- **No stage has a committed key**, development included (unlike the HMAC
  keys): a stored credential opens a remote service, so a development key
  must not be in the source. The one exception is the Rails environment
  `test`, which falls back to `credentials.keys_default` in the wagon's
  `config/settings/test.yml`. That key, and the golden-vector spec's key
  (`CredentialsSpec::GOLDEN_VECTOR_KEY` in
  `spec/domain/wsjrdp/credentials/standalone.rb`), are made up and public: only the stage `test` accepts them. The
  code knows them by fingerprint (`Keys::PUBLIC_FINGERPRINTS`), without
  reading any file, so an image without the settings file still refuses
  them; a spec keeps the list in step with both keys.
- Messages and logs name entries by their number and keys by their
  fingerprint, never a secret. A stage is repeated only when it is at most
  32 characters long, since 64 hex digits are a valid stage and may be a
  secret typed into the wrong place; a longer one is "another stage".
  `inspect`, `to_s` and `as_json` of the keys show fingerprints only;
  Marshal and YAML refuse them.

### The fingerprint

The fingerprint of a key is the Base64 of the SHA-256 of the secret as
written, lower-cased (44 characters) -- the same function as for the HMAC
keys. It names the key without giving it away. To check one in a shell:

```bash
printf %s "$SECRET" | tr 'A-F' 'a-f' | openssl dgst -sha256 -binary | base64
```

The log names the fingerprints of the active and the accepted keys at boot.

### Losing a key

A key cannot be recovered from anything the app stores. Losing it means
entering every credential of that stage again; the providers stay the
source of truth, so nothing is lost for good. Keep the key in the same safe
place as `HITOBITO_SERVICE_TOKEN_HMAC_KEYS`, and not in the database backup.
Until there is a way to re-seal credentials with a new key, an old key stays
in the list (after the active one) for as long as credentials sealed with it
are needed.

## `HITOBITO_CREDENTIAL_LABEL`

Optional free text naming this instance's key, e.g. `laptop-a`. It is read
at boot like the keys, stripped, and empty counts as not set
(`Wsjrdp::Credentials::Keys#label`). It is named in the boot log line.

## Sealing

`Wsjrdp::Credentials::Sealer` holds the whole cryptography, two calls into
Rails' `ActiveSupport::MessageEncryptor` -- the class Rails uses for its own
encrypted cookies and credential files:

```ruby
encryptor = ActiveSupport::MessageEncryptor.new(key_bytes, cipher: "aes-256-gcm", serializer: JSON)
text   = encryptor.encrypt_and_sign(fields, purpose: "credential/#{stage}/#{kind}/#{account_key}")
fields = encryptor.decrypt_and_verify(text, purpose: "credential/#{stage}/#{kind}/#{account_key}")
```

```ruby
text   = Wsjrdp::Credentials::Sealer.seal(fields, key: keys.active!, stage:, kind:, account_key:)
fields = Wsjrdp::Credentials::Sealer.unseal(text, key:, stage:, kind:, account_key:)
```

- `cipher:` and `serializer:` are always passed: outside the app's
  configuration the defaults would be CBC and Marshal.
- The **purpose** lies inside the sealed text and is authenticated with it:
  a text opens only for the stage, kind and account it was sealed for. Each
  part is checked against its grammar first, so none can contain a `/`.
- The fields are a plain flat hash of string names to strings, integers,
  `true`, `false` or `nil`; anything else is refused, and so is the field
  name `json_class` (below). Sealing and opening share this one rule
  (`Sealer.fields_problem`). A caller hands `seal` the values of
  `Kind#cast`, not request parameters: a Hash subclass such as
  `ActiveSupport::HashWithIndifferentAccess` is refused.
- **Opening never raises for the text.** A wrong key, a changed text,
  another purpose, a missing key or something that is no sealed text at all
  give `nil`: "cannot be opened here". (`MessageEncryptor` itself raises
  `InvalidMessage` for a wrong key or a changed text and returns `nil` for
  another purpose; the sealer turns both into `nil`.) A text that opens to
  anything sealing would refuse -- sealed by other code with the same key
  -- is `nil` as well, so a wrongly shaped result never reaches a
  consumer.
- The stored form is called **`rails-me-v1`** (`Sealer::SCHEME`):
  `Base64(ciphertext)--Base64(nonce)--Base64(tag)`, AES-256-GCM with a
  random 12-byte nonce and a 16-byte tag. Rails 7.1 writes the inner
  envelope in one of two spellings and reads both; the app writes the newer
  one (`load_defaults 7.1`).
- Neither a sealed text nor a field ever reaches a log or a message. A
  refusal repeats a field name only when it is a valid name (at most 48
  characters of the grammar), else it says `(not a name)`.

### Why `json_class` is reserved

`serializer: JSON` makes Rails read a sealed text with `JSON.load`, which in
the bundled json gem (2.6) runs with `create_additions: true`: a hash with
the key `json_class` (`JSON.create_id`) is taken for an object to build, and
the stored value names the class that is looked up. A field of that name can
be sealed, but what opening the text gives then depends on the value: for
most values the text no longer opens at all, for a few (`Object`, `Time`,
`Range` in a probe) it still did. Either way a stored value would decide
what the reader does, so the sealer refuses the name and the registry
reserves it. Opening checks the shape of the result afterwards, but it
cannot stop `JSON.load` from building an object while it parses; only
someone with the key can seal such a text, and the reserved name keeps our
own code from doing it. `serializer: JSON` stays: it is the form the design fixes, and
the golden-vector spec holds it.

### The golden-vector spec

`spec/domain/wsjrdp/credentials/golden_vector_spec.rb` holds two texts
sealed once with a made-up key (`CredentialsSpec::GOLDEN_VECTOR_KEY` in
`spec/domain/wsjrdp/credentials/standalone.rb`), one in each envelope spelling, that must keep
opening to known fields. **It is never repaired by making new texts.** If it
fails after a Rails upgrade, credentials sealed before the upgrade can no
longer be opened: stop the upgrade and find out what changed in
`MessageEncryptor`.

## Kinds: `config/wsjrdp_credential_kinds.yml`

The registry of kinds, committed; it holds no secret. A further service is a
further kind in this file.

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

A field has a `type` and may be `required`, be `secret` and have a
`default`; an `enum` lists its `values`. `secret: true` decides how a field
is shown and how it is read (below); every field is sealed, secret or not.

| Type | Becomes | Accepted |
|---|---|---|
| `string` | String | a String, as given |
| `email` | String | a String of the form of an address |
| `integer` | Integer | an Integer, or decimal digits with an optional sign (`"587"`) |
| `boolean` | `true` / `false` | `true`, `false`, `"true"`, `"false"`, `"1"`, `"0"` |
| `enum` | String | one of the field's `values` |
| `url` | String | an absolute `http` or `https` URL with a host and without user info |

Nothing is stripped: `" 587"` is no integer.

**The file is read strictly** (`Wsjrdp::Credentials::Kinds`). Each of these
raises `Wsjrdp::Credentials::Kinds::RegistryError`, which names the place
(`config/wsjrdp_credential_kinds.yml: kinds.moss_api.fields.scope.default:
...`): a key it does not know on any level; a kind or field name outside the
grammar or longer than 48 characters; a type not in the table; a field
called `name`, `created_at`, `valid_from` or `expires_at` (reserved for a
version's name and dates) or `json_class` (see "Why `json_class` is
reserved"); a default on a secret field (the file is committed); a `values`
on a field that is no enum, an enum without values or with a value twice; a
default that is no value of its field; a `title_field` that is no field of
the kind or a secret one; a `remind_days_before` that is not a list of
positive integers; a file that is no YAML or holds a date or an alias. The
file is committed, so a broken one is a bug in every stage, production
included.

### Casting values

`kind.cast(values, stage:)` turns a set of values -- strings from a form or
a variable, or typed from YAML -- into the values of a version. The result
has `values`, `errors`, `warnings` and `valid?`.

- A field the kind does not have is an error (`unknown`).
- `nil` and `""` count as not set. A field that is not set gets its
  default; a required field that is still not set is an error (`required`).
- A value that does not fit its type is an error (`not_a_string`,
  `not_an_email`, `not_an_integer`, `not_a_boolean`, `not_in_values`,
  `not_a_url`); a string that is not valid UTF-8 is `not_valid_text` for
  every type. Values that are not a hash (or nil) raise `ArgumentError`.
- A `url` that is not `https` is a **warning** (`not_https`) when the stage
  is `production`, and saved all the same; in every other stage nothing is
  said.
- Errors and warnings name the field and a code, never a value. An
  unknown field is named only when it is a valid name, else
  `(not a name)`: it may be a value put in the wrong place.
- The result (`Kind::Result`) hands its values out through `values` only.
  `inspect`, `to_s`, `pp`, `as_json` and `to_json` show field names and
  codes; Marshal and YAML refuse.

## The value object: `Wsjrdp::Credentials::Credential`

What a consumer will get: the values of one version, with the kind, the
account key, the stage and the fingerprint of the key it was opened with.

```ruby
credential[:smtp_host]             # a public field
credential.secret(:smtp_password)  # a secret field
```

- `[]` refuses a secret field (`Credential::WrongAccess`, pointing to
  `secret`), and `secret` refuses a public one, so a secret is only ever
  read on purpose. An unknown field is `Credential::UnknownField`. A field
  of the kind that is not set is `nil`.
- No value ever shows: `inspect`, `to_s`, `pp`, `as_json` and `to_json` give
  the kind, the account key, the stage, the names of the fields that are set
  and the key's fingerprint; Marshal and YAML refuse.

## Specs

The specs of `spec/domain/wsjrdp/credentials/` are standalone: they do not
boot Rails and cannot touch a database. From the wagon directory:

```bash
bundle exec rspec spec/domain/wsjrdp/credentials
```
