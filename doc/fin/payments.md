# Zahlungsverkehr

The Finanzen area **Zahlungsverkehr** (`/fin/payments`, right after Konten &
Wallets in the left navigation) shows the payment orders the contingent sends
to its bank, the debits of the direct debit orders and their returns. It only
reads; the orders are made by the scripts (`wsjrdp_scripts`).

| Tab | Path | Controller | Rows |
|---|---|---|---|
| Übersicht | `/fin/payments` | `Fin::PaymentsController` | key figures (`Fin::PaymentsOverview`) |
| Aufträge | `/fin/payments/orders` | `Fin::PaymentOrdersController` | `wsjrdp_payment_initiations` |
| Sammler | `/fin/direct_debit_payment_infos` | `Fin::DirectDebitPaymentInfosController` | `wsjrdp_direct_debit_payment_infos` |
| Einzüge | `/fin/payments/debits` | `Fin::DirectDebitsController` | `wsjrdp_direct_debit_pre_notifications` |
| Rückläufer | `/fin/payments/returns` | `Fin::PaymentReturnsController` | `wsjrdp_camt_transactions` with a `return_kind` |

Every list is an expandable table with the CNF filter; its rows are SQL
relations (`Fin::PaymentQueries`), so sorting, filtering and the footer sums
run in the database.

Every detail -- an order's, a Sammler's, a debit's, a return's -- is a finance
detail partial (`fin_detail`, [`detail_partials.md`](detail_partials.md)):
one `_detail` per controller, shown on the record's own page and inside its
list row's detail; the formatters live in `Fin::PaymentDetailsHelper`, the
labels in `activerecord.attributes.<model>`. An order's and a Sammler's own
page add the debits section below.

A debit's detail is read-only and puts the result first: person, amount
(with the announced one beside it), collection date and sequence type,
status and return. Then the order, Sammler, collection entry (Beitragsbuchung)
and the debit's other page ("Auch unter", see below), purpose and
reference, skip and comment, the mails, the mandate with the creditor id,
debtor and creditor, and the payment role with the timestamps at the end.
Its heading says **Vorabankündigung Einzug #id** while the debit is only
announced (`pre_notified`), **Einzug #id** once it is in a SEPA file or
skipped (`Fin::PaymentsHelper#payment_debit_label`).

A debit has two pages with the same detail (`Fin::DebitPages`), each with its
edit page:

- in the area, `/fin/payments/debits/:id` and `…/edit`, under the
  Zahlungsverkehr sheet, back to the Einzüge tab;
- under its person, `/fin/pn/:id` and `…/edit`, under the person's sheet,
  back to the person's Finanzen tab. The person's Beitrag tab and an
  accounting entry's page link here. A debit without a person has no page
  here: `/fin/pn` sends it on to the area's.

Each links the other ("Auch unter"). Reading takes `:log` on the
pre-notification (the audit tier up), editing `:update` (the finance tier
and up); the reading page shows "Bearbeiten" to them only. The edit page
changes (`Fin::DebitEditing`): while the debit is only announced (`pre_notified`) the
skip flag, amount, purpose, comment, reference, debtor and mandate (reference
and date); once it is in a SEPA file or skipped, the comment alone. The
manage tier (`:admin_finance` on the pre-notification -- an elevated tier, so
only in a session that picked it, `?max_finance_permission=finance_manage`)
also sets the status, in any status, from
`Settings.pre_notification_payment_status`. The amount takes the kit's money
input, the mandate date hitobito's date field.

The bank account form on a person's fee page (`Person::BankAccountController`,
`:update_finance` on the person) carries the new account and mandate into the
person's announced debits the viewer may `:update`, as checked; those they may
not are named in the form and left alone. A new IBAN under the stored mandate
reference gets a hint, not an error: a new account usually comes with a new
mandate.

Another page may link either page with `return_url`, a path of this
application (`direct_debit_path(id, return_url: request.fullpath)`). The
debit's page then shows a "Zurück" link there (without one, the tabs lead
back), "Bearbeiten", the form and
"Abbrechen" carry it along, and a save returns to it ("Speichern und weiter
bearbeiten" stays on the edit page). Anything but a local path -- another
host, `//host`, a `javascript:` URL -- is ignored.

## Orders and their kind

An order (`WsjrdpPaymentInitiation`) is one SEPA file (PAIN), sent from one
of the contingent's accounts: the account is the `WsjrdpFinAccount` whose IBAN
is the order's `initiating_party_iban`. Its kind (`#kind`, `.kind_sql`, the
same rule in Ruby and SQL):

