# Deregistration data on `people`

Where the wagon and the `wsjrdp_scripts` repository record that a person
withdraws from the contingent (Abmeldung) or that the contingent ends the
contract (Kündigung), and which code reads and writes each piece.

The data lives in three places of the `people` row: the `status` column,
the `sepa_status` column, and keys of the `additional_info` jsonb column.
The primary group and the person's notes carry side effects of a
deregistration but no deregistration data of their own.


## `people.status`

Two values of the registration status belong to a deregistration
(`config/settings.yml`):

| Value | Label | Meaning |
| --- | --- | --- |
| `deregistration_noted` | Abmeldung Vermerkt | the person wants to withdraw, something is still open |
| `deregistered` | Abgemeldet | the person no longer takes part |

Both values exclude a person from the usual selections:

- Wagon: the unit page's member queries (`Person::UnitController`), the
  public statistics (`Public::StatisticsController`) and the buddy list of
  the participant wishes (`people/_participant_wish_data`).
- Scripts: `PeopleWhere(exclude_deregistered=…)` adds
  `status NOT IN ('deregistration_noted', 'deregistered')`; it is on by
  default for batch queries and switched off explicitly by every
  deregistration script. Fee computations (`_people.py`) treat a person
  in either status without a payment role as owing nothing.

The Abmeldung page shows the status and does not edit it. It is written
by the person's Status page and by `bestätigung_abmeldung.py`, which sets
`deregistered` (see below).


## `people.sepa_status`

The Abmeldung page does not edit the finance status either. No
deregistration code sets a dedicated value; a deregistered
person is excluded from collections through `status`, not through
`sepa_status`.


## `people.additional_info`

### Flat keys (in release v2.40.0 and read by the scripts)

| Key | Type | Written by | Read by |
| --- | --- | --- | --- |
| `deregistration_issue` | string | Abmeldung page (Ticket Abmeldung); scripts `Person.deregistration_issue` setter | page, both documents, all four scripts (subject line, Bcc to the helpdesk) |
| `deregistration_requested_date` | ISO date | Abmeldung page | page (the T&R bracket is read for this day, today while it is empty), Moss receipt |
| `deregistration_effective_date` | ISO date | Abmeldung page | page, Abmelde-Formular (cancellation date), `bestätigung_abmeldung.py` |
| `deregistration_actual_compensation_cents` | integer | Abmeldung page (Entschädigung, entered in EUR through `deregistration_actual_compensation_eur`) | page, both documents |

`deregistration_issue` is a free text; the page links helpdesk ticket keys
(`HELP-…`, `FIN-…`) in it.

### The `deregistration_record` sub-object (wagon only)

`Wsjrdp2027::DeregistrationRecord`
(`app/domain/wsjrdp_2027/deregistration_record.rb`) holds the newer data
under one key, `additional_info["deregistration_record"]`:

| Sub-key | Type | Default (absent) | Meaning |
| --- | --- | --- | --- |
| `kind` | `withdrawal` \| `termination` \| `cancellation` | `withdrawal` | Abmeldung by the person, Kündigung by the contingent, or Storno der Registrierung (cancelled before a contract came about) |
| `reply_due_date` | ISO date | none | Rückmeldung bis as entered: the day the signed deregistration is to be back by, and so the day up to which the proposed Einbehalt stands |
| `effective_reply_due_date` | ISO date | none | the deadline the made Abmelde-Formular names above its heading and in the offer: `reply_due_date`, or two weeks from the day it was made; fixed by "PDF erzeugen", cleared by "Formular verwerfen" |
| `form_created_date` | ISO date | none | the day "PDF erzeugen" made the Abmelde-Formular; its "Erstellt am" reads it until "Formular verwerfen", which discards the receipt and everything captured with it |
| `receipt_created_date`, `receipt_created_by_id` | ISO date, person id | none | the day and the person "PDF erzeugen" made the Moss refund receipt with, until "Beleg verwerfen" |
| `refund_account_holder`, `refund_iban`, `refund_bic`, `refund_sepa_address` | string | none | the account a refund goes to, as the first made document captured it from `sepa_name`, `sepa_iban`, `sepa_bic`, `sepa_address`; both documents and the creditor section read it |
| `person_role`, `person_role_name`, `person_team_unit` | string | none | role, role name and team/unit as the first made document captured them (`Wsjrdp2027::DeregistrationSnapshot::PERSON_KEYS`) |
| `receipt_snapshot` | hash | none | the receipt's figures as they stood when it was made (`RefundReceipt::FROZEN`: creditor name, fee texts, amount paid, compensation, refund, booking text, remittance information) |
| `form_show_contractual_compensation` | boolean | shown | the Abmelde-Formular states the T&R compensation |
| `refund_receipt_text` | string | none | text above the Moss refund receipt's table |
| `refund_receipt_show_default_explanation` | boolean | shown | the receipt prints its explanation paragraph |
| `form_mailings` | list of hashes | none | the mails the Abmelde-Formular went out with, oldest first (see "The scripts' API" below); they stay when the form is discarded, and the person log does not show them as a change (`DeregistrationRecord::LOGGED_ATTRS`) |

