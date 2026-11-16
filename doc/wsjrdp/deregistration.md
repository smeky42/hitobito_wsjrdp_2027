# Deregistrations

Where the wagon and the `wsjrdp_scripts` repository record that a person
withdraws from the contingent (Abmeldung), that the contingent ends the
contract (Kündigung) or that a registration is cancelled (Storno), and which
code reads and writes each piece.

A deregistration is a row of `wsjrdp_deregistrations` (`WsjrdpDeregistration`)
with its history in `wsjrdp_deregistration_events`. On the person, the
`status` column says where the registration stands; the primary group and the
person's notes carry side effects. Until migration 20261115000100 the data
lived in keys of `people.additional_info` (see "Before the table").


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


## `wsjrdp_deregistrations`

One row per version of a person's deregistration; `number` counts them per
person (unique), `replaces` points at the row a new version took over from.
At most one row of a person is open (not in a final status). The person's
`deregistration_*` accessors (`Wsjrdp2027::Person`) read and write the
person's current row -- the open one, else the latest
(`WsjrdpDeregistration.current_for`) -- and the person's save saves it
(autosave). A person never deregistered has no row; the first value that is
not a default makes row 1.

| Where | What | Person accessor |
| --- | --- | --- |
| `kind` (default `withdrawal`) | `withdrawal` \| `termination` \| `cancellation` | `deregistration_kind` |
| `issue` | the helpdesk ticket, free text; the page links `HELP-…`/`FIN-…` keys | `deregistration_issue` |
| `requested_date` | the day the withdrawal was declared (Rücktritt erklärt am); the T&R bracket is read for it | `deregistration_requested_date` |
| `effective_date` | the day it takes effect (Abmeldung zum) | `deregistration_effective_date` |
| `reply_due_date` | Rückmeldung bis as entered | `deregistration_reply_due_date` |
| `actual_compensation` + `actual_compensation_currency` | the agreed compensation (Entschädigung), EUR, numeric | `deregistration_actual_compensation_cents` (and `_eur`) |
| `show_contractual_compensation` (default true) | the form states the T&R compensation | `deregistration_form_show_contractual_compensation(?)` |
| `form_snapshot` | what "PDF erzeugen" fixed: `created_date`, `effective_reply_due_date` (the deadline the form names), the refund account (`refund_account_holder`, `refund_iban`, `refund_bic`, `refund_sepa_address`) and `person_role`, `person_role_name`, `person_team_unit` | `deregistration_form_created_date`, `deregistration_effective_reply_due_date`, `deregistration_refund_*`, `deregistration_person_*` |
| `additional_info["refund_receipt"]` | the Moss refund receipt: `created_date`, `created_by_id`, `snapshot` (its figures, `RefundReceipt::FROZEN`), `text`, `show_default_explanation` | `deregistration_receipt_*`, `deregistration_refund_receipt_*` |
| `form_sent_at`, `sent_form_document_id` | when the form first went out, and the form as sent (a document `deregistration` *number* / `form`, `key_ref` the row, origin `api`) | -- |
| `signed_form_document_id`, `signed_form_received_at` | the form that came back signed (not used yet) | -- |
| `status`, `closed_at` | the step reached (below); `closed_at` once final | `deregistration&.status` |

### Steps