- **direct debit**: `sepa_schema` is `pain.008.*`, or Sammler
  (`wsjrdp_direct_debit_payment_infos`) belong to it;
- **credit transfer**: `sepa_schema` is `pain.001.*`;
- **conflict**: both -- shown with a warning;
- **unknown**: neither -- shown with a warning.

A direct debit order has **Sammler** (ISO `PmtInf`, the payment information:
one per collection date and sequence type -- `wsjrdp_direct_debit_payment_infos`)
and debits (pre-notifications, one per person). The order itself is the
**Auftrag**. In the list an order of several Sammler stays one row: its count,
amount and returns, and under them -- small, one line per Sammler -- each
Sammler's date, sequence type (when they differ), count, amount, returns and
bank credit; the order's own values (account, status, message id, schema,
skipped debits) stay single. The order's
page (`/fin/payments/orders/:id`) shows its head, its Sammler and -- for a
direct debit -- its debits; the row of the list opens into the head and the
Sammler only.

The Sammler have a list and pages of their own
(`/fin/direct_debit_payment_infos`, `/fin/direct_debit_payment_infos/:id`):
a Sammler's page shows its head, its creditor, the returns of its debits and
its debits. A debit belongs to the Sammler it names
(`direct_debit_payment_info_id`, set by `sepa_direct_debit.py` of
wsjrdp_scripts) when it was collected (status `xml_generated`); a skipped or
only announced debit is in no Sammler (`Fin::PaymentQueries.payment_info_debits`).
A Sammler's page thus shows exactly the count and amount of its PmtInf. The debits section of
an order's and a Sammler's page is one (`Fin::DirectDebitsSection`).

## Returns

A return is a bank transaction (`wsjrdp_camt_transactions`) that brings a
payment back -- the bank statement is the record. Its generated column
`return_kind` says what came back, from the bank transaction codes:

| `return_kind` | Codes (ISO family + sub-family, GVC) | What came back |
|---|---|---|
| `direct_debit` | `IDDT` + `UPDD`/`RCDD`/`PRDD` (GVC 108, 109, 193) | one of our direct debits: return, refund, reject or reversal |
| `credit_transfer` | `ICDT`/`IRCT` + `RRTN`/`XRTN` (GVC 159, 160) | a credit transfer we sent |
| `received_credit_transfer` | `RCDT`/`RRCT` + `RRTN`/`XRTN` (GVC 159, 160, 201) | a credit transfer we received, sent back |
| `received_direct_debit` | `RDDT` + `UPDD`/`RCDD`/`PRDD` (GVC 181, 184) | a direct debit we were charged, credited back |
| `other` | other return sub-families (`UPCT`, `UPCQ`, ...), or a return reason without a usable code | anything else returned |

A transaction with a return reason but no usable code counts as a
`direct_debit` return when it names a mandate, else as `other`. The codes are
the ISO 20022 Bank Transaction Code (`bank_transaction_code`, split into
`bank_transaction_domain`, `bank_transaction_family`,
`bank_transaction_sub_family`) and the code of the German banks
(`bank_transaction_code_dk`, its GVC in `gvc`); their meaning and the mapping
GVC to ISO code are those of DFÜ-Abkommen Anlage 3 and its Anhang 1.
A bank transaction's page (`/fin/tx/:id`) and a return's page show both
codes with the meaning of their parts -- German labels, the English names as
tooltip -- from the curated list `Fin::BankTransactionCodes`; the Primanota
(a batch number of the bank) is left out, a code not listed shows as it is.