Only values that differ from the default are stored, and the key is gone
once all of them are defaults again. The person's `deregistration_kind`,
`deregistration_reply_due_date`, `deregistration_termination?`,
`deregistration_cancellation?`,
`deregistration_form_show_contractual_compensation(?)`,
`deregistration_refund_receipt_text` and
`deregistration_refund_receipt_show_default_explanation(?)` delegate to
the record. The scripts do not read the sub-object.

### Computed, not stored

`Wsjrdp2027::Person` derives the amounts the page and the documents show:

- `deregistration_contractual_compensation_cents` — the compensation of
  section 7.2 T&R: a share of `total_fee_cents` by the bracket the
  compensation date falls into (up to 31.05.2026 half, up to 31.12.2026
  three quarters, up to 31.03.2027 nine tenths, then all of it). A
  cancelled registration never became a contract, so its T&R compensation
  is zero. `create_deregistration_form.py` no longer computes it: it sends
  the form the app makes.
- `deregistration_refund_cents` and `deregistration_open_cents` — what
  comes back and what is still owed: `amount_paid_cents` against the
  actual compensation, or the T&R compensation while none is entered.

The PDFs and their pictures are built from these values on every request
and are never stored.


## Side effects on other tables

- **Primary group.** `bestätigung_abmeldung.py --group <id>` moves the
  person to another group (typically a waiting list) through
  `Person.move_to_group`, which sets `primary_group_id` and the role
  types. `Person#team_unit_code` in the wagon reads the most recent coded
  group of all roles, ended ones included, so the unit a person left
  stays known.
- **Notes.** `bestätigung_abmeldung.py` adds a note (`add_note`) that
  records the day, whether an e-mail went out, the status change and the
  group move.
- **Person log.** A change on the Abmeldung page reaches the person log
  through PaperTrail; `Wsjrdp2027::PaperTrail::VersionDecorator` renders a
  change of the `deregistration_record` sub-object as one line per changed
  value.


## The scripts

All four live in `wsjrdp_scripts/registration_tools/`, select one person
by id with `exclude_deregistered=False` and send a letter by e-mail. Three
compile their Typst letter themselves; `create_deregistration_form.py`
fetches the Abmelde-Formular and everything its mail needs from the app
(see "The scripts' API") and reports the mail back.

| Script | Letter | Reads | Writes |
| --- | --- | --- | --- |
| `storno_registrierung.py` | Stornierungs-Formular for a registration that is not yet a contract | `amount_paid_cents`, `sepa_iban`, `sepa_name`; `--issue` and `--refund-amount` from the command line | nothing on `people` |
| `bestätigung_storno_registrierung.py` | confirmation of that cancellation | `--issue` from the command line | nothing on `people` |
| `create_deregistration_form.py` | Abmelde-Formular, made and answered by the app | the API below (`deregistration.json`, `form.pdf`); the mail's recipients from the people query | through the API: the form (`create_form.json`) and the report of the mail (`form_sent.json`) |
| `bestätigung_abmeldung.py` | confirmation of the deregistration with the account statement (Kontoauszug) | `deregistration_issue`, `deregistration_effective_date`, the accounting entries | `status = 'deregistered'`, a note, and with `--group` the primary group |

The two Storno scripts take the ticket from `--issue` as a static column
of the mailing; it is not written to `additional_info`. The Storno and
Abmeldung mail texts mention the stored status when it already is
`deregistration_noted` or `deregistered`.


## The Abmeldung page

`/people/:id/deregistration` (`Person::DeregistrationController`, gated on
`:log`) shows a summary head (kind, ticket, dates, Anmeldestatus; fee,
paid, Einbehalt, Rückzahlung or Forderung) and four sections: Abmeldung
erfassen (edited in place through a Turbo Frame), Abmelde-Formular,
Kreditor für Rückzahlung and Beleg für Rückzahlung in Moss. Which
sections stand open is kept in the session
(`session[:deregistration_open_sections]`), not in the database.

Everything the page edits is listed above: the four flat keys and the
`deregistration_record` sub-object. The Abmelde-Formular is offered for a
withdrawal only; a termination or a cancelled registration greys it out
with the reason. The Moss refund receipt words all three kinds.

Below the form the section shows the Bcc the script sends it with ("BCC bei
E-Mail-Versand des Abmelde-Formulars", with the unit it comes from) and one
line per mail in `form_mailings`; a mail that carried a form discarded since
is marked so.

While no compensation (Entschädigung) is entered and the form is not made
yet, the section warns that the form then leaves the refund and the claim to
be filled in by hand and that the script does not send it, and "PDF
erzeugen" asks before it makes the form (the form's `data-dereg-confirm`,
read by the page's javascript).


## The mail's recipients

`Wsjrdp2027::DeregistrationMailRecipients`, for the role the form names
(`DeregistrationSnapshot#role`), by the rules the scripts' mailings follow:

- **To**: the person's e-mail, for CMT and UL also `wsjrdp_email`.
- **Cc**: the additional e-mails marked for mailings, and for a youth
  participant or anybody under 18 the guardians' e-mails (only A where one
  guardian signs alone), minus what To has, sorted.
