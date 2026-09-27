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
| `deregistration_effective_date` | ISO date | Abmeldung page | page, Abmelde-Formular (cancellation date), `bestätigung_abmeldung.py`, `create_deregistration_form.py` |
| `deregistration_actual_compensation_cents` | integer | Abmeldung page (Entschädigung, entered in EUR through `deregistration_actual_compensation_eur`) | page, both documents, `create_deregistration_form.py` |

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
  is zero. The same
  brackets are coded in `create_deregistration_form.py`
  (`compute_contractual_compensation_cents`).
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
by id with `exclude_deregistered=False`, compile a Typst letter and send
it by e-mail.

| Script | Letter | Reads | Writes |
| --- | --- | --- | --- |
| `storno_registrierung.py` | Stornierungs-Formular for a registration that is not yet a contract | `amount_paid_cents`, `sepa_iban`, `sepa_name`; `--issue` and `--refund-amount` from the command line | nothing on `people` |
| `bestätigung_storno_registrierung.py` | confirmation of that cancellation | `--issue` from the command line | nothing on `people` |
| `create_deregistration_form.py` | Abmelde-Formular (the wagon's `deregistration_form.typ` is a copy) | `deregistration_issue`, `deregistration_effective_date`, `deregistration_actual_compensation_cents`, `total_fee_cents`, `amount_paid_cents`, `sepa_iban`, `sepa_name` | nothing on `people` (`--issue` overrides the stored ticket for the mail only) |
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
