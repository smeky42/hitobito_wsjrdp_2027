# Plan: Unify Moss card transactions and balance movements

Executed in **2026-09** against the development database; see [§10 Execution
record](#10-execution-record). This file deliberately carries no names, amounts,
IBANs or booking texts.

## Context

Moss transactions were represented by two unrelated tables with vastly different
schemas. The card side had the table `moss_card_transactions` with a separate
child bookings table (`moss_card_transaction_bookings`) and direct two-level
links into `datev_bookings`. The balance side was the flat
`moss_balance_movements` table: no header, no DATEV link, reachable only
backwards from `accounting_entries`. Both kinds have to be reconciled against
DATEV, so both need the same machinery. Moss's own API already models every
spend type uniformly (`Expense` + `ExpenseLine` + `expenseType`).

Decisions taken up front:

- Both kinds will be reconciled to DATEV, so the balance side needs a
  multi-level schema.
- `wsjrdp_camt_transactions` stays out of the unification (too ISO-20022
  specific).
- Preserving the existing links and comments through it is fundamental.
- The Moss wallet `fin_account` becomes common to both kinds; the
  migration sets it on the card rows too.
- The automatic Moss→DATEV matcher is built later. This plan prepares
  the schema and the anchors, not the matcher.

## 1. Three levels: Transactions, Expenses, Bookings

The balance-movements export is **lossy**. It collapses a reimbursement
expense's internal split (ledger account, cost center, sphere) into a single
row, carries no cost center for invoices, and reports a conversion rate of `1.0`
even on foreign-currency payments. The reimbursement and invoice exports carry
essential additional data. That is what makes three levels necessary:

| level | table | one row per | key |
|---|---|---|---|
| **L1** | `moss_transactions` | Moss transaction: a card payment, an invoice, a reimbursement or a top-up | `moss_transaction_uuid` |
| **L2** | `moss_expenses` | one expense: a card payment, an invoice, or one expense of a reimbursement | `(moss_transaction_uuid, expense_number)` |
| **L3** | `moss_bookings` | one **split**, the grain DATEV books at | `booking_unique_item_number` |

A card transaction **is** a payment. An invoice or reimbursement transaction
**has** one payment in Moss, which is not modelled as a database entity of its
own yet; the balance export carries that payment's fields (dates, fees,
reference, recipient account) on the transaction. For a reimbursement the
transaction is a *bracket* around the expenses paid out together; the booking
level exists to split along ledger account, cost center, sphere and booking
text. The schema reflects three consequences:

- **Total amount, currencies and exchange rate belong to L1**. They are
  properties of the represented payment.
- Amounts exist at all three levels, in the base and in the transaction
  currency, and must agree: `signed_total_base_amount = Σ expenses = Σ
  bookings`.
- The **sign is uniform per transaction**.

**Uniform shape.** Every transaction has at least one expense and every expense
at least one booking. A card transaction, invoice or top-up has exactly one
expense (which exists solely to keep the invariants); a reimbursement can
have multiple expenses. A top-up has an artificial expense too, although it has
no expense account, so that the sum invariant holds for every kind. In the FIN
web UI only the reimbursement expense level is meaningful; for the other kinds
it collapses into the transaction.

## 2. Ruby model shape: STI at two levels

```
MossTransaction (base)            MossExpense (base)              MossBooking
  MossCardTransaction               MossCardTransactionExpense      (no STI:
  MossInvoice                       MossInvoiceExpense               a booking is
  MossReimbursement                 MossReimbursementExpense         uniform)
  MossTopUp                         MossTopUpExpense
```

`type` holds the class name and **is** the kind; the convenience column
`expense_type` is generated from it in the database. The reimbursement export's
`Expense type` (`EXPENSE` or `MILEAGE`) is the L2 column `moss_expense_type`,
named so it cannot be confused with that generated column. Rails instantiates
the right subclass automatically, so behaviour goes on the subclass and nothing
branches on `type` by hand. Associations are declared once on the base, which is
also what the reverse links target (`DatevBooking has_one
:moss_transaction_as_clearing` / `:moss_booking_as_expense`): one foreign key
each, because the subclasses share a table.

**STI, not Delegated Types**, on the usual four criteria: the kind-specific
detail is moderate and mostly archival, it is not heavily queried or validated
per kind, the kinds share a lifecycle, and we want a single FK target. The
bulkiest archival fields (invoice terms, mileage geometry) live in the
`other_moss_columns` jsonb rather than in columns. Delegated Types stays the
documented upgrade path.

## 3. Polymorphism and links

- **Accounts.** The account-linking idiom is used: `*_number` + `*_kind`
  + a **generated** `*_type` (`CREDITOR`/`DEBITOR` → `WsjrdpPersonalAccount`,
  else `WsjrdpLedgerAccount`) with a CHECK on the Kontenart. L1 carries
  `supplier_account`, `moss_balance_account` and `cash_in_transit_account`, L3
  the split's `account`. All of it is NULL-safe, because a top-up booking has
  no expense account at all.
- **DATEV.** Links exist only where DATEV actually posts:
  `moss_transactions.clearing_datev_booking_id` (the creditor→wallet leg) and
  `moss_bookings.expense_datev_booking_id` (the expense leg), each with a
  `*_link_meta` jsonb for provenance per `doc/fin/recon_linking.md`. **L2 gets
  no DATEV link.** Verified: In the example data set, no DATEV booking matched
  an expense total without also matching a booking. An expense's DATEV view is
  derived by joining its bookings.
- **Fee Contributions.** The link is owned by the fee contribution side:
  `accounting_entries.moss_booking_id` + `moss_booking_link_meta` (replacing
  `moss_balance_movement_id`), plus `camt_transaction_link_meta` beside the
  existing `camt_transaction_id`. **One booking : N entries**, because a single
  Moss payment may settle several people's contributions, with the app-enforced
  rule `Σ entry amounts ≤ the booking's amount`. The booking additionally
  carries `contribution_subject_id/_type`, the person whose contribution it
  concerns.
