# Payment codes

A payment code identifies a payment notice (`wsjrdp_payment_notices`) in the
remittance information of a transfer: a refund we pay, or a claim a person
pays. The bank statement import (wsjrdp_scripts) finds the code in the
remittance text and links the payment to its notice.

The format, the Reed-Solomon parameters, the issuing rules and the matching
of typed codes are specified in wsjrdp_scripts, `docs/payment_code.md`. This
page covers the wagon's part.

## Format

```
RF75 K7M3 QX9P NFK3        printed
RF75K7M3QX9PNFK3           electronic form, stored in payment_code
```

`RF` and two ISO 11649 check digits around a codeword of 8 Crockford base32
data symbols and 4 Reed-Solomon parity symbols over GF(32) (primitive
polynomial x^5 + x^2 + 1, generator 2, first consecutive root 1).

## Code

`Wsjrdp2027::PaymentCode` (`app/domain/wsjrdp_2027/payment_code.rb`), without
a gem:

| Method | Does |
|---|---|
| `encode_codeword(data, parity_length: 4)` | appends the parity symbols |
| `code_from_codeword`, `check_digits` | the RF form |
| `compact`, `format_code`, `codeword_of` | electronic and printed form; `O` reads as `0`, `I`/`L` as `1` |
| `valid?`, `valid_codeword?` | check digits and syndromes |
| `generate_distinct_codeword(issued_codewords)`, `generate_distinct(issued_codes)` | a new code at a Hamming distance of at least 8 and a Levenshtein distance of at least 4 to every issued one, in at most 10 draws; otherwise the farthest draw, never an issued one |

`Wsjrdp2027::PaymentCode::Index` holds the issued codewords for the distance
questions of a new draw. Its answers are exact -- the same as comparing with
every codeword one by one -- but it compares packed integers for Hamming and
skips Levenshtein where the bag distance already shows that the smallest
distance cannot change. `WsjrdpPaymentReference.generate!` keeps one index for
the whole run. Making 1000 codes takes about 18 s against 1000 issued codes,
1 min against 10,000, 2.5 min against 20,000 and 10 min against 50,000; the
time grows with the number of issued codes.

Drawn at random, the codes keep the distances well up to about 20,000 issued
codes. Around 50,000 a draw meets an issued code at a Hamming distance below 8
about as often as not (there are about 2.2 · 10^7 codewords within distance 7
of a given one, out of 32^8), and beyond that the draws run out of attempts
and fall back to the farthest one, which keeps the distances no longer.

`spec/fixtures/files/payment_code_vectors.json` is a copy of the test
vectors of wsjrdp_scripts; `spec/domain/wsjrdp_2027/payment_code_spec.rb`
reproduces every one of them.

Matching a typed code to an issued one is not done here.

## The stock of codes

`wsjrdp_payment_references` (`WsjrdpPaymentReference`) holds every code made:
`available` until handed out, then `assigned` for good, whatever becomes of
its notices; a `void` one is never handed out. `origin` says whether
wsjrdp_scripts or the wagon made it.

- `WsjrdpPaymentReference.assign!` hands out the oldest available reference
  (`FOR UPDATE SKIP LOCKED`) and marks it assigned. With none left it makes
  one itself (`origin` wagon). A collision with a code made at the same
  moment draws again.
- `WsjrdpPaymentReference.generate!(count)` makes available references,
  each far enough from every codeword in the table and from the others made
  in the same call.
- Making codes (`generate!`, and `assign!` with an empty stock) takes the
  transaction-level advisory lock `GENERATION_LOCK_KEY` (2027000001) before
  it reads the codewords there are, so two makers never draw against the same
  state and the distances hold. Reading and handing out stocked codes take no
  lock. A maker in wsjrdp_scripts takes the same key.
- The pool is `POOL_SIZE` (500) available codes; below `LOW_STOCK` (100) the
  Verwaltung page warns.
- `WsjrdpPaymentNotice#assign_payment_reference!` gives a notice a code from
  the stock when it is made (status `created`); run it in the transaction
  that saves the notice. A notice without a code carries the empty string in
  `payment_code` (the column is NOT NULL); several notices may share one
  reference (a remainder asked for under the first code).

## The Zahlungscodes page

Verwaltung → Zahlungscodes (`/fin/admin/payment_references`,
`Fin::PaymentReferencesController`). The finance write tier, the manage tier
and admins see it and edit a code's comment (`:show` / `:update` on
`WsjrdpPaymentReference`); making codes for the stock is `:configure_finance`
(admins and the manage tier), like the rest of the Verwaltung area
(`doc/navigation.md`, §8):

- the counts per status and a warning when the stock is low;
- making codes for the stock, for `:configure_finance` only: a count, or
  without one as many as the pool lacks (at most 5000 per request);
- the references as an expandable table (`doc/wsjrdp/expandable_table.md`),
  newest first, 50 per page, with a column menu and sortable headers.

The table is declared in `Fin::PaymentReferencesController::POLICY`:

| Part | File |
|---|---|
| Columns | `app/domain/fin/payment_references_columns.rb` — Code (printed, monospace), Status, Herkunft, Erzeugt, Vergeben, Ankündigungen (the number of payment notices using the code, every status counted); Kommentar in the columns menu only |
| Filter | `app/domain/fin/payment_references_filter_schema.rb` — Code (text, over the electronic and the printed form), Status, Herkunft, Erzeugt and Vergeben (dates in the application's time zone; Vergeben also `hat Wert` / `ist leer`), Zahlungsankündigungen (the count, `≠ 0` first) |
| Cells, values | `app/helpers/fin/payment_references_helper.rb` |

The notice count is one correlated subquery
(`Fin::PaymentReferencesColumns::NOTICE_COUNT_SQL`): the list selects it as
`notice_count`, sorts by it and the filter compiles it, so the three count
alike. The filter is remembered per session; the builder posts to
`/fin/admin/payment_references/apply`.

The Schnellauswahl holds the status as an **exclusive** group — one status, or
all of them behind the asterisk, as the counts above the table read — and the
preset "mit Zahlungsankündigung" (`Zahlungsankündigungen ≠ 0`).

A code's page, `/fin/admin/payment_references/:id`
(`fin_admin_payment_reference_path`), heads with "Zahlungscode #<id>" light and
muted and the printed code, and shows: the code printed and
electronic, the codeword, `payment_code_type`, `codeword_scheme` with
`data_length`, `parity_length` and the `rs_*` parameters, status, origin, the
two timestamps, the comment, and the payment notices using the code (person,
amount, status, created, description). It is also the lazy detail of the
code's row: the row loads it into its turbo frame, and the view answers that
frame through `wsjrdp_detail_frame` (`app/views/fin/payment_references/show`
and `_detail`). The links to a person leave the frame.

The comment is the one editable field (`_comment`): for who may `:update` the
code, a "Bearbeiten" next to it swaps in a textarea where the text stands, on
the page and in a row's detail alike. The form is sent from inside the frame
it stands in; `update` saves the comment alone and redirects to the code's
page, which answers that frame again, with the flash inside it.