- **From**: the helpdesk of the role -- `unit-management@` for YP and UL,
  `ist@` for IST and BMT, `info@` otherwise.
- **Bcc of YP and UL**: the Support-CMT addresses
  (`groups.additional_info["support_cmt_mail_addresses"]`) of the person's
  unit. A unit is a group with a `unit_code`; the registration groups and the
  waiting lists are `Group::Unit` too but have none. Source `unit`: the
  primary group is a unit. Source `last_unit`: the group of the most recent
  role in a unit, ended roles included (the order of
  `Person#team_unit_code`). Source `primary_group`: the person was never in a
  unit, so the primary group's addresses.
- **Bcc of every role**: the helpdesk as well where a ticket is entered.


## The scripts' API

`Person::DeregistrationController`, with an API key in `X-Token` (scopes
`people` and `people:log`, an acting person who may `:log` the person; the
scripts' purpose is `deregistration`). A request with a valid API key is not
asked for a CSRF token; what cannot be answered comes back as JSON
`{"error": "…"}` with status 422.

| Request | Answer |
| --- | --- |
| `GET /people/:id/deregistration.json` | the deregistration (`Wsjrdp2027::DeregistrationState`, below) |
| `POST /people/:id/deregistration/create_form.json` | makes the form like "PDF erzeugen" (a made form stays as it is), then the deregistration; 422 where there is no form |
| `GET /people/:id/deregistration/form.pdf` | the made form's PDF, built on the request; 422 before it is made |
| `POST /people/:id/deregistration/form_sent.json` | records a mail the form went out with (API key only), then the deregistration with `form_mailing` and `duplicate`; 201 for a new mail, 200 for a Message-ID recorded already |

The deregistration:

```json
{
  "person_id": 1234, "kind": "withdrawal", "available": true,
  "not_available_reason": null, "issue": "HELP-123",
  "status": "deregistration_noted", "contract_status": "confirmed",
  "role_id_name": "YP 1234 Max Muster", "birthday": "2010-06-01",
  "deregistration_requested_date": "2026-11-10",
  "deregistration_effective_date": "2026-12-31",
  "contract_names": ["Max Muster", "Erika Muster"],
  "amounts": {"base_currency": "EUR", "regular_full_fee": 3400,
              "total_fee_reduction": 0, "total_fee": 3400, "amount_paid": 402.95,
              "deregistration_contractual_compensation": 2550,
              "deregistration_actual_compensation": 800.5,
              "deregistration_refund": 0, "deregistration_open": 397.55},
  "form": {"created_date": "2026-11-15", "reply_due_date": "2026-11-29",
           "file_name": "WSJ27 Abmeldung YP 1234 Max Muster.pdf",
           "refund_iban": "DE02120300000000202051", "refund_account_holder": "Erika Muster",
           "show_contractual_compensation": true},
  "mail": {"from": "unit-management@worldscoutjamboree.de",
           "to": ["max@example.org"], "cc": ["erika@example.org"],
           "bcc": ["…the unit's addresses…", "unit-management@worldscoutjamboree.de"],
           "unit": {"group_id": 19, "name": "A3", "source": "last_unit"}},
  "form_mailings": []
}
```

`amounts` carries the person's amounts under their Rails names without the
unit (`regular_full_fee_cents`, `total_fee_cents`, `amount_paid_cents`,
`deregistration_*_cents`; `total_fee_reduction` is
`active_total_fee_reduction`) in euros: whole euros as an integer, others as
a number to the cent, read from the cents; `null` where there is none (an
actual compensation not entered). One `base_currency` holds for all of them,
the ledger currency of `doc/fin/money_conventions.md` R1. The compensations
are read for the day the deregistration was requested, as on the page.

The script refuses to send a form without an actual compensation.

The report (`form_sent.json`) carries `email_sent_at` (ISO 8601),
`email_to`, `email_cc`, `email_bcc` (lists of addresses), `email_subject`,
`email_message_id`, `script` and `deregistration` -- the answer above the mail
was built from. `Wsjrdp2027::DeregistrationFormSent` writes, in one
transaction:

- a **person note** by the API key's acting person: "Abmelde-Formular am
  15.11.2026 per E-Mail verschickt (HELP-123)";
- a **log entry** (`wsjrdp_note`, category `deregistration_form`, shown as
  "Abmelde-Formular verschickt: an max@…, erika@… · HELP-123"):
  `whodunnit` the API key, `additional_info` `{"script": …}`, and in
  `wsjrdp_data` the `email_*` values, `deregistration_issue`,
  `form_created_date`, `note_id` and the `deregistration` the script sent;
- an element of **`form_mailings`**: the `email_*` values,
  `form_created_date`, `log_version_id` and `note_id`. This save writes no
  PaperTrail version of the person -- the log entry stands for it.