- **Creditor, approval, submitter, purchase order and export dates are
  properties of the transaction**: the creditor is `supplier_account_number`
  (its name, IBAN and BIC are standing data in `wsjrdp_personal_accounts`,
  reached through `supplier_account`; the exports' copies are not stored),
  `approver_name` / `approval_date`, `submitted_by` (who created the claim or
  uploaded the invoice; a different person from the payee on a third of the
  reimbursements), the invoice export's `po_number` / `pr_number` and its `Last
  Export Date` (the L1 column `last_export_date`).  The card export carries them
  itself; for the balance kinds they come from the detail export, where they are
  constant per transaction. The reimbursement export's `User IBAN` / `User BIC`
  are the payee's own and are not imported: `recipient_iban` / `recipient_bic`
  come from the balance export's `Recipient Account Number` / `Recipient Bank
  Code` (the same values, except where a BIC is missing). An expense delegates
  the approval fields to its transaction.  The `Supplier Vat ID` stays in
  `other_moss_columns`.
- **Who acted.** A card payment names its card holder (`card_holder_name`,
  `card_holder_team_name`, `card_used`, `card_purpose`; the name as printed on
  the card and the two constant card labels are `other_moss_columns` keys). An
  invoice or reimbursement names the finance user who released its payout
  (`payout_user_name`, `payout_team_name`, from the balance export's
  `Cardholder` / `Team Name`, which mean that user there, not a card holder).
  Every kind names its submitter and approver (above).
- **Recipient.** `moss_transactions.recipient_id` (+ `recipient_link_meta`) is a
  *different* role from `contribution_subject`: who the money was paid to.  The
  candidate name from the export is kept in `recipient_name`, so it survives
  even when no Person matched. It is filled for reimbursements and invoices: the
  account holder the transfer went to, parsed from the balance export's `Reason
  for Purchase` (`<Name>; ; -`). On a reimbursement that is the recipient name
  from the SEPA data of the person's Moss profile; on an invoice it is what the
  finance team entered for the transfer, mostly the creditor's name, otherwise
  the person paid back (a participant or a parent), which no other column
  holds. On a top-up the field names our own funding account, kept verbatim in
  the column `top_up_sender` (Moss cuts the field after 60 characters, so the
  IBAN is truncated; the camt link stays on amount + date).
- **Top-up funding.** `moss_transactions.camt_transaction_id` (+ meta). The
  export names the funding account only truncated (`top_up_sender`), so the
  link is matched on amount + date. The FK sits on the Moss side because that keeps an unrelated table free
  of Moss and gives the heuristic link its provenance meta.

Moss URLs are **computed** from the stored uuids (record and export view per
kind), never stored. The uuids are stable, the URLs might not.

## 4. Reconciliation with DATEV

Per Moss's documented booking logic every transaction posts as a three-step
chain. With our chart: wallet `36100`, cash-in-transit `13720`, collective
creditors `700000`/`700002` plus individual `700xxx`:

| step | DATEV leg | amount | reconciles to |
|---|---|---|---|
| 1 expense recording | `<expense account> → <creditor>` | per **split** | **L3 booking** (primary) |
| 2 supplier settlement | `<creditor> → 36100` | transaction total | **L1 transaction** |
| 3 wallet repayment | `36100 → 13720` | top-up | **L1 top-up ↔ camt** |

Not every transaction flows through the wallet. An invoice paid straight from
the bank to an individual creditor has **no** step-2 leg, which is why the
robust anchor is the booking level and the clearing leg is only a secondary
confirmation.

**Date anchor per kind**, matched against `datev_bookings.booking_date` (the
DATEV `Belegdatum`, the only per-row date the Buchungsstapel export carries):

| kind | anchor | where it lives |
|---|---|---|
| card | `booking_date` | L1 column |
| reimbursement | `Submitted On` | L1 `submitted_on` |
| invoice | `Invoice Date` | L1 `invoice_date` |
| top-up | the transaction uuid in `Belegfeld 1` | — |

Every kind's dates have columns of their own; no date column is shared between
exports, even where the values would coincide, and every anchor is an L1
column. The invoice's `invoice_date`, `delivery_date`, `due_date` and
`submitted_date` are columns of `moss_transactions`, filled from the invoice
export only (in Moss they are header facts; `delivery_date` is the second-best
invoice anchor). The reimbursement's `submitted_on` is a transaction column too:
it is Moss's `expenseTime` of the reimbursement header, the day the claim was
submitted, and constant across the expenses of every payout. A card payment's
Service Date and Receipt Date are transaction columns as well (`service_date`,
`receipt_date`). Only the reimbursement's expense has a date of its own on L2:
`purchased_on`, the expense line's `expenseTime`. The shell rows of the other
kinds carry no dates.

**Foreign currency: never match on EUR.** DATEV stores `Umsatz` in the
transaction currency with `WKZ Umsatz`, and each side converts with its own
rate. One expense leg in the data was even booked with the *inverted* rate,
producing an EUR base larger than the foreign amount. So a foreign-currency
booking is matched on `(transaction amount, currency)` first, with an EUR
fallback: an invoice stays foreign on both sides, but Moss converts a
reimbursement itself and DATEV then books the EUR amount. A row whose EUR base
exceeds its foreign amount is flagged as a suspected wrong-rate entry.

`Belegfeld 1` can hold a Moss uuid with its leading zeros dropped, so a uuid
match accepts a sufficiently long suffix. Steps 1 and 2 reconcile different
legs and must not compete for a DATEV row, so the matcher indexes the DATEV
rows once per pass; a top-up's single booking *is* its `36100` / `13720`
leg.

Everything that cannot be matched automatically ends up **explicitly
categorised**: booked after the export was taken, an account reclassified by the
accountant, a wrong-rate leg, a prepayment (DATEV books no expense leg for one),
settled outside the Moss export path (`manually_paid` / `manually_booked`), or
reconciled by hand, in which case `*_link_meta` records `automatic_manual =
'manual'` with author and timestamp.

## 5. Keys, and why they are constructed

The same CSV column name means different things in different exports.
`Sub-row Number` counts *expenses* in the balance export but *splits within one
expense* in the reimbursement export. So the keys are **built**, never taken
from the CSV:

| kind | `expense_number` (L2) | `booking_unique_item_number` (L3) |
|---|---|---|
| card | 1 | `<transaction uuid>_<Sub-row Number>` (card export) |
| invoice | 1 | `<transaction uuid>_<Sub-row Number>` (balance export) |
| top-up | 1 | `<transaction uuid>_<Sub-row Number>` (balance export) |
| reimbursement | balance `Sub-row Number` | `<Unique Expense ID>_<Sub-row Number>` (reimbursement export) |

The CSV `Unique Item Number` is **not** usable as a key: its suffix is a
running, file-position-dependent counter (offset by one on balance rows,
file-global in the reimbursement export), and it is empty on most reimbursement
rows. The raw value is preserved in `other_moss_columns["Unique Item Number"]`
(accessor `MossBooking#unique_item_number`). The constructed keys are unique
across all four kinds (a unique index enforces it), and `Sub Item Row Number` is
ignored entirely.

The importer attaches each real `Unique Expense ID` to the right expense **by
ordinal**: for every reimbursement the sequence of balance-row amounts equals
the sequence of expense totals; the importer's detail gate checks that the
two agree and skips a reimbursement otherwise. The balance row carries no
expense id to join on.

## 6. jsonb: what goes where

**`other_moss_columns`** holds data Moss exported that has no column in the
database schema, **every key being the CSV column header verbatim**. Nothing is
renamed on the way in. The header → snake_case mapping exists only in the
accessor maps `OTHER_MOSS_TEXT_COLUMNS` / `OTHER_MOSS_DATE_COLUMNS` on
`MossTransaction`, `MossExpense` and `MossBooking`, so it is normally not
necessary for the app to read raw keys. The migration file lists the keys of
every export per level, as a Ruby comment above each jsonb column.

Which keys land where:

- **Mostly-empty fields** are stored only when the cell has a value, on the
  level the field belongs to in Moss's own model (§9b). Header facts go to the
  transaction: the reimbursement export's `Reimbursement Name`, `Reimbursement
  Payment Status` and `Supplier Vat ID` (`DETAIL_TX_OTHER` in the importer), the
  card export's `Reason for Purchase`, the `Sage *` codes and the card payment's
  expense facts (`Invoice File Name`, `Card Acceptor Name`, `Airline Ticket
  Number`, `Is Prepayment?`, release plan; the card transaction *is* its own
  expense in Moss), and the invoice export's payment status, type, terms, discounts,
  reviewers and file name (`INVOICE_OTHER_TX`; the workflow status is the column
  `invoice_status`). Only a reimbursement's expense has facts of its own:
  `Attached File Name`, the mileage type, route and distance, and its balance
  row's `Category`. The shell rows of the other kinds carry no keys. The line's
  own fields (unit price, quantity, VAT code / name / rate from every export,
  Moss's client code) go to the booking.
- **The payment's amount, currency and rate columns are mirrored** under their
  Moss names even when a house column holds the same value, and even when empty,
  so the source stays visible next to the derived columns. The balance export's
  *per-row* amounts are not mirrored on the transaction (they are the first
  expense's figures, not the payment's), and the invoice line's currency and
  rate are not mirrored on the booking (they are the payment's).
- **`Category` is a per-row value** in the balance export (it varies within a
  transaction) and is the ledger account's name, keyed by the account number
  that is a column. It gets no column and is kept as a raw field on the row's
  level: the reimbursement expense (L2), the invoice line or top-up booking
  (L3). The exports' other copies of that name (`Name of Expense Account`,
  `Expense Account - Name`, `Original Expense Account`) are not stored at all;
  the name comes from the standing data, and `down` derives it the same way.
- **`additional_info`** holds app-side annotations (today
  `denylist_subject_candidates`, the candidates rejected for the
  contribution-subject matching), plus whatever a migration needs for its own
  `down`: the unification keeps the legacy row identity it must restore
  (`legacy_balance_*`) here, never in `other_moss_columns`.

Some detail-export columns are deliberately **not imported**: the reimbursement
export's `Supplier account` and the invoice export's `Supplier Number` (both
equal the balance export's `Supplier Account` on every imported transaction,
i.e. `moss_transactions.supplier_account_number`), and the per-expense `Approver
Name` / `Approval Date`, which feed the transaction's columns instead. The
creditor's `Supplier Name` / `Supplier IBAN` / `Supplier BIC` of every export
are standing data (`wsjrdp_personal_accounts`, reached through
`supplier_account`) and are not stored.

**The texts of a payment, with the Moss website's labels.** The website uses two
labels for the texts of every level, "Name" and "Buchungstext"; the CSV column
behind each label differs per export. Which API field each of them is remains an
inference from the labels (§9b):

| level | kind | CSV column | website label | our column |
|---|---|---|---|---|
| L1 | card, invoice | `Parent Booking Text` | Buchungstext (of the transaction) | `transaction_posting_text` |
| L1 | reimbursement | `Reimbursement Name` | Name | `transaction_name` (the claim's title; also kept under its header) |
| L1 | reimbursement | `Reimbursement Description` | Buchungstext | `transaction_posting_text` (often empty; the display falls back to the title) |
| L2 | reimbursement | `Expense Name` | Name (of the expense) | `expense_name` |
| L2 | reimbursement | `Parent Booking Text` | Buchungstext (of the expense) | `expense_posting_text` |
| L3 | card | `Note` | Buchungstext (of the booking) | `booking_posting_text` |
| L3 | reimbursement, invoice | `Expense Description`, `Booking Text` | Buchungstext (of the split / line) | `booking_posting_text` |

Two names next to the texts of a reimbursement: `recipient_name` is the
recipient name from the SEPA data of the payee's Moss profile (parsed from the
balance export's `Reason for Purchase`), `submitted_by` is the name of the Moss
user who filed the claim. `payment_reference` is the balance export's `Payment
Reference`, the SEPA Verwendungszweck of the outgoing transfer, house-normalised
(Moss appends our organisation's name). The two never coincide on an invoice,
whose reference is built from the invoice number, the unit and a `WSJ27MOSS`
number; on a reimbursement the reference is the name with umlauts, ß and
non-SEPA characters *deleted* and the organisation appended: most references
equal the name, some differ only by those deleted characters, a few were
reworded on one side. The name is the claim's title and is stored as
`transaction_name` (and kept under its header as well); the transaction text is,
as for every kind, the Buchungstext: the reimbursement export's `Reimbursement
Description` (free text that mostly says something found in no other text of the
transaction; often empty, and then the text stays empty and the display falls
back to the title). `created_in_moss_on` is `Expense.createTime` (`Creation
date`). Neither exists in the card or invoice exports.

## 6a. The Moss website's labels, per kind

Collected by walking through one page per kind together with the user, the dev
database's rows next to the Moss pages. "Zahlungsansicht" is the
`/export/balance-movements/<uuid>` page of the payment behind a reimbursement,
an invoice or a top-up; "transaction page" is the reimbursement, invoice or card
page. "not shown" means the page carries no such field. The statuses
(`Transaction State`, `Invoice Status`, `Invoice Payment Status`, `Reimbursement
Payment Status`) and the invoice's review fields were skipped. Two general
observations: the website shows spend as a positive amount (our signed columns
hold spend negative, the WSJRDP convention), and it shows the top-up's funding
account with the full IBAN, which only the export truncates.

**Reimbursement** (transaction page unless noted)

| level | CSV column (export) | our column | website label |
|---|---|---|---|
| L1 | `Reimbursement Name` (reimb) | `transaction_name` | Name |
| L1 | `Reimbursement Description` (reimb) | `transaction_posting_text` | Buchungstext |
| L1 | `Submitted On` (reimb) | `submitted_on` | Beantragt am |
| L1 | `Submitted By` (reimb) | `submitted_by` | Eingereicht von |
| L1 | `Approval Date` / `Approver Name` (reimb) | `approval_date` / `approver_name` | Freigegeben am / Freigegeben von |
| L1 | `Payment Date` (balance) | `payment_date` | Zahlungsdatum, on the Zahlungsansicht |
| L1 | `Payment Reference` (balance) | `payment_reference` | Verwendungszweck on the Zahlungsansicht; on the transaction page without a label |
| L1 | `Recipient Account Number` / `Recipient Bank Code` (balance) | `recipient_iban` / `recipient_bic` | Konto des Empfängers / BIC / Bankleitzahl, on the Zahlungsansicht (the Hitobito view keeps IBAN / BIC) |
| L1 | `Reason for Purchase` (balance), parsed | `recipient_name` | Name des Kontoinhabers, on the Zahlungsansicht (the Hitobito view keeps Empfängername) |
| L1 | `Supplier Account` (balance; the `Supplier Name` is not stored) | `supplier_account_number` | Kreditor, on the export view |
| L1 | `Amount`, summed (balance) | `signed_total_base_amount` | no label: the transaction's amount, sign flipped |
| L1 | `Booking Date`, `First Export Date` (balance), `Creation date` (reimb), `Moss Balance Account`, `Cash in Transit Account` (balance) | columns | not shown |
| L2 | `Expense Name` (reimb) | `expense_name` | Name |
| L2 | `Parent Booking Text` (reimb) | `expense_posting_text` | Buchungstext |
| L2 | `Purchased On` (reimb) | `purchased_on` | Kaufdatum |
| L2 | `Amount` (balance row) | `signed_expense_base_amount` | no label, sign flipped |
| L2 | `Expense type`, `Attached File Name` (reimb), `Category` (balance) | column / keys | not shown |
| L2 | `KM Expense Type` (reimb) | key | Kilometersatz |
| L2 | `Travel Route` (reimb) | key | Reiseroute (start and destination are not shown separately) |
| L2 | `Trip Distance In Unit` (reimb) | key | Gesamtdistanz; `Reimbursable Distance In Unit` appears, if at all, as a correction of it without a label |
| L2 | `Trip Type`, `Commute Deduction In Unit`, `Distance Unit`, `Vehicle Type` (reimb) | keys | not shown |
| L3 | `Expense Account` / `Cost Center - Name` / `Cost Carrier - Number` (reimb) | `account_number` / `cost_center_number` / `sphere_number` | Sachkonto / Kostenstelle / Sphäre |
| L3 | `Expense Description` (reimb) | `booking_posting_text` | Buchungstext |
| L3 | `Amount` (reimb, per split) | `signed_base_amount` | Bruttobetrag, sign flipped |

**Card** (transaction page)

| level | CSV column (export) | our column | website label |
|---|---|---|---|
| L1 | `Payment Date` (card) | `payment_date` | Transaktionsdatum |
| L1 | `Booking Date` (card) | `booking_date` | Buchungsdatum (checked on two payments whose `Settlement Date` differs from it) |
| L1 | `Service Date` (card) | `service_date` | Leistungsdatum |
| L1 | `Approval Date` (card) | `approval_date` | Freigegeben am |
| L1 | `Settlement Date`, `Receipt Date`, `First Export Date`, `Last Export Date` (card) | columns | not shown |
| L1 | `Merchant Name` (card) | `merchant_name` | Händlername auf Abrechnung |
| L1 | `Merchant City` / `Merchant Country` (card) | `merchant_city` / `merchant_country` | not shown |
| L1 | `Cardholder` (card) | `card_holder_name` | Karteninhaber |
| L1 | `Card Purpose` + `Card Used` (card) | `card_purpose` + `card_used` | Karte: one linked field "«Kartenzweck» *1234", the card purpose followed by the last four digits of the card number in muted type; to render it the same way, take the digits from `card_used` ("VIRTUAL - 1234") |
| L1 | `Parent Booking Text` (card) | `transaction_posting_text` | Buchungstext |
| L1 | `Invoice Number` (card) | `invoice_number` | Belegnummer |
| L1 | `Total Amount` (card) | `signed_total_base_amount` | Betrag |
| L1 | `Supplier Account` (card) | `supplier_account_number` | Kreditor |
| L1 | `Reason for Purchase`, `Invoice File Name`, `Card Holder Name`, `Card Holder Label`, `Card Label` (card keys); `Team Name` (`card_holder_team_name`), `Approver Name`, `Post Spend Approval Status` (card) | keys / columns | not shown |
| L3 | `Account Number` / `Cost Center - Number` / `Sphere` (card) | `account_number` / `cost_center_number` / `sphere_number` | Sachkonto / Kostenstelle / Sphäre |
| L3 | `Note` (card) | `booking_posting_text` | Buchungstext |
| L3 | `Home Amount` (card) | `signed_base_amount` | Bruttobetrag, sign flipped |
| L3 | `Amount (excl. VAT)` (card) | key | Nettobetrag, sign flipped |
| L3 | `VAT Code` / `VAT Name` / `VAT Rate` (card) | keys | Steuersatz |
| L3 | `Unit Price`, `Quantity` (card) | keys | not shown |

**Invoice** (invoice page; Zahlungsansicht for the payment)

| level | CSV column (export) | our column | website label |
|---|---|---|---|
| L1 | `Invoice Date` (invoice) | `invoice_date` | Rechnungsdatum |
| L1 | `Delivery Date` (invoice) | `delivery_date` | Lieferdatum |
| L1 | `Due Date` (invoice) / `Net Due Date` (invoice key) | `due_date` / key | Nettofälligkeit (the two fields are equal on every invoice today, so the page cannot tell them apart) |
| L1 | `Booking Date` (balance) | `booking_date` | Bezahlt am (one example, where the payment date of the day before is not shown) |
| L1 | `Payment Date` (balance), `Submitted Date` (invoice) | `payment_date`, `submitted_date` | not shown |
| L1 | `Parent Booking Text` (invoice) | `transaction_posting_text` | Buchungstext |
| L1 | `Invoice Number` (balance) | `invoice_number` | Rechnungsnummer |
| L1 | `PO Number` / `PR Number` (invoice) | `po_number` / `pr_number` | Bestellnummer / Kaufanfragen Nummer |
| L1 | `Submitted By` (invoice) | `submitted_by` | Eingereicht von |
| L1 | `Payment Reference` (balance) | `payment_reference` | Verwendungszweck |
| L1 | `Supplier Account` + `Supplier Name` (balance; the name is not stored) | `supplier_account_number` | Kreditor, number and name shown together |
| L1 | `Supplier IBAN` / `Supplier BIC` (invoice) | not stored (standing data) | IBAN / BIC |
| L1 | `Supplier Vat ID` (invoice) | key | not shown |
| L1 | `Amount` (invoice) | `signed_total_transaction_amount` | Betrag, in the invoice's currency |
| L1 | `Conversion Rate` (invoice) | `exchange_rate` | Wechselkurs, shown as "1 € = 4,2486" |
| L3 | `Amount in Home Currency` (invoice) | key | Umgerechneter Betrag (Moss's own conversion, not the amount paid) |
| L1 | `Amount`, summed (balance) | `signed_total_base_amount` | Gesamtbetrag on the Zahlungsansicht, sign flipped |
| L1 | `Original Amount` (balance) | `signed_total_transaction_amount` | Zahlungsbetrag on the Zahlungsansicht |
| L1 | `Payment Fee` / `Fees Amount` (balance) | `payment_fee` / `fees_amount` | Zahlungsgebühren / Fremdwährungsgebühren on the Zahlungsansicht |
| L1 | not exported | derived | the Zahlungsansicht's Wechselkurs = `Original Amount` ÷ (`Transaction Amount Excluding Fees` − `Payment Fee`), the rate of the payment itself; the export's `Conversion Rate Including Fees` is 1.0000 and not it |
| L1 | `Reviewed by`, `Last reviewed`, `Verified By Name`, `Verifier Names`, `Is Prepayment?`, `General Invoice Type`, `Invoice File Name`, `Sage Transaction Type` (invoice) | keys | not checked |
| L3 | `Booking Text` / `Expense Account - Number` / `Cost Center - Number` / `Cost Carrier - Number` (invoice) | `booking_posting_text` / `account_number` / `cost_center_number` / `sphere_number` | Buchungstext / Sachkonto / Kostenstelle / Sphäre |
| L3 | `Amount` (invoice line) | `signed_transaction_amount` | Betrag, sign flipped |
| L3 | `Net Amount`, `VAT Amount`, `VAT Code` / `VAT Name` / `VAT Rate`, `Unit Price`, `Quantity` (invoice), `Category` (balance) | keys | unknown: we book without VAT |

**Top-up** (Zahlungsansicht only)

| level | CSV column (export) | our column | website label |
|---|---|---|---|
| L1 | `Amount` (balance) | `signed_total_base_amount` | no label |
| L1 | `Payment Date` (balance) | `payment_date` | no label, in the line "Einzahlung · «Datum»" |
| L1 | `Reason for Purchase` (balance) | `top_up_sender` | no label, the header line; shown with the full IBAN |
| L1 | `Category` = `Moss Deposit` (balance) | key | not shown as such (the page says Einzahlung) |

`Combined Description` of the reimbursement export is not a field of its
own: on every row it is `Reimbursement Description` + " - " +
`Expense Description` with empty parts skipped, and it stays ignored.

## 7. Migration

[`db/migrate/20260901200000_unify_moss_transactions.rb`](../../db/migrate/20260901200000_unify_moss_transactions.rb).

**The migration reads no CSV.** Everything it needs beyond the legacy tables is
put into the database first, by
`accounting_tools/enrich_moss_balance_movements.py` in the `wsjrdp_scripts`
project, which writes into `moss_balance_movements.additional_info`:

| key | content |
|---|---|
| `moss_bookings` | the complete list of that expense's L3 bookings, one JSON object each |
| `moss_expense_uuid` | the reimbursement's `Unique Expense ID` |

It runs for **reimbursements only** and there for **every** row, not just the
split ones, so the migration always finds a complete list. Card, invoice and
top-up rows need no enrichment: their bookings derive 1:1 from the row itself
(an invoice's several balance rows *are* its lines).

`up` then runs in this order:

1. **Guard, before any schema change.** Every reimbursement row must carry its
   booking list and expense uuid.  Otherwise it raises and the schema is
   untouched.
2. Create the three tables. A column comment names the CSV column and the
   export a value comes from; explanations, website labels and API inferences
   are Ruby comments beside the columns, and the generated columns carry no
   comment.
3. Backfill card → L1 + one L2 shell + one L3 per split. The card header's
   `comment` and subject fold **onto the bookings**; `up` writes no L1 or L2
   annotation. The legacy header jsonb's snake_case keys are re-keyed to their
   CSV headers and stay on the payment (`CARD_LEGACY_TX_KEYS`, with the legacy
   `invoice_file_name` and `is_prepayment` columns as keys), except the line
   keys, which are lifted onto every split (`CARD_LEGACY_LINE_KEYS`);
   `CARD_LEGACY_BOOKING_KEYS` re-key the split's own keys. The legacy supplier
   name and IBAN/BIC keys go into `additional_info` (`legacy_supplier_*`) for
   `down` only; the legacy `original_expense_account` and the account names
   are not carried.
4. Backfill balance → one L1 per transaction (the total is summed; the export
   has no total column), L2 per kind, and **real** L3 bookings expanded from the
   enriched list. A balance row's `Category` stays on the row's level (the
   reimbursement expense, the invoice line or top-up booking), its `Client
   Number` goes onto every booking of the row. What `down` will need to rebuild
   a flat row (the row's `Unique Item Number` and `Sub-row Number`, and for a
   reimbursement expense its collapsed `Account Number`) goes into
   `additional_info` as `legacy_balance_*`, the row's supplier name as
   `legacy_supplier_name`; the row's excl.-VAT figures go onto the first booking
   of an expanded expense only, so `down` can sum them back. The always-empty
   legacy `moss_expense_id` is not carried; `down` writes it back empty.
5. Assert the sum invariant for every transaction.
6. Move the fee contribution link to `accounting_entries.moss_booking_id` (a
   deterministic join on transaction uuid + expense number) and drop
   `moss_balance_movement_id`, refusing to continue if any link is left over.
7. Drop the three legacy tables.

`down` is the exact inverse of the legacy state. Every mapping is a plain
column join, which is what makes it exact; the account names the legacy tables
carried are derived from the standing data by number, the creditor's name and
bank details come back from `legacy_supplier_*`. It does **not** write the
enrichment's scaffolding (`moss_bookings`, `moss_expense_uuid`) back into the
flat rows; that comes from the reimbursement export, so before running `up`
again the enrichment script runs again, and the guard makes sure of it. The
only lossy direction is annotation: if several bookings of one expense carried
*different* comments, the flat row has one slot.

**Delete behaviour.** Loose reconciliation links (`datev_bookings`,
`accounting_entries`, camt, `Person`) are `ON DELETE SET NULL`: deleting one
clears the link and never a Moss row. The tight Moss chain (L1 → L2 → L3) is
`NOT NULL` + `ON DELETE CASCADE`, which keeps the child half of the invariant
automatically; the transaction-level half may differ after a partial delete,
and that is allowed. **The import script guards the invariant.** It reports
the status, writes only per-transaction-consistent rows, and a globally broken
invariant is not an import stop. No trigger, no `before_destroy`.

## 8. Importer

One importer replaces the two legacy ones:
`accounting_tools/import_moss_transactions.py` in `wsjrdp_scripts`. It follows
`docs/writing_import_scripts.md`: declarative column maps per export,
`SingleTableUpsertPlanBuilder` plan/apply per level, a plan preview before the
production approval, `--dry-run` and `--rollback-for-testing`, `source_file`
kept out of the diff, `fin_account_id` written on INSERT only.

- **All four exports go into one call.** The split detail exists only in the
  reimbursement and invoice exports, and so does the real exchange rate. An
  invoice's booking dimensions (cost center, sphere, distribution
  combination) come from the invoice export as well; the balance export has
  no cost-center column.
- **Per-transaction detail gate, never per file.** A reimbursement or invoice
  whose detail rows are missing, whose row count does not match, or whose
  amounts do not line up is skipped **individually** and logged with the
  reason. Everything else is imported and nothing is deleted, so a partial
  export costs those transactions, never the run.
- **Never overwritten:** `comment`, `additional_info`, `status`,
  `contribution_subject_*`, the DATEV / camt / recipient links with their
  `*_link_meta`, `manually_paid` / `manually_booked`. None of them is part of a
  diffed value set, so a re-import cannot touch them.
- The payment reference keeps its house normalisation (Moss appends our own
  organisation name to every reference, often truncated mid-word), through the
  now-public `wsjrdp2027.moss.normalize_payment_reference`.
- Every `*_uuid` value travels as a real `uuid`, not as text. Postgres has no
  `uuid = text` operator, so a text key silently matches nothing.
- Every `other_moss_columns` key it writes is the CSV column header verbatim
  (`*_OTHER_*` tuples through `_verbatim`, `*_MIRROR_*` tuples through
  `_mirror`); the migration's key lists are generated from these tuples.
- A column of the same name can mean different things in different exports:
  `Transaction Amount Excluding Fees` is per transaction in the balance export
  but per split in the card export, so the card total is summed over the
  splits.
- A column is filled only from the export that carries its field:
  `expense_name` (L2) from the reimbursement export's `Expense Name`,
  `merchant_name` (L1) from the card export's `Merchant Name`, and every date
  column from exactly one CSV field (§4). The transaction text comes from the
  detail export of the kind (`Parent Booking Text`, `Reimbursement Description`);
  the balance export's reference stays `payment_reference`.

## 9. Verification method

Each of these is a gate; a red one blocks the migration. All of it runs against
the development database, restored from a production dump, **never against
production**.

- **Baseline** before anything: counts and the full per-row inventory of the
  three legacy tables, every `accounting_entries` link, every card DATEV link.
- **`up`**: row and sum parity; the three-level invariant per transaction and
  globally; amount, currency and account fidelity per booking including the
  generated columns; every preserved comment / `additional_info` / subject on
  exactly the booking it came from; all `accounting_entries` links remapped;
  the wallet `fin_account_id` on every row.
- **Reversibility**: `up → down → up`, asserting set-equality against the
  baseline after `down` and the `up` gates again.
- **Schema**: generated columns recompute, the NULL logic holds for top-ups,
  the CHECKs and the three unique indexes are exactly as decided, and the
  delete matrix behaves.
- **Rails**: STI resolves to the concrete subclass at both levels, the
  `WsjrdpTransaction` concern works on both kinds, every association loads, the
  `DatevBooking` back-links resolve, and the `fin/` tree renders as before.
- **Importer**: legacy parity, a fresh import into emptied tables reproducing
  the state, idempotency (a second run writes nothing), the detail gate on each
  of its branches, plus `ruff` / `mypy` / `ty` and the tests.
- **Reconciliation**: the DATEV matching re-run from the migrated tables must
  reproduce the same match rate and the same categorisation, which is what
  proves the schema kept every anchor.

## 9a. What the FIN views act on

The wallet statement (`/fin/acc/<wallet>`) and the linking UI act on the
**booking**, not on the transaction. The booking is the row that carries the
contribution subject, the accounting-entry link and the candidate deny list, and
it is the only Moss level with a route of its own (`/fin/moss_booking/:id`). So
for now `WsjrdpFinAccount#transactions` returns the wallet's bookings, reached
through its transactions. Summing them gives the same balance as summing the
transactions; the sum invariant guarantees it. A side effect of the unification is
that the card splits now appear in the wallet statement too, which is what the
plan intended.

The statement view stays shared with the bank accounts (`description`, `note` in
italics, `comment` per row). A Moss booking instead renders
`MossBooking#text_lines`. The transaction's and the expense's comments appear
through `parent_comments` next to the booking's own, which remains the only
editable one. The candidates for the contribution subject are searched in the
split's and the expense's Buchungstext, the claim's title (`transaction_name`),
the account holder paid (`recipient_name`) and the SEPA reference.

Two shared concerns, `WsjrdpTransaction` and `SubjectLinking`, speak the
vocabulary of a bank statement row: `subject`, `fin_account`, `amount_eur`.
`MossBooking` adapts those three names onto `contribution_subject`, its
transaction's `fin_account` and `signed_base_amount`, so the concerns stay
shared with `WsjrdpCamtTransaction` unchanged and nothing else in the app has to
know about the rename.

The transaction itself has **no page** in the app. The booking's detail view names
its transaction and links out to the Moss record page for it.

## 9b. How the Moss API model maps onto the three levels

Source: the Moss OpenAPI spec (a copy lives in `wsjrdp_scripts` under
`External_Data/Moss_Exports/openapi_spec/`; the wallet and reconciliation
schemas are only in the online version at
`https://developers.getmoss.com/specs/latest/`). As of now, we have no access to
the Moss API; this section records how its objects, per the published spec, and
our tables correspond.

Moss has **two explicit levels plus a separate wallet ledger**:

- **`Expense`**, the header returned by `GET /v1/expenses`. Its type filter
  accepts exactly three header types: `CARD_TRANSACTION`, `INVOICE`,
  `REIMBURSEMENT`. The header carries `status`, `supplierId`, `createdBy`,
  `bookingText`, `description`, `homeAmount`, `expenseTime` (per type: the
  receipt date of a card payment, the invoice date, the submission date of a
  reimbursement), `exportMetadata` (first / last export time) and a
  type-specific `expenseMetadata` (card: merchant details, settlement /
  service / booking dates, receipt status, invoice number; invoice: due, net
  due and delivery dates, payment status, payment reference and date,
  approvers, verifiers, last reviewer, payment term; reimbursement: payment
  status, channel, time and recipient).
- **`ExpenseLine`**, a flat list under the header, typed by `expenseType`:
  `CARD_TRANSACTION_LINE` and `FX_FEE` under a card payment, `INVOICE_LINE`
  under an invoice, and under a reimbursement the expenses
  (`REIMBURSEMENT_INVOICE_LINE`, `MILEAGE_LINE`, `PER_DIEM_LINE`) together
  with their splits (`REIMBURSEMENT_INVOICE_LINE_SPLIT`, "nested within" a
  expense line; the receipt file hangs on the parent line). A line carries the
  expense account, the dimensions (cost center and cost carrier have fixed
  dimension ids), the tax rate, `bookingText` / `description`, net / gross /
  VAT amounts, `amount`, `homeAmount`, `conversionRate`, `quantity`,
  `unitPrice` and line-type metadata (mileage: distance, unit, trip type,
  rate).
- **`BankTransaction`** (`POST /v1/bank-transactions/search-query`): the
  money movements of the wallet, typed `CARD`, `PAYOUT`, `TOP_UP`,
  `WITHDRAWAL`, `REPAYMENT`, with the amount including fees,
  `amountBeforeFees`, `originalAmount` on foreign currency, booking and value
  date, counterparty and a fee list. A top-up is **not** an expense in Moss.
  Moss also offers its own bank-to-ledger reconciliation objects (matching
  groups, ledger entries, bank-ledger mappings).

| Moss | our level |
|---|---|
| `Expense` header (`CARD_TRANSACTION`, `INVOICE`, `REIMBURSEMENT`) | `moss_transactions` (L1); `type` ↔ `expenseType` |
| `BankTransaction` of type `TOP_UP` | `moss_transactions` of type `MossTopUp` (L1) |
| expense line of a reimbursement (`REIMBURSEMENT_INVOICE_LINE`, `MILEAGE_LINE`, `PER_DIEM_LINE`) | `moss_expenses` (L2) |
| split line (`REIMBURSEMENT_INVOICE_LINE_SPLIT`), card split (`CARD_TRANSACTION_LINE`), invoice line (`INVOICE_LINE`) | `moss_bookings` (L3); an unsplit expense is its own single booking |
| no middle level: for a card payment or an invoice the header *is* the expense | the shell rows of `moss_expenses` for card, invoice and top-up |
| `FX_FEE` line | not in the exports; the fees are L1 columns |

So our three levels are a normalisation of Moss's header plus typed lines: the
header (or the wallet movement) is L1, the expense-type lines are L2, the
split-type lines are L3. The split dimensions are line attributes in Moss
exactly as they are booking columns here. The one thing we add is the uniform
middle level; the one thing Moss keeps per line and we keep per payment is the
currency conversion, which is constant within a payment in the data.

**Consequence for column placement**. Whatever Moss keeps on the header is an L1
fact for every kind: the card payment's merchant (`merchant_name` /
`merchant_city` / `merchant_country`), its receipt file and deferral fields, the
invoice's `invoice_date` / `delivery_date` / `due_date` / `submitted_date`, its
status, terms and reviewers, the reimbursement's `submitted_by`, `submitted_on`,
`transaction_name` and `created_in_moss_on`. Whatever it keeps on an expense
line is an L2 fact of a reimbursement (`expense_name`, `expense_posting_text`,
`purchased_on`, `moss_expense_type`, the mileage fields). Whatever it keeps on a
split line is an L3 fact. The shell rows of a card payment, an invoice or a
top-up carry nothing kind-specific: no column of `moss_expenses` and no
`other_moss_columns` key is filled for them.

