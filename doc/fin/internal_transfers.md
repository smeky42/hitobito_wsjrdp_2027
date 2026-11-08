# Umbuchungen (internal transfers)

An *Umbuchung* is money that only moves between two of the contingent's own
accounts -- the bank accounts and the Moss wallet. It is neither income nor
expense, so the account overview leaves it out of its monthly in- and outflow.
This guide covers the model, how transfers are found, the pages, the rights
and the import API.

- Model: `app/models/wsjrdp_internal_transfer.rb` (`WsjrdpInternalTransfer`),
  the leg marks in `app/models/concerns/wsjrdp_internal_transfer_leg.rb`
- One leg as the pages read it: `app/domain/fin/internal_transfer_leg.rb`
- Detection: `app/domain/fin/internal_transfer_detection.rb`
- Pages: `app/controllers/fin/internal_transfers_controller.rb`,
  `app/views/fin/internal_transfers/`, `app/helpers/fin/internal_transfers_helper.rb`,
  list columns `app/domain/fin/internal_transfers_columns.rb`, list filter
  `app/domain/fin/internal_transfers_filter_schema.rb`, the detail's legs table
  `app/domain/fin/internal_transfer_legs_columns.rb`
- Rights: `Wsjrdp2027::VariousAbility` / `Wsjrdp2027::TokenAbility`
  ([`doc/roles.md`](../roles.md), "Finance tiers")
- Specs: `spec/models/wsjrdp_internal_transfer_spec.rb`,
  `spec/domain/fin/internal_transfer_detection_spec.rb`,
  `spec/controllers/fin/internal_transfers_controller_spec.rb`,
  `spec/abilities/internal_transfer_ability_spec.rb`,
  `spec/helpers/fin/accounts_overview_helper_spec.rb`

## Model

`wsjrdp_internal_transfers` holds one row per transfer: `comment`,
`link_meta` and `additional_info` (both jsonb). Its **legs** point at it:

| table | column | a leg is |
|---|---|---|
| `wsjrdp_camt_transactions` | `internal_transfer_id` | a bank transaction |
| `moss_transactions` | `internal_transfer_id` | a Moss transaction (L1: the whole payment, never its splits) |

The foreign key is at the same time the marker: `internal_transfer_id IS NULL`
selects the real movements (`.without_internal_transfer` on both models). A
row can be the leg of one transfer only; the key is `ON DELETE SET NULL`, so
dissolving a transfer keeps its rows.

A leg's **side** follows from its sign: money leaving an account is the
*Von* side, money arriving the *Nach* side. A transfer is **vollständig** when
it has at least one leg on each side and the legs sum to exactly 0, else
**offen** (its other side may not be imported yet). Fees and returns of a
transfer are not modelled; all amounts are EUR.

`link_meta` records how a transfer came about:

| key | meaning |
|---|---|
| `source` | `suggestion` (confirmed on the page), `api` (the import scripts), `manual` (put together by hand) |
| `rule` | the detection rule of a suggestion (see below) |
| `by` | `{person_id, name}` or `{service_token_id, name}` |
| `at` | when it was linked |
| `edits` | one entry per later change of the legs: `at`, `by`, `added`, `removed` (leg keys) |

A leg is named across the two tables by its **key**, `camt:<id>` or
`moss:<id>`. A bank transaction replaced by a later statement's copy or
deleted is no leg any more. The camt importer updates rows in place and never
writes `internal_transfer_id`, so a re-import keeps the links.

## Detection

`Fin::InternalTransferDetection` works the suggestions out fresh on every
call -- one SQL query; nothing is stored until a suggestion is linked.

A **pair** is an outflow and an inflow of the same amount on two different
own accounts, at most **10 calendar days** apart in either direction, where
**every IBAN a side names belongs to the other side's account and at least one
side names one**. An account's own IBANs are its `iban` and its `top_up_iban`.
That one rule covers:

| rule (`link_meta.rule`) | case |
|---|---|
| `both_ibans` | a transfer between two bank accounts, both statements naming the other side |
| `receiver_iban` | only the outflow names the receiving account |
| `sender_iban` | only the inflow names the sending account (e.g. the interest a notice account passes on) |
| `moss_top_up` | a bank outflow to the wallet's `top_up_iban` and a Moss top-up (Moss names no IBAN) |

Requiring *every* named IBAN to match is what keeps two transfers of the same
amount on the same day apart when they go to different accounts.

The 10 days cover 3 bank days in the worst case of weekends, the nationwide
holidays and banks closed on 24 and 31 December (a Friday before Christmas to
the Monday after). Measured on the development copy of the data (about 1,100
free rows): about 4 ms; with the rows multiplied by 10 about 18 ms, by 50
about 270 ms, by 200 about 0.9 s -- computing it on every page view is fine.

