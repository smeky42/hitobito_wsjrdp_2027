# Account transactions tables — decision log

Decisions behind the bank statement table and the all-transactions page. The
code is the source of truth; this log says why.

## D1 Bank statement

`/fin/acc/:id` of a bank account is an expandable table of its camt
transactions. The description cell keeps the link actions of the old
statement; a row opens the transaction's detail with inline edit. The filter
lives in the URL (pages link to "this account"); the table prefix is `ct`, as
the wallet's table on the same controller uses the empty one.

## D2 All transactions

`/fin/acc/all` (the first account tab; `/fin/acc` stays the overview) lists
bank and Moss transactions together. `Fin::AccountTransaction` is a
`UNION ALL` subquery that borrows the camt table's name, so filter, sort, sum
and paging run in SQL; a view would not survive `db:schema:load`. Its `.all`
builds the union only outside a scope, as Kaminari calls `.all` inside one.

A row's description is its own table's cell (bank: the statement partial,
Moss: the Moss list's cell); the page loads those records only while the
description is shown. Row keys are `camt-<id>` and `moss-<id>`, so the detail
frame check allows hyphens before the id.

## D3 The other side

`Fin::CamtParty`, one SQL expression for cell, sort and filter; the first rule
that gives a value wins:

1. a transfer leg: the account on the other side;
2. the other side's IBAN belongs to an own account: that account;
3. the other side's name, the side taken from the transaction code's family
   (kept on a return), else from the sign;
4. a label: batch transfer, batch direct debit, or the bank.

The return lists and the details of a bank transaction or a return use it too.

## D4 Kinds

`Fin::AccountKinds`: a bank row is a return, a (linked) transfer, fees and
interest (domain `ACMT`) or a plain payment; a Moss top-up is a transfer.
Colours keep the Moss kinds', a transfer takes the top-up's, returns the red of
returns. Bank statements offer the four bank kinds as a quick choice.

Quick choice: Alt-click chooses one kind alone, right-click or a long press
offers only / all but / all. The segment wraps; on a phone it shows icons.

## D5 Hidden columns

A hidden column's value moves into the description: the party as a line, the
dates, kind and account as chips. Its sort moves below the description's
header; every sortable column also has its sort in the column menu, which can
be pinned open. An auto column counts as shown, an excluded one gets nothing.

## D6 Dates

The booking day is the date every row has (bank and Moss); it is the default
column and sort. Moss's value date (`payment_date`) is missing on many rows,
so only bank rows have one: a hidden column on a statement, never shown on the
all-transactions page (`cols: {never:}`). The booking day's column gives way
on a phone, where its chip shows instead.

## D7 Persons

`Fin::TransactionPersons` gives a row's linked persons as one text: the bank
transaction's person and its contribution bookings' persons, or the persons of
a Moss transaction's bookings. The person filter searches that text.