Field correspondences (header): `id` ↔ `moss_invoice_uuid` /
`moss_reimbursement_uuid` (the card export's `Transaction ID` is the card
transaction itself); `status`, the workflow status (DRAFT … COMPLETED) ↔
`invoice_status`, which only the invoice export carries (`Invoice Status`); the
state of the payment (`CardTransactionMetadata.transactionStatus`: PENDING,
ACCEPTED, REVERSED, REJECTED; the exports' `Transaction State`) ↔
`moss_transaction_state`; `supplierId` ↔ `supplier_account_number` (Moss's
`Supplier` object carries `code` = the account number; its `iban` and `bic` are
standing data here, `vatIdNo` a key); `createdBy` ↔ `submitted_by`;
`bookingText` / `description` ↔ the texts of §6, by the website's labels
(Buchungstext ↔ `bookingText`, Name ↔ `description`): `transaction_posting_text`
is the `bookingText` of every kind (for a reimbursement the `Reimbursement
Description`) and the reimbursement's `transaction_name` is its `description`;
`homeAmount` ↔ `signed_total_base_amount`; `expenseTime` ↔ the per-kind DATEV
date anchor of §4; `exportMetadata` ↔ `first_export_date` / `last_export_date`;
the invoice metadata's `paymentReference` / `paymentDate` ↔ `payment_reference`
/ `payment_date`, its approvers ↔ `approver_name` / `approval_date`; the
reimbursement metadata's recipient ↔ `recipient_*` (`recipient_name` is the
recipient name from the SEPA data of the Moss profile); the wallet movement's
`counterparty` ↔ `top_up_sender` (the balance export's `Reason for Purchase` of
a top-up, cut after 60 characters). Line: `expenseAccountId` ↔ `account_number`,
the cost-center and cost-carrier dimensions ↔ `cost_center_number` /
`sphere_number`, `taxRateId` ↔ the `VAT Code` / `VAT Name` / `VAT Rate` keys,
`bookingText` / `description` ↔ `booking_posting_text`, `amount` / `homeAmount`
↔ `signed_transaction_amount` / `signed_base_amount`, `netAmount` / `vatAmount`
↔ the `(excl. VAT)` and `VAT Amount` mirrors, `quantity` / `unitPrice` ↔
`Quantity` / `Unit Price`, the mileage metadata ↔ the mileage keys of the
expense. Wallet movement: `amount` ↔ `signed_total_base_amount`,
`amountBeforeFees` ↔ `total_amount_excluding_fees`, `originalAmount` ↔
`signed_total_transaction_amount`, the fee list ↔ `fees_amount` / `payment_fee`.

