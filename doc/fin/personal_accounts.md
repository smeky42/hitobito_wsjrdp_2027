# Personal accounts (Debitoren/Kreditoren): DATEV ↔ Moss data model

This document describes, how supplier/creditor master data flows between
**Moss** (spend management, the system where suppliers are created) and **DATEV
Rechnungswesen** (bookkeeping), and how it maps onto our
[`wsjrdp_personal_accounts`](../../db/migrate/20260823000200_add_wsjrdp_personal_accounts.rb)
table. Based on a field-by-field comparison of two real exports of the same 88
creditors:

* A Moss supplier export (27 columns, UTF-8; the columns are
  flattened/renderered views of the [Moss API `Supplier`
  object](https://developers.getmoss.com/api/get-supplier-by-id), schema:
  [`Supplier.yaml`](https://developers.getmoss.com/specs/latest/schemas/Supplier.yaml)).
* A DATEV export, format category 16 **"Debitoren/Kreditoren"** v5 (254 fields,
  CP1252/`;`, DTVF header line), field semantics per DATEV service information
  [1003221 "ASCII-Import: Feldbeschreibungen für
  Standardformate"](https://apps.datev.de/help-center/documents/1003221),
  chapter 6. Only **49 of 254** fields carry any value in our data — counting
  the empty string and `0` as empty, but `0,00` as a value (the importer instead
  treats all three as empty, which yields 38).

## Concepts

* A DATEV **Personenkonto** (personal account) is a subledger account for a
  business partner: **Debitor** (customer, receivables) or **Kreditor**
  (supplier, payables). Its number is one digit longer than the Sachkontenlänge
  ("Personen-Kontonummer: Sachkontennummernlänge + 1", doc 1003221) — with our
  5-digit chart (SKR 42) personal accounts are 6-digit: Debitoren
  `1xxxxx`–`6xxxxx`, Kreditoren `7xxxxx`–`9xxxxx`. Our CHECK constraints
  `chk_personal_account_number_six_digits` and
  `chk_personal_account_type_matches_number` encode exactly that.
* **Moss is the primary source for suppliers.** Suppliers are created/edited in
  Moss; an automatic sync (Moss → DATEV, via the DATEV Rechnungsdatenservice
  used by the [Moss–DATEV
  integration](https://www.datev.de/web/de/marktplatz/moss)) creates the
  matching Kreditoren-Personenkonto in DATEV. Only payables exist today: all 88
  rows are Kreditoren. That follows from the number range `7xxxxx`, not from
  `Adressattyp` — that field says *Unternehmen*, see below. Participant fees are
  NOT booked through Debitoren.


## Common fields

Several fields/columns contain identical values, i.e., are truly synced between
Moss and DATEV. In the Hitobito database we use non-prefixed column names for
them:

| Moss column | DATEV field (exact) | eq/n | `wsjrdp_personal_accounts` column |
|---|---|---|---|
| `Supplier Number` | `Konto` | 88/88 | `number` (shared key) |
| `Supplier Name` | `Name (Adressattyp Unternehmen)` | 86/88 ¹ | `name` |
| `IBAN` | `IBAN-Nr. 1` | 59/59 | `iban` |
| `SWIFT-Code` | `SWIFT-Code 1` | 51/51 | `bic` |
| `Street` | `Straße (Rechnungsadresse)` | 59/59 | `street` |
| `Second line` | `Adresszusatz (Rechnungsadresse)` | 0/0 ² | `address_second_line` |
| `Post code` | `Postleitzahl (Rechnungsadresse)` | 59/59 | `post_code` |
| `City` | `Ort (Rechnungsadresse)` | 57/59 ¹ | `city` |
| `Country` | `Land (Rechnungsadresse)` | 61/61 | `country` |

¹ Note: The mismatches are pure **transliteration**: the DATEV DebKred export is
CP1252 (per DATEV document
[1003221](https://apps.datev.de/help-center/documents/1003221), chapter 2.  All
format categories use `Zeichensatz: ANSI`) and cannot represent all European
scripts, in particular Polish diacritics, so the export carries `ą → a`, `Ś →
S`, `ń → n`. Moss keeps the original Unicode. Comparing such values needs care,
otherwise a DATEV import silently degrades the stored Unicode, cf.,
[datev_cp1252.md](datev_cp1252.md).

² The second address line is empty on all 88 rows on **both** sides, so there
is no row on which the two could be compared — the pairing rests on the field
semantics (Moss API `address.addressLine2`, DATEV's Rechnungsadresse block),
not on observed data. Both branches map it, so whichever export carries a
value first will fill `address_second_line`.

On import, both importing Moss and importing DATEV personal account data may
write these common columns, cf., [Importing](#importing).


## Fields with same information but distinct encoding

In these cases we keep both encodings, but chose a leading encoding which gets a
dedicated database column.

| Moss | DATEV | Relation | Stored — Moss side | Stored — DATEV side |
|---|---|---|---|---|
| `Type` = `COMPANY` | `Adressattyp` = `2` | Same meaning. DATEV codes (doc 1003221 field 7, there spelled "Adressatentyp"): `0` = keine Angabe, `1` = natürliche Person, `2` = Unternehmen (default). All 88 rows carry `2`. Note this says *company vs. natural person*, it does not say Kreditor. Moss API enum: only supplier objects, always companies here. | `moss_type` (enum verbatim) | `other_datev_columns["Adressattyp"]` |
| `Payment Method` = `SEPA` | `Zahlungsträger` = `7` | DATEV codes (field 136): blank/`0` = per master data, `7` = SEPA-Überweisung mit einer Rechnung, `8` = SEPA-Überweisung mit mehreren Rechnungen, `9` = keine Überweisungen, Schecks. 79 of 88 rows carry `7`; 9 rows have no Zahlungsträger despite Moss `SEPA`. | `moss_default_payment_method` (value verbatim) | `other_datev_columns["Zahlungsträger"]` |
| *(Moss API `id`, a UUID)* | `Nummer Fremdsystem` | **The sync's foreign key**: first 15 characters of the Moss supplier UUID (field 220 is `Text 15`). Populated on 77/88 rows — the remainder were presumably created before the sync or manually in DATEV. | `moss_uuid` — currently always empty, the CSV export does not carry the UUID | `datev_nummer_fremdsystem` |


## Derived / redundant DATEV fields

* `Kunden-/Lief.-Nr.` simply repeats `Konto` in the available data set (81/81
  where set).
* `Kurzbezeichnung` is `Name` truncated to 15 characters (78/88; field is `Text
  15`). It is stored as `datev_short_name`, which is a DATEV artifact that at
  the moment is distinct from the Hitobito-specific `short_name`.  Like every
  free-text column a DATEV import writes, it is compared transliteration-aware
  (see [datev_cp1252.md](datev_cp1252.md)).
* Structurally filled on all 88 rows, but with one constant value — no
  information: `Skonto in Prozent (Debitor)`, `Kreditoren-Skonto 1/2/4/5 %`,
  `Mahngebühr 1–3`, `Verzugspauschale 1–3` (all `0,00`), plus `Insolvent` and
  `Zahlungsbedingung` (both `0`, i.e. "nein" and "no payment-term key
  assigned"). Note the counting rule above: `0,00` counts towards the 49
  populated fields, `0` does not.


## Fields that exist in only one system (and are populated)

**DATEV only** (kept verbatim in `other_datev_columns` by the DebKred import
branch):

* **Bank account blocks 1–5** (`IBAN-Nr. 1..5`, `SWIFT-Code 1..5`,
  `Bankbezeichnung n`, `Bankleitzahl n`, `Länderkennzeichen n`, `Kennz.
  Hauptbankverb. n`). Moss stores exactly one IBAN/BIC, DATEV offers five slots
  — but **no supplier here actually has a second bank account**: 54 of 88 fill
  exactly one slot, 29 fill none, and the 5 filling 2–5 slots repeat **the same
  IBAN** in every slot (0 of 5 carry distinct IBANs). The extra slots are sync
  duplicates, not additional accounts. `Kennz. Hauptbankverb.  n` marks the slot
  payments use, and that is always the last filled one.  Only that slot is
  trustworthy: for the three creditors with a foreign bank (accounts 700027,
  700072, 700081) it carries the real `Länderkennzeichen` (AT, PL, IT) and the
  only `Bankbezeichnung`, while the earlier duplicate slots claim `DE` for a
  byte-identical IBAN.
* `EU-Land` / `EU-UStID` — a **USt-IdNr only**, split into country prefix and
  number (10 of 88 rows). Moss stores its counterpart concatenated in one field,
  which also accepts non-VAT tax numbers — see `Vat ID` below.
* `Adressart` = `STR` (address is a street address) and `Kennz.
  Korrespondenzadresse` = `1` — both on the same 4 rows; the other 84 rows have
  an empty `Adressart` and `Kennz. Korrespondenzadresse` = `0`.
* Present in the format but genuinely empty on all 88 rows (worth knowing):
  `SEPA-Mandatsreferenz 1..10`, the natürliche-Person name fields, `Sprache`,
  the individual fields (`Indiv. Feld 1..15`), and `Abw. Kontoinhaber 1..10`.

**Moss only** (already covered by our schema):

| Moss column | Meaning (per [Moss API](https://developers.getmoss.com/api/get-supplier-by-id)) | Our column |
|---|---|---|
| `Status` (`ACTIVE`/`DEACTIVATED`; API enum also `DELETED`) | supplier lifecycle in Moss: 79 active, 9 deactivated | `moss_status` |
| `Vat ID` | Tax identifier of the supplier (API `vatIdNo`). **Not reliably a VAT id**: Moss accepts whatever is entered. 19 of 88 rows are populated; 10 of those are a real USt-IdNr and equal DATEV's `EU-Land` + `EU-UStID` concatenated (10/10 verified). The other 9 have no DATEV counterpart at all (`EU-UStID` empty, because that field only ever holds a USt-IdNr): 5 are a German *Steuernummer* in slash notation (`12/345/67890` and variants), the remaining 4 are bare digit strings of 9–11 digits with no separator. So treat the DATEV correspondence as conditional, and do not parse the first two characters as a country code without checking. | `moss_vat_id` |
| `Expense account` / `Expense account code` | default expense sub-category (API `defaultExpenseAccountId`, resolved to name/number) | `moss_default_ledger_account_number` (code; the name goes to `other_moss_columns`) |
| `Cost Center Name`/`Cost Center Number` | default cost center (API `defaultCostCenterId`) | `moss_default_cost_center_number` (the name goes to `other_moss_columns`) |
| `Cost Carrier Name`/`Cost Carrier Number` | default cost carrier = our tax sphere (API `defaultCostCarrierId`) | `moss_default_sphere_number` (the name goes to `other_moss_columns`) |
| `Team Name` | default team (API `defaultTeamId`) — Moss concept, absent in DATEV | `moss_default_team_name` |
| `VAT Code`/`VAT Rate`/`VAT Name` | default VAT rate (API `defaultVatRateId`, resolved) | `other_moss_columns` |
| `Payment term - Number`/`- Description` | default payment terms (API `paymentTermId`, resolved) | `other_moss_columns` |
| `Account Holder Name` | bank account holder if it differs from the supplier name. DATEV has per-bank equivalents (`Abw. Kontoinhaber 1..10`), unpopulated here, so there is nothing to reconcile — hence the `moss_` prefix. | `moss_account_holder_name` |
| `Currency` | Supplier default currency (API `currency`, ISO 4217): EUR on 78, PLN on 2, empty on 8 of 88. Worth keeping: the two PLN suppliers are **exactly** the creditors of our four foreign-currency bookings, so the field predicts where `transaction_currency ≠ base_currency` occurs. DATEV has no counterpart — its DebKred field `Währungssteuerung` is unused in our data. | `moss_default_currency` |

The second address line is not listed here: both systems have the field (Moss
`Second line`, DATEV `Adresszusatz (Rechnungsadresse)`), both branches map it
onto `address_second_line`, and both are empty on all 88 rows — see the
[Common fields](#common-fields) table, footnote ².


## Importing

Both DATEV and Moss data is fed into the same table. The import upserts on the
account number and derives `account_type` (`CREDITOR`/`DEBITOR`) from the number
range. Each writes **only its own** columns: the DATEV branch never touches
`moss_*` / `other_moss_columns`, the Moss branch never touches `datev_*` /
`other_datev_columns`, and neither touches the Hitobito-owned `short_name`,
`aliases`, `description`, `comment`, `visibility`, `represented_person_id` and
`additional_info`
(`display_short_name` — short_name falling back to name — is generated by the
database and cannot be written at all). Fields without a dedicated column are
preserved verbatim in the respective JSONB column `other_*_columns`, keyed by
their original header, so nothing an export ships is silently dropped.

The two branches deliberately differ in how they treat the **shared** text
fields (`name`, `street`, `address_second_line`, `city`):

* **Moss import — plain overwrite.** Moss stores Unicode and is the system of
  record for suppliers, so a differing value simply wins. Because the two
  systems are kept in sync, a difference is also a signal: the import logs it
  as suspected sync drift before applying it.
* **DATEV import — transliteration-aware.** A DATEV export is CP1252 and
  cannot carry characters outside that charset, so `Gdańsk` arrives as
  `Gdansk`. Details about this issue and the handling are described in
  [datev_cp1252.md](datev_cp1252.md). The protection covers **every free-text
  column the DATEV branch writes**, `datev_short_name` and the values inside
  `other_datev_columns` included.


## Consequences for our model

* Only the columns both systems genuinely share stay unprefixed: `number`,
  `name`, `iban`, `bic`, `street`, `address_second_line`, `post_code`, `city`
  and `country` — either import may write them.
* Everything a single system owns carries its prefix — `moss_status`,
  `moss_type`, `moss_vat_id`, `moss_default_currency`,
  `moss_default_payment_method`, `moss_account_holder_name`, `moss_default_*` on
  the one side, `datev_short_name` and `datev_nummer_fremdsystem` on the
  other. `moss_uuid` is reserved for the full supplier UUID once the Moss API is
  used; the CSV export does not contain it.
* Unmapped extra fields land in `other_moss_columns` / `other_datev_columns`
  keyed by the original header, so nothing an export ships is silently dropped.
* The DATEV bank slots 2–5 need no model of their own: in the current data they
  only ever duplicate `IBAN-Nr. 1`, so `iban` / `bic` lose nothing.  They
  survive inside `other_datev_columns`. Should a supplier ever gain a genuinely
  second account, that assumption has to be rechecked — the marker to watch is
  `Kennz. Hauptbankverb. n` pointing at a slot with a different IBAN.
* All 88 personal accounts are Kreditoren today. Debitoren (`1xxxxx`–`6xxxxx`,
  `account_type = 'DEBITOR'`) are prepared for in the schema (CHECK constraints,
  `account_ref_type` routing in `datev_bookings`) but unused.
