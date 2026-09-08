# Reconciliation linking: associations with provenance + a rating tier

A reusable pattern for **associating rows of two tables** (usually
different tables) where the link is only *probably* right and we want
to record, per link, **how sure we are**, **how it was made**,
**when**, and **by whom** — and then show that back to the user with a
colour-coded confidence chip.

The provenance half of the pattern (the `*_link_meta` column of §1) carries
several finance links — the camt importer's `imported_subject_link_meta` /
`subject_link_meta`, the Moss side's `clearing_datev_booking_link_meta`,
`expense_datev_booking_link_meta` and `recipient_link_meta`, the entry's
`moss_booking_link_meta` / `camt_transaction_link_meta` (their column comments
point back here). The instance that carries a matcher and a rating chip on top
is **`DatevBooking` ↔ `AccountingEntry`** (a DATEV booking ↔ its
Beitragsbuchung), driven by `Fin::DatevBookingMatcher` and shown on the
reconciliation page and the booking detail page. This document describes the
general recipe and that concrete instance.

---

## 1. The pattern

For a link from table `A` to table `B` add, on the side that holds the foreign
key (here the link on `accounting_entries`):

| column          | meaning                                                                        |
| --------------- | ------------------------------------------------------------------------------ |
| `<b>_id`        | the association itself (`belongs_to`/`has_one`)                                 |
| `<b>_link_meta` | provenance as one `jsonb` object (empty `{}` when unlinked): `created_at`, `author_id`, `score` (0.0..1.0, or null), `automatic_manual`, `classification_string` (HOW linked — a short slug, or null) |

Design notes:

- **`classification_string` is intentionally a free-form string, not an enum / DB
  constraint.** The set of values keeps changing, and each link has its own set
  (the camt importer's subject link writes `"sepa_mandate"`); we don't want a
  migration per change. For the booking ↔ entry link the authoritative list
  lives **in code and in §3 below**: reading side
  `Fin::DatevBookingMatcher::AUTOMATIC_LINK_BASES` (value → its German label),
  writing side the scripts repo's
  `packages/wsjrdp2027/src/wsjrdp2027/datev_fee_links.py` (`LINK_TYPE_*`).
- **`null` classification_string is meaningful**: it marks a link that matched
  none of the deterministic rules — a genuine heuristic or hand-made link, whose
  quality is then *derived on the fly* by the rating function (§4).
- Keeping the provenance in ONE json column (rather than a column per attribute)
  lets the shape grow (e.g. `score`, `automatic_manual`) without a migration each
  time. It is written by **every** path that creates a link (import and UI), in
  **one place per side** (the importer's `link_entries`; the matcher's
  `write_pairs`), so it can never drift apart from the association.

---

## 2. The concrete instance — `AccountingEntry` → `DatevBooking`

The link + its provenance live on **`accounting_entries`**
(`db/migrate/20260828000500_add_reverse_datev_booking_links.rb`):

| column                     | role                                                        |
| -------------------------- | ----------------------------------------------------------- |
| `datev_booking_id`         | the association — the reconciled DATEV booking (unique 1:1)  |
| `datev_booking_link_meta`  | provenance as one JSON object (empty `{}` when unlinked)     |

`datev_booking_link_meta` keys:

| key                     | role                                                                  |
| ----------------------- | --------------------------------------------------------------------- |
| `created_at`            | WHEN linked (ISO 8601)                                                 |
| `author_id`             | BY WHOM (`1` = system/importer, else the acting user)                  |
| `score`                 | match quality `0.0..1.0` (`1.0` = 100 %); `null` for a pure hand-pick  |
| `automatic_manual`      | `"automatic"` (the DATEV import) or `"manual"` (any UI connect)        |
| `classification_string` | HOW linked (see §3), or `null` = heuristic/manual                      |

The booking holds no copies of its own. Its **person** is reached through the
linked entry (`booking.accounting_entry` → `AccountingEntry#person`, the entry's
subject), and its **bank transaction** is that entry's camt, mirrored onto
`wsjrdp_camt_transactions.datev_booking_id` (1:1,
`DatevBooking#camt_transaction`) — the mirror writes the id only, so the camt
row's own `datev_booking_link_meta` stays empty. `datev_booking_link_meta` on
the entry is the provenance of §1.

---

## 3. Who writes the link, and the `classification_string` values

Two writers, one shared set of `classification_string` values:

- **DATEV importer** (`wsjrdp_scripts`,
  `packages/wsjrdp2027/src/wsjrdp2027/datev_fee_links.py`, `link_entries`):
  writes `automatic_manual = "automatic"`, `author_id = 1` (system),
  `score = 1.0`.
- **UI connect** (the matcher's internal `write_pairs`, reached from the
  reconciliation "Verbinden" actions and the booking-detail connect form): writes
  `automatic_manual = "manual"` (bulk or single), `author_id = current_user.id`,
  the matcher `score` (`1.0` for a detected rule, else the scored value / 100,
  else `null`), and auto-detects the `classification_string` via
  `detect_link_type` for the two cases decidable from the pair alone, so a UI
  link of such a pair is classified exactly like the importer would.

`classification_string` values in use right now:

| value                                | rule                                                                          |
| ------------------------------------ | ----------------------------------------------------------------------------- |
| `"2025_fee_booking"`                 | 2025 fee rule: the person id **with role prefix** stands in the Buchungstext **and** the entry's Valuta is exactly the booking date (amount already guaranteed) |
| `"document_field_1_pre_notification"`| the Belegfeld 1 `Einzug-YYYY-MM-<SEQ>-<n>-<prenotif_id>` resolves via the pre-notification id to the person's unique entry (Ende-zu-Ende-ID channel) |
| `"retoure_matching_camt_return_by_amount_and_date"` | Retouren rule: a "Retoure" fee booking with a negative 41030-side amount meets the entry of a returned bank transaction (`wsjrdp_camt_transactions.return_reason`, not soft-deleted) on the same cents **and** the same `booking_date`, unique on both sides within ±14 days; entries flagged `excluded_from_fee_reconciliation` are out |
| `NULL`                               | matched no rule — a heuristic proposal accepted in the UI, or a hand-picked link |

Every non-null value is **import-equivalent** — a link the DATEV import itself
would (or did) create — and therefore maps to the `:automatic` rating tier (§4).
`detect_link_type` covers the first two; the Retouren rule needs the camt side
and the ±14-day uniqueness window over both whole tables, so only the importer
writes it — the matcher reads it (`AUTOMATIC_LINK_BASES`) and rates it.

---

## 4. The rating function

`Fin::DatevBookingMatcher.rate_pair(booking, entry)` rates
**one explicit pair in isolation** — no candidate search over other entries. It
returns a `Match` (or `nil` when the pair carries no signal at all) exposing:

- **`match.score`** — the computed rating as a percentage, `0..100`.
- **`match.tier`** — one of the four confidence tiers below.
- `match.basis` — a short human explanation; `match.details` — the tooltip text.

### The four tiers

| tier                | when                                                                    | chip colour        | icon |
| ------------------- | ---------------------------------------------------------------------- | ------------------ | ---- |
| `:automatic`        | `kind == :import` — an import-equivalent link (a non-null automatic `classification_string`, the live Ende-zu-Ende-ID channel, or the re-derived 2025 fee rule). Always 100 %. | green `#146c43`    | lock |
| `:heuristic_high`   | computed score `>= 100` (the scored channel's maximum)                  | green `#2f9e44` (close to automatic) | link |
| `:heuristic_middle` | computed score **over** `HEURISTIC_MIDDLE_MIN_PERCENT`                  | amber `#b8860b`    | link |
| `:heuristic_low`    | computed score **at or below** that threshold                          | orange/red `#d9480f` | link |

- The middle/low boundary is the single constant
  **`Fin::DatevBookingMatcher::HEURISTIC_MIDDLE_MIN_PERCENT` (= 50)** — a code-only
  knob, defined in exactly one place, not user-adjustable.
- Tier → colour + icon lives in **`Fin::BookingsHelper::MATCH_TIER_STYLES`**;
  the chip is rendered by `match_rating_chip(match, target_label:, compact:)`,
  the same styles reached without a `Match` in hand via `match_tier_style_for`
  (the reconciliation quick-select buttons) and listed by `match_rating_legend`.

### How a rating is decided

1. If the entry's `classification_string` (in `datev_booking_link_meta`) is one of the automatic values, the
   rating is **fixed** without re-deriving it from the current texts: tier
   `:automatic`, 100 %, and the canonical basis that value maps to in
   `Fin::DatevBookingMatcher::AUTOMATIC_LINK_BASES`.
2. Otherwise the two matcher channels run for this pair only: the live
   Ende-zu-Ende-ID channel (→ `:automatic`), else the scored person/date channel
   — `:automatic` as well when the pair satisfies the importer's 2025 fee rule
   (`import_equivalent_2025?`), otherwise a heuristic tier from the computed
   score.

Both channels rate the **actual textual** name/date/id evidence of the pair; a
link that already exists gets no bonus for existing.

---

## 5. Where the pieces live

| concern                          | file                                                                 |
| -------------------------------- | ------------------------------------------------------------------- |
| the `datev_bookings` table       | `db/migrate/20260828000100_add_datev_bookings.rb`                    |
| link + provenance columns        | `db/migrate/20260828000500_add_reverse_datev_booking_links.rb` (`datev_booking_id` + `datev_booking_link_meta` on `accounting_entries` and `wsjrdp_camt_transactions`) |
| `classification_string` values   | §3 above; `Fin::DatevBookingMatcher::AUTOMATIC_LINK_BASES` (value → label) and, import-side, `wsjrdp_scripts` `packages/wsjrdp2027/src/wsjrdp2027/datev_fee_links.py` (`LINK_TYPE_*`) — no migration or DB constraint lists them |
| rating, tiers, threshold, detect | `app/domain/fin/datev_booking_matcher.rb` (`rate_pair`, `Match#tier`, `HEURISTIC_MIDDLE_MIN_PERCENT`, `AUTOMATIC_LINK_BASES`, `detect_link_type`, `write_pairs`, `link_score`, `connect_pair!`) |
| chip + colours + provenance text | `app/helpers/fin/bookings_helper.rb` (`match_rating_chip`, `MATCH_TIER_STYLES`, `match_tier_style` / `match_tier_style_for`, `match_rating_legend`, `booking_link_rating`, `booking_link_provenance`) |
| booking detail display           | `app/views/fin/bookings/_booking_detail.html.haml`, `app/views/fin/bookings/_detail.html.haml` |
| reconciliation display           | `app/views/fin/reconciliation/participant_fees.html.haml`, `app/views/fin/reconciliation/_connect_controls.html.haml` |
| UI connect (passes acting user)  | `app/controllers/fin/reconciliation_controller.rb`, `app/controllers/fin/bookings_controller.rb` |
| import-side writer               | `wsjrdp_scripts` `packages/wsjrdp2027/src/wsjrdp2027/datev_fee_links.py` (`link_entries`, `match_2025_fee_entries`, `match_pre_notification_fee_entries`, `match_return_fee_entries`, `mirror_camt_links`), driven by `accounting_tools/import_datev_buchungsstapel.py` and, for the Retouren rule over the whole table, `accounting_tools/one-shots/link_datev_return_bookings.py` |

> Dev-only caveat: the reconciliation `reset_links` action (development only)
> must clear the entry's `datev_booking_link_meta` **and** its
> `datev_booking_id`, plus the camt side's `datev_booking_id`; otherwise an
> orphaned `classification_string` survives on a now-unlinked entry and would
> mis-drive the `:automatic` tier. The booking-detail unlink
> (`Fin::BookingsController#disconnect_entry`) clears the same three.

---

## 6. Reusing the pattern for another pair of tables

1. **Migration** — on the FK-holding table add `<b>_id` (the association) plus
   `<b>_link_meta` (`jsonb`, `null: false`, default `{}`), with a DB comment
   naming the column it is the provenance of and pointing at this doc (as the
   Moss link columns do). The `classification_string` values themselves stay out
   of the DB — no enum, no constraint.
2. **One writer per side** — funnel every link creation through a single method
   that stamps the whole meta object (mirror `write_pairs` / `link_entries`).
   Auto-detect the deterministic `classification_string` there; leave `null` for
   heuristic and hand-made links.
3. **Rating** — a `rate_pair(a, b)`-style function returning a match with
   `{score, tier}`: an explicit automatic `classification_string` fixes tier
   `:automatic` at 100 %; otherwise compute a score and bucket it around a
   **single** threshold constant into `:heuristic_high` / `:heuristic_middle` /
   `:heuristic_low`.
4. **Display** — one tier → colour + icon map and one chip helper, shared by
   every page that shows the link, plus a provenance help-text helper
   (when / by whom / how).