**Inferred, not observed.** We have no access to the Moss API, so the CSV
exports are the only source and four correspondences above are inferences from
the spec and the website's labels, not observations:

1. the card export's `Transaction ID` is the id of the card `Expense` (or of
   the `CARD` wallet movement);
2. the label rule Buchungstext ↔ `bookingText`, Name ↔ `description`, on the
   header and on the expense line alike;
3. the reimbursement's expense fields sit on `REIMBURSEMENT_INVOICE_LINE` /
   `MILEAGE_LINE` and its splits on `REIMBURSEMENT_INVOICE_LINE_SPLIT`;
4. the `counterparty` of a `TOP_UP` movement carries the full funding IBAN
   that the export truncates (the website shows it in full, so Moss holds
   it; only the export cuts it).

With API access a handful of GET calls (expenses, bank transactions) would
settle them. Every other field correspondence in this section (`createdBy` ↔
`submitted_by`, `expenseTime` ↔ the dates of §4, the metadata fields) is an
inference of the same kind, drawn from the field names and the exports' fill
pattern.

## 10. Execution record

Executed originally on 2026-09-01 against the development database, restored
from a production dump, and re-run after every review round through 2026-09-03
(`down → up → import`, twice each time); never against production. Every run was
green on the gates of §9:

- the legacy baseline captured before anything (the three legacy tables, the
  `accounting_entries` links, the card DATEV links), then the enrichment of
  every reimbursement row, idempotent;