`recorded` → `form_created` ("PDF erzeugen"; back to `recorded` by "Formular
verwerfen") → `form_sent` (the first `form_sent.json`) → … →
`confirmation_sent` (`confirmation_sent.json`). `signed_form_received`,
`refund_initiated` and `refund_booked` exist but nothing sets them yet. Final:
`finished`, `canceled`, `superseded`, `deleted`. The step and the person's
`status` are kept apart: the Status page and the scripts set `status` as
before.

### Fixed once sent

From `form_sent` on, what the sent form says stays (`FIXED_ATTRS`: kind,
ticket, the dates, the compensation, the flag, `form_snapshot`, …); a save
that changes one of them fails. The page then shows the row as fixed, offers
no Bearbeiten and no "Formular verwerfen", but "Neue Fassung anlegen"
(`new_version`): a new open row with the next number takes over what was
entered (`CARRIED_ATTRS`), the old one becomes `superseded`. The Moss receipt
stays changeable on a fixed row.

### Events and the person log

Every create and update of a row writes a `WsjrdpDeregistrationEvent`
(`field_changes`, the status move, who did it -- the person or API key
PaperTrail names). A mail a script reports is an event `notify` with action
`form_sent` or `confirmation_sent`, its `additional_info` the mail
(`email_*`, `log_version_id`, `note_id`, `form_created_date`); the person's
`deregistration_form_mailings` reads them. The row is versioned by PaperTrail
with the person as `main`, so the person log shows "Abmeldung Nr. 1
geändert:" and a line per value (`VersionDecorator#deregistration_change`).
The page lists the events under Abmeldung erfassen (Verlauf), newest first,
each with the values it changed below it, muted -- worded by
`Wsjrdp2027::DeregistrationWording.row_change_lines`, which the person log
uses for a row's versions too. A step reached by sending a mail
(`form_sent`, `confirmation_sent`) is told by the mail's line alone -- the status event written right after the mail's event; a step reached otherwise keeps its line; a step
leaves out what it implies (the status, `form_snapshot`, `form_sent_at`); a
change of the kept form alone reads "Abmelde-Formular gespeichert".

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


## Before the table

Until migration 20261115000100 the data lived in `people.additional_info`:
the flat keys `deregistration_issue`, `deregistration_requested_date`,
`deregistration_effective_date`, `deregistration_actual_compensation_cents`
and the sub-object `deregistration_record` (
`kind`, `reply_due_date`, `effective_reply_due_date`, `form_created_date`,
the receipt's and the snapshot's keys, the two flags, `form_mailings`). The
migration made one row (number 1) per person with any of them -- status
`finished` for a person `deregistered`, `form_sent` once a mail went out,
`form_created` once the form was made, `recorded` otherwise -- turned the
mails into events and removed the keys; `down` writes them back from each
person's current row. The person log still shows the older entries' changes
of `additional_info["deregistration_record"]`, worded by
`Wsjrdp2027::DeregistrationWording` like the flash and the row's log.


## Side effects on other tables

- **Primary group.** `bestätigung_abmeldung.py --group <id>` moves the
  person to another group (typically a waiting list) through
  `Person.move_to_group`, which sets `primary_group_id` and the role
  types. `Person#team_unit_code` in the wagon reads the most recent coded
  group of all roles, ended ones included, so the unit a person left
  stays known.
- **Notes.** `bestätigung_abmeldung.py` adds a note (`add_note`) that
  records the day, whether an e-mail went out, the status change and the
  group move; a sent form leaves a note of its own (`form_sent.json`).


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
| `create_deregistration_form.py` | Abmelde-Formular, made and answered by the app | the API below (`deregistration.json`, `form.pdf`) | through the API: status `deregistration_noted` and the form (`prepare_form.json`), the report of the mail (`form_sent.json`) |
| `bestätigung_abmeldung.py` | confirmation of the deregistration with the account statement (Kontoauszug) | ticket and effective date from `deregistration.json`, the accounting entries | `status = 'deregistered'`, a note, with `--group` the primary group; through the API the report of the mail (`confirmation_sent.json`) |

The two Storno scripts take the ticket from `--issue` as a static column
of the mailing; they write no deregistration row yet. The scripts'
`Person.deregistration_issue` is a value in memory only, filled from the API
or the command line -- it never writes `additional_info`. The Storno and
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

The dates are read by `Wsjrdp::DateInput` (doc/wsjrdp/date_input.md): ISO
or German `D.M.YYYY` / `D.M.YY`. A date or an amount the form cannot read
saves nothing and names the error on its field; the stored value stays. A
date field keeps what was typed, the amount field shows the stored amount.

Below the form, in the page's field list, the section shows the mail the
script sends it with -- From, To, Cc, Bcc (with the unit it comes from, muted)
and Reply-To where there is one, the addresses as mailto links -- and under
Versand one line "Verschickt am …" per mail in `form_mailings`; a mail that
carried a form discarded since is marked so. Under Dokumente it lists the
current row's documents around the form
(`DeregistrationFormDocument.documents_of`): the kept PDF the row points at
(`sent_form_document`) and the mails as they went out (`form_mail` *n*). A document whose entry the login user may
see (`can?(:show, document)`) is linked to its page; a mail is listed for
everybody who sees the page, with "EML herunterladen" (`mail_file`).

"PDF erzeugen" keeps the form as a document of the row -- the PDF and its
first page --, with the fingerprint of what it was drawn from
(`DeregistrationForm#inputs_digest`, `additional_info["form_inputs_sha256"]`).
The form prints live data too (the amount paid, names, the guardians), so
before it went out the kept PDF is shown only while the fingerprint matches;
a stale one gives way to the form drawn from the data, and the next
`prepare_form` keeps a new version. A save on the page keeps nothing.
"Formular verwerfen" lets go of the kept PDF of a form that did not go out,
so the page no longer lists it, and hides it (deleted, the file stays; while
the documents are busy it stays current until the next version replaces it).
The discard takes the lock of the row's reports and reads the row anew, so it
never discards a form a report is recording right then. The form's PDF
and picture are answered with `Cache-Control: private, no-store`: whether the
kept or a drawn form comes back changes with the data.

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
- **Reply-To**: none (`reply_to` is an empty list), so replies reach that
  helpdesk; the script sets what the app names.
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
asked for a CSRF token.

`GET deregistration.json` answers the deregistration itself (below). Every
other JSON answer -- the POSTs, and an error of `form.pdf` -- has one shape:

```json
{"deregistration": { …what deregistration.json answers… },
 "errors":   [{"code": "no_birthday", "message": "Das Geburtsdatum fehlt; …"}],
 "warnings": [{"code": "no_issue", "message": "Es ist kein Helpdesk-Ticket eingetragen."}],
 …what the action adds (form_mailing, duplicate)…}
```

| Status | When |
| --- | --- |
| 200 | done; a report of a Message-ID recorded already |
| 201 | a new mail recorded (`form_sent`, `confirmation_sent`) |
| 400 | the request body is no JSON (`bad_json`) |
| 403 | a report without an API key |
| 409 | the deregistration is not in the state the request needs: the form not made yet (`form_not_created`), a report for another version (`other_deregistration`), a fixed form (`fixed`) |
| 503 | the documents are being written by somebody else, or another report of the same deregistration is being recorded (`busy`): try again |
| 422 | the form would not be complete or there is none (the codes of the check below), or a report that is wanting (`invalid_report`, `no_acting_person`) |

| Request | Answer |
| --- | --- |
| `GET /people/:id/deregistration.json` | the deregistration (`Wsjrdp2027::DeregistrationState`, below), with `form_check` |
| `POST /people/:id/deregistration/create_form.json` | like `prepare_form.json`, without the status |
| `POST /people/:id/deregistration/prepare_form.json` | what `create_deregistration_form.py` sends before the mail: the person's status moves on to `deregistration_noted` (unless it is that or `deregistered`; a save of the person, so PaperTrail writes it with the API key) and the form is made where it is not yet, and -- before the answer -- kept as a document: the PDF and its first page (`Wsjrdp2027::DeregistrationFormDocument`). A form kept already ("PDF erzeugen", an earlier prepare) is taken as it is while it still says what the data say (its fingerprint); a new version is kept only where there is none, it is stale, deleted, its file missing, or an upload replaced it in its slot. Nothing is written while the form would not be complete: 422 with every error and warning |
| `GET /people/:id/deregistration/form.pdf` (`.png`: the first page) | the kept PDF of the made form (for `.png` its kept first page), for the page and an API key alike, so the script attaches exactly that PDF -- before the form went out only while it is fresh; drawn from the data otherwise; 422 where there is no form, 409 before it is made |
| `POST /people/:id/deregistration/form_sent.json` | records a mail the form went out with (API key only), with `form_mailing` and `duplicate`; 409 `form_document_missing` while there is no kept form (nothing is kept here), 409 `other_form_document` where the report's `deregistration.form.document_id` is not the row's; a row whose form went out before forms were kept (migrated: its `create` event has action `migrated`, no document) records its further mails without the check; reports of one row are recorded one at a time (`Wsjrdp::SessionLock`, an advisory lock of the session that "Formular verwerfen" takes too; 503 `busy` after 8 s); a Message-ID recorded already is answered as a duplicate before either check; an EML a failed report left in its slot is replaced on the next report |
| `GET /people/:id/deregistration/mail_file?document_id=` | a kept mail of the person's deregistrations (`form_mail` / `confirmation_mail`) as an EML to save, for whoever may see the page, whatever the document's own lists say; 404 for any other document |
| `POST /people/:id/deregistration/confirmation_sent.json` | records the confirmation `bestätigung_abmeldung.py` sent (API key only, `Wsjrdp2027::DeregistrationConfirmationSent`): a log entry of category `deregistration_confirmation`, an event `confirmation_sent`, the row moves on to `confirmation_sent`; no person note (the script writes one); answered like `form_sent.json` with `confirmation_mailing` |

A report names the row it was built from (`deregistration.deregistration_id`);
one for another version is refused with 409.

### The form check

`Wsjrdp2027::DeregistrationFormCheck`, in `form_check` of the deregistration
and in the answer of `prepare_form.json`. Texts: `people.deregistration_check`.

| Code | Kind | When |
| --- | --- | --- |
| `unavailable_termination`, `unavailable_cancellation`, `unavailable_no_date` | error | no form for the kind, or no day to name (`DeregistrationForm#unavailable_reasons`) |
| `no_compensation` | error | no agreed compensation: the form would leave refund, claim and account blank |
| `no_birthday` | error | the form would leave the birthday blank |
| `no_refund_account` | error | a refund without IBAN or account holder |
| `no_issue` | warning | no helpdesk ticket: the mail lands in no ticket |
| `deadline_over` | warning | the made form's deadline is over |
| `sent_before` | warning | the form went out before (one per mail) |
| `no_guardian` | warning | a youth participant or minor without a guardian who signs |

`create_deregistration_form.py` lists all of them at once (its dry run adds
`dry_run_no_form`), ends on an error and asks once for the warnings; a refusal
of `prepare_form.json` (`HitobitoApiError`) is listed the same way.

The deregistration:

```json
{
  "person_id": 1234, "deregistration_id": 77, "number": 1,
  "deregistration_status": "form_created", "kind": "withdrawal", "available": true,
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
  "mail": {"subject": "WSJ27 Abmeldung YP 1234 Max Muster HELP-123",
           "confirmation_subject": "WSJ27 Bestätigung der Abmeldung YP 1234 Max Muster HELP-123",
           "from": "unit-management@worldscoutjamboree.de",
           "to": ["max@example.org"], "cc": ["erika@example.org"], "reply_to": [],
           "bcc": ["…the unit's addresses…", "unit-management@worldscoutjamboree.de"],
           "unit": {"group_id": 19, "name": "A3", "source": "last_unit"}},
  "form_mailings": [], "confirmation_mailings": []
}
```

`status` is the person's registration status, `deregistration_status` the
step of the row.

`amounts` carries the person's amounts under their Rails names without the
unit (`regular_full_fee_cents`, `total_fee_cents`, `amount_paid_cents`,
`deregistration_*_cents`; `total_fee_reduction` is
`active_total_fee_reduction`) in euros: whole euros as an integer, others as
a number to the cent, read from the cents; `null` where there is none (an
actual compensation not entered). One `base_currency` holds for all of them,
the ledger currency of `doc/fin/money_conventions.md` R1. The compensations
are read for the day the deregistration was requested, as on the page.


`mail.subject` and `mail.confirmation_subject` are the subjects of the two
mails -- the role, id and name the form names and the ticket behind them; the
scripts take them as they are.

The report (`form_sent.json`) carries `email_sent_at` (ISO 8601),
`email_to`, `email_cc`, `email_bcc` (lists of addresses), `email_subject`,
`email_message_id`, `script`, `deregistration` -- the answer above the mail
was built from -- and `email_eml_base64`, the mail as it went out. The EML's
Message-ID must be `email_message_id` (422 otherwise); it is kept as document
`deregistration` *number* / `form_mail` *n* (`confirmation_mail` *n* for a
confirmation), the n-th mail of its kind, `key_ref` the row, and the event and
the log entry name it (`eml_document_id`). `Wsjrdp2027::DeregistrationFormSent` writes, in one
transaction:

- a **person note** by the API key's acting person: "Abmelde-Formular am
  15.11.2026 per E-Mail verschickt (HELP-123)";
- a **log entry** (`wsjrdp_note`, category `deregistration_form`, shown as
  "Abmelde-Formular verschickt: an max@…, erika@… · HELP-123"):
  `whodunnit` the API key, `additional_info` `{"script": …}`, and in
  `wsjrdp_data` the `email_*` values, `deregistration_issue`,
  `form_created_date`, `note_id` and the `deregistration` the script sent;
- an **event** of the row (`notify`, action `form_sent`) whose
  `additional_info` holds the `email_*` values, `form_created_date`,
  `log_version_id` and `note_id` -- one element of `form_mailings`;
- with the first mail: the row's `form_sent_at` and its step `form_sent`.
  The form as sent is the PDF `prepare_form` kept -- document
  `deregistration` *number* / `form` (`key_ref` the row, origin `api`) with
  its first page as a derivation (`thumbnail`, 288 px wide); a report while
  there is none is refused (`form_document_missing`), nothing is kept here. These saves
  write no PaperTrail version -- the log entry stands for them. From then on
  the row is fixed.