The Rückläufer tab has two sections: "Rücklastschriften" lists the
`direct_debit` returns -- everything below is about them -- and "Weitere
Rückläufer" every other kind. A return's page (`/fin/payments/returns/:id`)
serves both; for another kind it shows what came back, the other party and
the codes. Its edit page (`/fin/payments/returns/:id/edit`, for whoever may
update the bank transaction) changes the processing status and the comment
(`Fin::ReturnEditing`), the fields of the page a bank transaction lets edit;
in a row of the Rücklastschriften list the same viewer edits them in place
(the kit's inline toggle, saved within the row).

Another return names the bank transaction it brought back -- its original --
in `reverses_id`, the original names it in `reversed_by_id`
(`Fin::ReturnOriginals`). The return's page shows the original. Its edit page
offers the candidates as a field of the edit form: the opposite amount
exactly (no partial returns), within 90 days before the return, of the side
and ISO families the return's kind says, no return themselves and not linked
to another return. They are ordered by a score -- 50 for the amount, plus the
end-to-end id (50), the IBAN of the other party or the mandate (30), its name
(10) and closeness in time (up to 10) -- that does not show; a candidate's
"Merkmale" tooltip compares every feature, matched or not. A radio button
chooses one (none is chosen unless linked), "keine Verknüpfung" unlinks, and a
field beside takes the id of a bank transaction that is no proposal (it must
still be a candidate); "Speichern" saves the choice. The original's bank
transaction page shows "Zurückgekommen" with a link to the return. The
accounting entry
booked for it on the person's fee account (`accounting_entries` with
`camt_transaction_id`) is derived from it; the Rückläufer list shows it in its
Beitragsbuchung column and flags a return without one (preset "ohne
Beitragsbuchung"). Deleted and replaced bank transactions are left out.

A return finds its debit (`Fin::PaymentQueries.return_notice_join`):

1. by the link it carries -- `wsjrdp_camt_transactions.direct_debit_pre_notification_id`,
   set by the CAMT importer (wsjrdp_scripts) or by hand;
2. unlinked, by its end-to-end id -- the debit with the same `endtoend_id`;
3. else by its mandate reference: the newest collected debit of that mandate
   whose collection date lies at most `MANDATE_DAYS` (5) before the return's
   value date. This covers an order the bank re-referenced when its SEPA file
   was imported through banking software (its returns carry end-to-end ids of
   the bank's own).

The list marks a debit found the second or third way "nicht verknüpft" (preset
"nicht verknüpft"), so gaps of the importer show.

Through the debit it reaches its Sammler (the debit's
`direct_debit_payment_info_id`, else order + sequence type + collection date)
and its order. A return that finds no debit keeps the order it names itself
(`payment_initiation_id`); without one it is **not assignable** and marked in
the Rückläufer list (preset "nicht zuordenbar"). The figures of every list --
the Retouren of orders and Sammler, the Rücklastschrift of a debit -- come from
the same mapping (`RETURN_DEBITS_SQL`); the sums are negative, as the bank's
amounts are.

## Credits

The bank credits each Sammler as one collective credit, an entry carrying the
Sammler's `PmtInfId`; the importer links it to that Sammler and its order
(`direct_debit_payment_info_id`, `payment_initiation_id`). Links rest on our own
references (end-to-end id, `PmtInfId`), never on bank transaction codes. The
Bankbuchung column of the orders and the Sammler shows its value date, linked
to the bank transaction, and warns where the credits do not add up to the
control sum, or where a credit is missing although the SEPA file went to the
bank (status `xml_generated`; preset "ohne Bankbuchung" on the Sammler).
Statements with transaction details (camt.053/054) would link each debit's
single collection through the same `direct_debit_pre_notification_id` as its
return; the role is the transaction's own (`return_reason`, credit or debit),
see `WsjrdpDirectDebitPreNotification#return_camt_transactions` and
`#collection_camt_transactions`.

The processing status of a return (Bearbeitung, `return_debit_status` in the
bank transaction's `additional_info`) is set on the bank transaction's page.

## Rights

- The overview, the orders and the Sammler name nobody: whoever may `:show`
  `WsjrdpFinAccount` sees them (the finance read tier and up).
- The debits, the returns and the debits section of an order's page are
  person-level payment data: `:log` on `WsjrdpFinAccount` (the audit tier and
  up), as the Personen tab of Beiträge. Their tabs and tiles are hidden
  without it.
- Editing a debit takes `:update` on `WsjrdpDirectDebitPreNotification` (the
  finance tier and up).

## Links into the area

- An account's statement (`/fin/acc/:id`) links the orders sent from it.
- The Beiträge overview links the direct debit orders.
- A debit under its person (`/fin/pn/:id`) links its order and its page in
  the area; an
  accounting entry (`/fin/ae/:id`, and its detail in the reconciliation)
  links its order -- for a return's entry the order of its return.