- `up`: one L1 row per transaction of the four kinds, the L2 expenses and
  shells, the L3 splits; every contribution link remapped; no invariant
  violation; every comment, contribution subject and denylist entry on the
  booking it came from; the wallet `fin_account_id` on every row; the guard
  refuses a run without the enrichment before any schema change;
- `up → down → up`: `down` reproduces the legacy tables column by column,
  compared against the pre-migration backup (the only differences are what
  changed in Moss between the backup's export and the run's);
- the import onto the migrated database: updates only, no inserts, every
  changed value `NULL → a real value`; a second run writes nothing; a fresh
  import into emptied tables, compared and then rolled back, reproduces the
  state column by column and on L1 key by key (on L3 the migration
  additionally writes the `(excl. VAT)` figures `down` needs);
- the detail gate on each of its branches, proven on mutated export copies:
  exactly the affected transaction skipped with its reason, nothing deleted;
- the schema dumped and loaded into the wagon's test database behind the
  database-name interlock, the finance ability spec green;
- the DATEV reconciliation re-run from the migrated tables: all bookings but
  one matched (most automatically, the rest by nearest date; the one absent
  is a prepayment, which DATEV books without an expense leg) and every
  clearing leg but those of the invoices paid straight from the bank, which
  never touch the wallet; most matched bookings sit at 0 days from their
  anchor.

