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
| Rückläufer | `/fin/payments/returns` | `Fin::PaymentReturnsController` | `wsjrdp_camt_transactions` with a return reason |

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
skip flag, amount, purpose, comment, reference, debtor and mandate date; once
it is in a SEPA file or skipped, the comment alone. The manage tier
(`:admin_finance` on the pre-notification -- an elevated tier, so only in a
session that picked it, `?max_finance_permission=finance_manage`) also sets the
status, in any status, from `Settings.pre_notification_payment_status`, and
the mandate reference of a debit only announced. The amount takes the kit's money input, the mandate
date hitobito's date field.

Another page may link either page with `return_url`, a path of this
application (`direct_debit_path(id, return_url: request.fullpath)`). The
debit's page then leads "Zurück" there instead of to its tab, "Bearbeiten", the form and
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
its debits. A debit belongs to a Sammler when it names it
(`direct_debit_payment_info_id`), or -- the debits of the later orders name
none -- when it has the Sammler's order, sequence type and collection date
(`Fin::PaymentQueries.payment_info_debit_condition`). The debits section of
an order's and a Sammler's page is one (`Fin::DirectDebitsSection`).

## Returns

A return is a bank transaction (`wsjrdp_camt_transactions`) with a
`return_reason` -- the bank statement is the record. The accounting entry
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
