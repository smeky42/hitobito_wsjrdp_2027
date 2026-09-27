# API keys (service tokens)

## Terms

| Thing | Shown as | Code |
|---|---|---|
| the record | API-Key (the core's name), "API-Key <id>" before its heading | `ServiceToken` |
| the secret a client sends | Token | `ServiceToken#plain_token` (only on the object that made it) |
| what the table stores | Token-Hash; "Token" where the token is stored unhashed | column `token` (the core's) |
| a secret the token hash is made with | Schlüssel; its fingerprint (Schlüssel-Fingerabdruck) | `Wsjrdp2027::ServiceTokenHmacKeys`, columns `stage`, `hmac_secret_key_fingerprint` |

## Who manages API keys

- Only an admin (a role with the `admin` permission, `Group::Root::Admin`)
  manages API keys (`Wsjrdp2027::ServiceTokenAbility`): they are made,
  edited and given a new token in the root group (`Group.root`) only; an
  admin shows and deletes the API keys of every layer. The core lets every
  `layer_full` and `layer_and_below_full` holder manage the API keys of their
  own layer; the wagon replaces those rules with `.none`, so the CMT leaders,
  the finance roles, the unit managers and the IST leaders manage none.
- The "API-Keys" button on a layer's page and the list are shown on
  `:index_service_tokens`, which only an admin holds, on every layer
  (`Wsjrdp2027::GroupAbility`). Nobody else sees them.
- The model refuses a new API key outside the root group and a move out of
  it (`not_root` on `layer`, `Wsjrdp2027::ServiceToken`), for the console
  and scripts too. An API key of another layer works as it is until an admin
  deletes it.
- The core's root user (`Settings.root_email`) may everything, API keys
  included, without being an admin; the admin-only fields (acting person,
  finance scopes) stay closed to it.

## Tokens and token hashes

An API key's token is shown once, in the answer to the request that makes it
("API-Key hinzufügen" or "Token neu erzeugen"). The `token` column of
`service_tokens` holds one of three forms, chosen on the new page:

| Form | Stored value | Works in |
|---|---|---|
| HMAC (default) | `hmac-sha256:<hex>`, with `stage` and `hmac_secret_key_fingerprint` | only in its stage, with an accepted secret |
| SHA-256 | `sha256:<hex>` | every stage, every copy of the database |
| unhashed | the token itself | every stage; anyone who reads the table can use it |

Tokens are 50 characters of `A-Z a-z 0-9 - _` and never hold a `:`. A request
carrying a stored value finds nothing.

## HMAC secrets: `HITOBITO_SERVICE_TOKEN_HMAC_KEYS`

A comma-separated list of `<stage>:<secret>` entries, the stage of `a-z` and
`0-9`. The secret is at least 32 random bytes as hex:

```bash
openssl rand -hex 32
```

```
HITOBITO_SERVICE_TOKEN_HMAC_KEYS=production:<64 hex>,production:<64 hex>
```

- The stage of an instance is `RAILS_STAGE` (default `production`) under
  `RAILS_ENV=production`, else the Rails environment (`development`, `test`).
- Only entries of the instance's stage are used; the others are logged and
  ignored. The first is active: new HMAC tokens use it. All are accepted: a
  token of this stage is looked up with each of them.
- The fingerprint of a secret is the Base64 of the SHA-256 of the secret as
  written (44 characters). It names the secret without giving it away.  A new
  HMAC token stores the fingerprint of the active secret. An adopted token hash
  stores the fingerprint given with it.
- An API key of another stage, or whose fingerprint is not accepted here,
  does not work here.
- Production always starts. Without the variable it has no active secret:
  HMAC tokens cannot be made there, SHA-256 and unhashed ones can. Bad entries
  are logged and ignored, and so are the committed secrets of development
  and test.
- Every other stage refuses to start on a bad entry and on any `production`
  entry.
- Development and test fall back to `service_tokens.hmac_keys_default` in
  the wagon's `config/settings/<environment>.yml`. These values are public on
  purpose: they only mark development and test tokens.
- Logs and error messages name fingerprints, never secrets. The core's
  `filter_parameters` (`:token`, `:secret`, ...) keep request parameters such
  as `token` and `adopted_token` out of the logs.

### Changing a secret

1. Put the new entry first and restart. Old tokens keep working.
2. Make the tokens of the old secret anew ("Token neu erzeugen"); the API
   key's page shows the fingerprint of its secret.
3. Take the old entry out and restart. Remaining tokens of the old secret
   stop working; their page says so.

## Tokens that survive a production dump into development

1. In development, make the API key (HMAC). Copy the token and the token hash
   `hmac-sha256:…` from the answer.
2. In production, make an API key with the same rights and choose
   "Token-Hash einer anderen Umgebung übernehmen" with the stage
   (`development`) and that token hash; both are required. The fingerprint
   of the development secret (on the development API key's page) is
   optional.
3. The next production dump brings the row into development, where the token
   works. Production cannot use it: the row names another stage, and
   adoption refuses the stage `production` and the instance's own stage.

## Making a token anew

"Token neu erzeugen" keeps an HMAC API key an HMAC one. A SHA-256 API key may
get a SHA-256 or an HMAC token, an unhashed one an unhashed, a SHA-256 or an
HMAC token -- an HMAC token only where this stage has a secret. The buttons
read "Token neu erzeugen" for one kind and "Neues Token (…)" per kind
otherwise; each asks first and makes the token at once. An API key of another
stage gets no new token here.

## Acting person

`service_tokens.acting_person_id` (nullable, set to NULL when the person is
deleted) names a person whose rights the API key needs as well
(`Wsjrdp2027::ActingPersonTokenAbility`): an action is allowed when the API
key allows it (`TokenAbility`: kinds, Zugriffsbereich, layer) and the person
may do it (`Ability`, wagon rules included). Actions `TokenAbility` does not
know stay closed.

- `current_user` is the acting person; PaperTrail still records the API key
  as the author (`whodunnit` = its id, `whodunnit_type` = `ServiceToken`).
- JSON:API lists (`index_ability`) follow the acting person's readables.
- Only an admin (a role with the `admin` permission) sets, changes or
  clears it. For an admin the core's form shows it after the description as
  the person autocomplete (`Wsjrdp2027::StandardFormBuilder#labeled_input_fields`);
  anyone else's submitted value is dropped. Its search
  (`Wsjrdp::ServiceTokenActingPeopleController`) finds every person, one
  without roles included, by name or by id; the autocomplete asks from three
  characters on, so person 1 is `001` or `0001`.
- `ApplicationController` and `JsonApiController` both use it.
- The core's person pages ask for the signed-in person's roles and fail on a
  token request; they are no API.

## Scopes

`service_tokens.scopes` (a string array) names what the API key reaches
(`Wsjrdp2027::ServiceTokenScopes`). Every area has one base scope and any
number of extras:

| Area | Base | Extras |
|---|---|---|
| people | `people` | `people:log` |
| groups | `groups` | `groups:log` |
| events | `events` | `events:log` |
| invoices, event_participations, mailing_lists | same name | – |
| finance | `finance:read` | `finance:audit`, `finance:write`, `finance:manage` |

- The bases of the core areas are the core's boolean columns of the same name
  (and the names of the core's OAuth scopes). The columns lead where they
  change (the core's form); where only the scopes change (a script), the
  columns follow them. The migration fills the scopes of existing rows from
  the columns.
- An extra sets its base with it. The extras work only with an acting person
  (`ServiceToken#effective_scopes`): the form disables them without one and
  asks before saving drops checked ones, and the controller drops them.
- `people:log`, `groups:log`, `events:log` give `:log` on that area, on what
  the API key may show there and where its substitute person with its
  Zugriffsbereich may `:log` -- in practice a Zugriffsbereich with
  "Schreibrechte" -- and within the acting person's rights. In this wagon
  `:log` is the gate of the privileged view (`doc/roles.md`, "The :log
  convention").
- Each finance scope gives the substitute person its finance permission
  (`finance:read` `finance_read`, `finance:audit` `finance_audit`,
  `finance:write` `finance`, `finance:manage` `finance_manage`); several may
  be held, as a role holds several. The API key may the actions of every
  permission held (`Wsjrdp2027::TokenAbility::FINANCE_ACTIONS`) on the finance
  models (`Wsjrdp2027::FinanceAccess.ladder_models` from `finance_read`,
  `.person_level_models` from `finance_audit`), on a person's finance and on
  a group's finance pages. The highest permission held caps the substitute
  person and an acting person (`Wsjrdp2027::FinanceCap`; it counts as picked,
  so `finance_manage` applies too).
- `finance:read` works without an acting person; it only reads, through the
  wagon's finance pages (there is no JSON:API for the finance data).
- Only an admin changes the finance scopes.
- The form: the `:log` extras stand indented behind the core's checkboxes of
  their area (`Wsjrdp2027::StandardFormBuilder#boolean_field`), the finance
  scopes at the end of "Rechte" (`service_tokens/_fields_wsjrdp_2027`, the
  core form's extension point). "Rechte" on the API key's page adds ", Log"
  to an area, a line "Finanzen <highest tier>" and a line with the scopes.

## A substitute person without id

Without an acting person the API key acts as the core's substitute person, an
unsaved person with one role. Its abilities work, but whatever stores an
author does not: an accounting entry needs an `author_id` and fails; a
pre-notification, a document or a link to a DATEV booking is stored without
one. This is why the extras -- and with them every finance scope that
writes -- need an acting person.
