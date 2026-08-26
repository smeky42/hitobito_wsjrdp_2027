# Handling Text in DATEV Exports in CP1252 Encoding

Every DATEV ASCII/DTVF export we receive (Buchungsstapel,
Debitoren/Kreditoren, Kontenbeschriftungen) is encoded in
**Windows-1252 (CP1252)**, a single-byte charset. We observed, that
characters outside it arrive **transliterated to their base letter**.

DATEV's own documentation states the charset but not the conversion:

* Field-description document
  [1003221](https://apps.datev.de/help-center/documents/1003221),
  ch. 2, lists `Zeichensatz: ANSI` (i.e. CP1252) for **all seven**
  format categories — Buchungsstapel, Debitoren/Kreditoren,
  Sachkontenbeschriftungen, and the rest.
* The [DATEV Developer
  Portal](https://developer.datev.de/de/file-format/details/datev-format/getting-started),
  section *Zeichensatz*, on the **import** direction: *"Der
  Default-Zeichensatz für den Import nach DATEV Rechnungswesen ist der
  Standard ISO-8859-1 bzw.  CodePage 1252. Zusätzlich kann DATEV
  Rechnungswesen auch die Unicode-Standards (UTF-8, -16, -32)
  interpretieren, sofern die ByteOrderMark (BOM, gilt auch für UTF-8)
  mitgeliefert wird."* — with the caveat that Unicode works only via
  the manual import or the `accounting:extf-files` online API; the
  KrStaPv console app does not support it.

> **The transliteration itself is undocumented — and so is DATEV's
> internal storage.** Neither source describes what DATEV does on
> **export** with a character CP1252 cannot represent, nor in which
> encoding it keeps the value in the first place. That `ą → a`,
> `Ś → S`, `ń → n` is an **observed** property of our own exports, not
> behaviour DATEV specifies or guarantees. Treat the rule below as a
> robust heuristic, not a contract — and if a comparison ever behaves
> oddly, re-check the assumption against fresh export data.

Note: Our own exports are not affected. When we *write* DATEV files we
default to UTF-8 with BOM, which DATEV reads per the quote above, so
nothing is transliterated on the way out. The CP1252 writer path
exists only to reproduce a genuine DATEV export byte-for-byte (the
synthetic 2025 Buchungsstapel), and only that path applies the
transliteration.

Our database is UTF-8 and Moss stores full Unicode, so the *same*
value can legitimately look different depending on where it came from:

| Origin | Value |
|---|---|
| Moss (Unicode, correct) | `ZHP Chorągiew Gdańska` |
| DATEV export (CP1252) | `ZHP Choragiew Gdanska` |

Note what is **not** affected: German umlauts and most
Western-European accents (`ä ö ü ß é à ç ñ`) exist in CP1252 and
survive unchanged. The problem is limited to characters outside it. We
are most affected by Polish (`ą ć ę ł ń ó ś ź ż`), but could be
affected by much more (Czech, Hungarian, Turkish, Greek and Cyrillic,
…)


## Failure Modes to Avoid

A naive importer may compare the incoming DATEV string with the stored
value, finds them different, and updates the row, silently replacing
the correct Unicode name with its ASCII-ified version.


## Dealing with DATEV Texts

**Never compare a DATEV text against a stored text directly. A DATEV
text counts as unchanged when it equals the stored text, or equals the
stored text transliterated.**

```
datev == stored                         ->  unchanged, keep stored
datev == to_win1252_compatible(stored)  ->  unchanged, keep stored
otherwise                               ->  changed, store the DATEV value
```

The check is **deliberately asymmetric**: only the *stored* side is
transliterated, never the incoming one. That is what makes an upgrade
possible. Should DATEV ever export the full character set, an incoming
`Gdańsk` against a stored `Gdansk` does *not* match, so the import
writes the richer value instead of silently keeping the poorer one. A
symmetric comparison would call the two equal and freeze our data at
the reduced form forever.

Together the two directions form a ratchet:

| stored | from DATEV | result |
|---|---|---|
| `Gdańsk` | `Gdansk` | unchanged — the export is just reduced, keep `Gdańsk` |
| `Gdańsk` | `Gdańsk` | unchanged |
| `Gdansk` | `Gdańsk` | **changed** — upgrade to `Gdańsk` |
| `Gdańsk` | `Danzig` | changed — a real rename |

The stored value can therefore only ever move toward the richer
representation, and alternating CP1252 and Unicode exports do not make
it oscillate.

One case is accepted knowingly: if someone deliberately edits a name in
DATEV *down* to its ASCII form, we treat that as the transliteration
artefact it is indistinguishable from, and keep our richer value.

A helper function for the import implements this check. Underneath it
tries to reproduce the transliteration in DATEV's exports. Note: This
is based on our limited observations.  Characters encodable in CP1252
pass through, everything else is reduced to its base character via
Unicode NFD decomposition, with an explicit fallback table for letters
whose diacritic is part of the glyph and therefore does not decompose
(`ł → l`, `đ → d`, `ẞ → SS`, …).


## Affected Fields

**Every free-text value an import of DATEV data writes**. This needs
to be done always, as we do not knoe how DATEV stores text
internally. What we observe is just an export. Our logic covers all
bases:

* DATEV stores CP1252 internally — then a value entered with Polish
  diacritics was flattened on the way *in*, and DATEV's own value is
  permanently the reduced one;
* DATEV stores Unicode and only reduces on export — then the file we
  read understates what DATEV actually holds, and the same field may
  arrive in full Unicode through a different channel.
* DATEV stores a mixture of CP1252 and Unicode. Even in this case
  nothing breaks and the import could handle Unicode, where DATEV
  stores it.

This includes the raw-export JSONB columns (`other_datev_columns`):
they hold export content verbatim, so their string values need the
same key-by-key comparison as a dedicated column.

Applied today:

| Table | Columns |
|---|---|
| `wsjrdp_personal_accounts` | `name`, `street`, `address_second_line`, `city`, `datev_short_name`, plus every string in `other_datev_columns` |
| `wsjrdp_ledger_accounts` | `name`, `datev_purpose`, plus every string in `other_datev_columns` |

The same treatment is due wherever a further DATEV import lands — the
rule belongs to the *source*, not to a particular table.

It does **not** apply to:

* **codes, enums and technical identifiers** — account numbers,
  `account_type`, `country` (ISO), `post_code`, `iban`, `bic`,
  `datev_nummer_fremdsystem` (a UUID prefix), the numeric
  `datev_function_*` fields: no character outside ASCII can occur, so a
  plain comparison is already correct;
* **`moss_*` columns** — written only from Moss data, which is Unicode,
  and with no DATEV field to compare against there is nothing to
  protect;
* **values coming *from* Moss** in general — Moss stores Unicode and may
  overwrite freely.


## DATEV Fields with Length Limits

DATEV fields have hard length limits (Debitoren/Kreditoren: `Name` 50,
`Kurzbezeichnung` 15 characters — see DATEV document
[1003221](https://apps.datev.de/help-center/documents/1003221),
chapter 6). A long name therefore arrives truncated, which is the same
trap in a different guise: the incoming value is a *prefix* of the
stored one, not a change. Where a field is at its DATEV maximum, treat
"stored value starts with incoming value" as equal rather than as an
update.


## Mojibake

The CP1252 Transliteration issue is not to be confused with
**mojibake**, CP1252 bytes that were decoded as UTF-8 or vice versa,
producing, e.g., `Ã¶` where `ö` was meant. When it is known or
detectable, the respective import from DATEV shall repair this on read
(the special cased 2025 Primanota import does this for participant fee
bookings).