The design decisions taken along the way are worked into the sections above.

### Follow-ups, deliberately not done here

1. The December-2025 top-up creditor mismatch (a DATEV-import question: the
   2025 chart had a single supplier number, which cannot express the 2026
   distinction between the two collective creditors).
2. Dead code in `wsjrdp2027`: with the legacy importers gone, the
   `MossBalanceMovement` CSV class and its `_pg` helper have no caller left.
3. 34 pre-existing spec failures around `:impersonate_user` in the person
   ability specs; unrelated to this work, but the suite is red until someone
   decides whether the ability or the shared example is right.
4. The automatic Moss→DATEV matcher. Decided on 2026-09-03: not built for
   now; `accounting_tools/one-shots/moss_datev_matching_report.py` stays the
   prototype it would grow from. The alternative is Moss's own reconciliation
   API (matching groups between wallet movements and general-ledger entries,
   ledger-account sync, bank-ledger mappings). Its prerequisites: the DATEV
   bookings would have to be uploaded into Moss (a write scope and a
   DATEV → Moss data flow); it covers the wallet side only (steps 2 and 3 of
   the Moss chain), not the expense legs per split (step 1); and it needs API
   access, which we do not have.
5. A narrower mirror policy. Today every amount, currency and rate column of
   the exports is mirrored into `other_moss_columns` under its Moss name,
   even where a house column holds the same value (`Total Amount` beside
   `signed_total_base_amount`, `Home Amount` beside `signed_base_amount`, the
   currencies beside `currency` / `currency_original`), for source fidelity.
   A narrower policy would mirror only what has no house column. Kept as is
   by decision.