Rows that do not take part: rows that already are a leg, rows marked *no
transfer*, and pairs one of their rows denies (see below).

The result has three groups:

- **unique** -- pairs whose rows have no other candidate;
- **ambiguous** -- the other pairs, grouped so that pairs sharing a row are
  one group; the user picks one;
- **missing** -- free bank transactions that name another own account's IBAN
  but have no partner. They are **waiting** until the third bank day after
  their date (`Wsjrdp2027::Target2`, the TARGET calendar) and **without
  counterpart** after that.

## Marks on a leg

A wrong suggestion is answered by a mark in the row's `additional_info`, next
to the existing `denylist_subject_candidates`:

| key | set by | meaning |
|---|---|---|
| `not_internal_transfer` | "Keine Umbuchung" | the row is no transfer at all |
| `denylist_internal_transfer_candidates` | "Ausgewählte verwerfen", "keine davon" | keys of rows that are not this row's counterpart (both rows deny each other) |

There is no page to undo a mark yet; clear the key in `additional_info`.

## Pages

`/fin/acc/internal_transfers`, the tab *Umbuchungen* of *Konten & Wallets*:

1. **Vorschläge zur Verknüpfung** (only for whoever may create transfers):
   the unique pairs as a checked table ("Ausgewählte verknüpfen" /
   "Ausgewählte verwerfen"), each ambiguous group as a choice with "keine
   davon", the rows without counterpart ("Als offene Umbuchung anlegen" /
   "Keine Umbuchung") and, for information, the rows still waiting.
2. **Umbuchungen**: an expandable table (array-backed). Its filter is the
   generic one (`Fin::InternalTransfersFilterSchema`, filtered in Ruby): the
   Schnellauswahl holds the status (*vollständig* / *offen*, an exclusive
   group), the filter pane offers Konto (Von oder Nach), Von-Konto,
   Nach-Konto, Betrag, Datum, Status, Volltextsuche (both purposes and the
   comment), Verwendungszweck (Von), Verwendungszweck (Nach) and Kommentar.
   The accounts of a side are one list field (`:integer_list`): "ist"
   matches if any account of the side is chosen, "ist nicht" if none is. The optional column "Verwendungszweck (Von)" shows the
   outgoing rows' purpose; the page link sits in the row as a double icon
   button (`t.detail_page(column: true)`). A row opens the transfer's detail.

The **detail** (`_detail`) shows the two sides as cards with the arrow and the
amount between them, the legs with their sum and how they were linked. The
legs are an expandable table ("Buchungen der Umbuchung", prefix `itl`, all on
one page, sortable): a row opens the transaction's fields -- a bank row
`_camt_leg_detail`, a Moss row the Moss list's own detail
(`fin/moss_transactions/_detail`) -- and the double icon button leads to the
transaction's page. The
same partial is the transfer's own page (`/fin/acc/internal_transfers/:id`,
with the h1 "Umbuchung #id" and amount and accounts) and the pane of a list
row. The trash can beside **Bearbeiten** dissolves the transfer after a
confirmation. **Bearbeiten** opens the form in the same frame:
the comment, per side the legs with "entfernen" and "Buchung hinzufügen" --
the shared transaction picker ([`doc/wsjrdp/transaction_picker.md`](../wsjrdp/transaction_picker.md)),
one row for *Von*, any number for *Nach*, with the open rest of the transfer
offered as "gleicht aus" (kept current while legs are ticked off or picked) --,
and a live sum. A transfer left without legs is dissolved; "Umbuchung
auflösen" does it directly. **Neue Umbuchung** puts one together by hand.

Saving answers like the account detail: from a frame it leaves the frame
(Turbo stream action `redirect_top`) for the transfer's page, or for the list
with the row open (`?o=<id>`); a failed save stays in the frame. The frame on
the transfer's page has the prefix `itpage`, the list's rows `it`.

The chart on `/fin/acc` leaves every leg of a transfer -- complete or open --
out of *Ein* and *Aus*; the balance line still includes them, so it ends at the
total balance.

## Rights

The read and the audit tier see transfers; the write tier (`finance`, also
CMT admins) and the manage tier may do everything with them, destroying one
included. Service tokens get the same per finance scope, capped by their
acting person.

## Import API

`POST /fin/acc/internal_transfers/link_unique.json` links every unique pair
and answers the counts `{linked, ambiguous, waiting, without_counterpart}`. It
only answers a request signed in with a **service token** (header `X-Token`;
no CSRF token is asked of it) that may create transfers -- scope
`finance:write` with an acting person on the write tier. A signed-in person
gets 403.

The import scripts of `wsjrdp_scripts` (`import_camt_bank_statements.py`,
`import_moss_transactions.py`) call it after a committed import through
`wsjrdp2027.link_internal_transfers`, with the token from the config key
`hitobito_api_token`. Without a token the step is skipped; a failed call is
only logged.
