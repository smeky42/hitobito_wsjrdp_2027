# Reconciliation linking: associations with provenance + a rating tier

A reusable pattern for **associating rows of two tables** (usually different
tables) where the link is only *probably* right and we want to record, per link,
**how sure we are**, **how it was made**, **when**, and **by whom** — and then
show that back to the user with a colour-coded confidence chip.

The first (and so far only) instance is **`DatevBooking` ↔ `AccountingEntry`**
(a DATEV booking ↔ its Beitragsbuchung), driven by `DatevBookingMatcher` and
shown on the reconciliation page and the booking detail page. This document
describes the general recipe and that concrete instance.

---

## 1. The pattern

For a link from table `A` to table `B` add, on the side that holds the foreign
key (here `datev_bookings`):

| column                    | meaning                                                        |
| ------------------------- | ------------------------------------------------------------- |
| `<b>_id`                  | the association itself (`belongs_to`/`has_one`)               |
| `<b>_link_type`           | HOW the link was made — a short slug, or `NULL` for a plain heuristic/manual link |
| `<b>_linked_at`           | WHEN the link was written                                     |
| `<b>_link_person_id`      | BY WHOM — a `people.id` (`1` = system/importer, otherwise the acting user) |

Design notes:

- **`*_link_type` is intentionally a free-form string, not an enum / DB
  constraint.** The set of values keeps changing; we don't want a migration per
  change. The authoritative list lives as a **Ruby comment on the migration**
  (see `db/migrate/20260817000100_add_datev_bookings.rb`) and in §3 below.
- **`NULL` link_type is meaningful**: it marks a link that matched none of the
  deterministic rules — a genuine heuristic or hand-made link, whose quality is
  then *derived on the fly* by the rating function (§4).
- The provenance columns are written by **every** path that creates a link
  (import and UI), in **one place per side** (the importer's `_link_entry`; the
  matcher's `write_pairs`), so they can never drift apart from the association.

---

## 2. The concrete instance — `DatevBooking` → `AccountingEntry`

All extra columns on `datev_bookings` that participate in a fee link (answering
"do I list all the extra columns?" — yes, here they are):

| column                              | role                                                                 |
| ----------------------------------- | ------------------------------------------------------------------- |
| `accounting_entry_id`               | the association — the linked Beitragsbuchung (unique 1:1)            |
| `accounting_entry_link_type`        | HOW linked (see §3), or `NULL` = heuristic/manual                    |
| `accounting_entry_linked_at`        | WHEN linked                                                          |
| `accounting_entry_link_person_id`   | BY WHOM (`1` = system/importer, else the acting user)               |
| `person_id`                         | mirrored on connect — the entry's subject person                    |
| `camt_transaction_id`               | mirrored on connect — the entry's bank-transaction row              |

`person_id` and `camt_transaction_id` are *not* provenance; they are convenience
mirrors written in the same `write_pairs` UPDATE so a booking carries its person
and bank transaction without a join. Only the three `*_link_*` columns are the
provenance triple of §1.

---

## 3. Who writes the link, and the `link_type` values

Two writers, one shared set of `link_type` values:

- **DATEV importer** (`wsjrdp_scripts/accounting_tools/import_datev_buchungsstapel.py`,
  `_link_entry`): sets `accounting_entry_link_person_id = 1` (system).
- **UI connect** (`DatevBookingMatcher.write_pairs`, reached from the
  reconciliation "Verbinden" actions and the booking-detail connect form): sets
  `accounting_entry_link_person_id = current_user.id`, and auto-detects the
  `link_type` for the two import-equivalent cases via
  `DatevBookingMatcher.detect_link_type`, so a UI link of such a pair is stamped
  exactly like the importer would.

`accounting_entry_link_type` values in use right now:

| value                                | rule                                                                          |
| ------------------------------------ | ----------------------------------------------------------------------------- |
| `"2025_fee_booking"`                 | 2025 fee rule: the person id **with role prefix** stands in the Buchungstext **and** the entry's Valuta is exactly the booking date (amount already guaranteed) |
| `"document_field_1_pre_notification"`| the Belegfeld 1 `Einzug-YYYY-MM-<SEQ>-<n>-<prenotif_id>` resolves via the pre-notification id to the person's unique entry (Ende-zu-Ende-ID channel) |
| `NULL`                               | matched neither rule — a heuristic proposal accepted in the UI, or a hand-picked link |

Both non-null values are **import-equivalent** — a link the DATEV import itself
would (or did) create — and therefore map to the `:automatic` rating tier (§4).

---

## 4. The rating function

`DatevBookingMatcher.rate_pair(booking, entry, ignore_person_link: false)` rates
**one explicit pair in isolation** — no candidate search over other entries. It
returns a `Match` (or `nil` when the pair carries no signal at all) exposing:

- **`match.score`** — the computed rating as a percentage, `0..100`.
- **`match.tier`** — one of the four confidence tiers below.
- `match.basis` — a short human explanation; `match.details` — the tooltip text.

### The four tiers

| tier                | when                                                                    | chip colour        | icon |
| ------------------- | ---------------------------------------------------------------------- | ------------------ | ---- |
| `:automatic`        | `kind == :import` — an import-equivalent link (a non-null automatic `link_type`, or the live Ende-zu-Ende-ID channel). Always 100 %. | green `#146c43`    | lock |
| `:heuristic_high`   | computed score `== 100`                                                 | green `#2f9e44` (close to automatic) | link |
| `:heuristic_middle` | computed score **over** `HEURISTIC_MIDDLE_MIN_PERCENT`                  | amber `#b8860b`    | link |
| `:heuristic_low`    | computed score **at or below** that threshold                          | orange/red `#d9480f` | link |

- The middle/low boundary is the single constant
  **`DatevBookingMatcher::HEURISTIC_MIDDLE_MIN_PERCENT` (= 50)** — a code-only
  knob, defined in exactly one place, not user-adjustable.
- Tier → colour + icon lives in **`WsjrdpBookingsHelper::MATCH_TIER_STYLES`**;
  the chip is rendered by `match_rating_chip(match)`.

### How a rating is decided

1. If `booking.accounting_entry_link_type` is one of the automatic values, the
   rating is **fixed** without re-deriving it from the current texts: tier
   `:automatic`, 100 %, and a canonical basis
   (`"Beitrag aus 2025 (Personen-Nr + Valuta)"` /
   `"Ende-zu-Ende-ID in Belegfeld 1"`).
2. Otherwise the two matcher channels run for this pair only: the live
   Ende-zu-Ende-ID channel (→ `:automatic`), else the scored person/date channel
   (→ a heuristic tier from the computed score).

### `ignore_person_link:`

The scored channel normally short-circuits to 100 % when the booking's person is
already the entry's person ("Person bereits an der Buchung hinterlegt"). For an
**already-linked** pair (the booking-detail page) that is trivially true and
tells you nothing about the link's quality, so the booking detail passes
`ignore_person_link: true` to rate the **actual textual** name/date/id evidence
instead. The reconciliation page (rating *proposals* for still-unlinked
bookings) leaves it at the default `false`.

---

## 5. Where the pieces live

| concern                          | file                                                                 |
| -------------------------------- | ------------------------------------------------------------------- |
| columns + `link_type` value list | `db/migrate/20260817000100_add_datev_bookings.rb`                    |
| rating, tiers, threshold, detect | `app/models/datev_booking_matcher.rb` (`rate_pair`, `Match#tier`, `HEURISTIC_MIDDLE_MIN_PERCENT`, `detect_link_type`, `write_pairs`) |
| chip + colours + provenance text | `app/helpers/wsjrdp_bookings_helper.rb` (`match_rating_chip`, `MATCH_TIER_STYLES`, `booking_link_rating`, `booking_link_provenance`, `booking_link_type_label`) |
| booking detail display           | `app/views/fin/bookings/_booking_detail.html.haml`                   |
| reconciliation display           | `app/views/fin/reconciliation/participant_fees.html.haml`            |
| UI connect (passes acting user)  | `app/controllers/fin/reconciliation_controller.rb`, `app/controllers/fin/bookings_controller.rb` |
| import-side writer               | `wsjrdp_scripts/accounting_tools/import_datev_buchungsstapel.py` (`_link_entry`, `_match_2025_fee_entries`, `_match_pre_notification_fee_entries`) |

> Dev-only caveat: the reconciliation `reset_links` action must clear the
> provenance triple **and** `camt_transaction_id` alongside `accounting_entry_id`
> / `person_id`; otherwise an orphaned `link_type` survives on a now-unlinked
> booking and would mis-drive the `:automatic` tier.

---

## 6. Reusing the pattern for another pair of tables

1. **Migration** — on the FK-holding table add `<b>_id` (the association) plus
   `<b>_link_type` (string, null), `<b>_linked_at` (datetime, null),
   `<b>_link_person_id` (bigint, null). Document the `link_type` values in a Ruby
   comment on the migration, not a DB comment.
2. **One writer per side** — funnel every link creation through a single method
   that stamps the provenance triple (mirror `write_pairs` / `_link_entry`).
   Auto-detect the deterministic `link_type` there; leave `NULL` for heuristic.
3. **Rating** — a `rate_pair(a, b, ignore_person_link:)`-style function returning
   `{score, tier}`: an explicit automatic `link_type` fixes tier `:automatic` at
   100 %; otherwise compute a score and bucket it around a **single** threshold
   constant into `:heuristic_high` / `:heuristic_middle` / `:heuristic_low`.
4. **Display** — one tier → colour + icon map and one chip helper, shared by
   every page that shows the link, plus a provenance help-text helper
   (when / by whom / how).
