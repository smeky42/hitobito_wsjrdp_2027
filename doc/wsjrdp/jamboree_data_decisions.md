# Jamboree data: decisions against the organizer's template

The page "Daten für den Veranstalter" (`Person::JamboreeDataController`,
`Wsjrdp2027::Person::JamboreeData`, answers in the jsonb column
`people.jamboree_data`) collects what the organizer asks for in its bulk
import template (Accredit Solutions, `Template.XLSX`, sheet "Import Data").
This document records where we deliberately differ from that template: what
we do not ask, what we ask but do not pass on, and how stored values map to
the template. Column letters refer to the "Import Data" sheet.

Each entry names the field as the UI shows it (German) and as Ruby knows it.

## Not asked

| Template column | UI | Ruby | Why |
|---|---|---|---|
| Q "Religion(s)" | – | – | Not filled in for the organizer. |
| S "Please state your National Identity Number (if applicable)" | – | – | Not filled in for the organizer. |

## Asked, but only for the contingent

These answers stay with us; the export leaves them out.

| UI | Ruby | Note |
|---|---|---|
| Tracht- bzw. Klufthemdgröße | `uniform_size` | Our uniform order. |
| Kluft Ärmellänge | `uniform_long_sleeve` | Empty means Langarm: the forms preselect it, and "nicht gewählt (=Langarm)" is shown. Count orders with `IS NOT FALSE`. |
| Kluft bestellen | `uniform_order` | Asked only where `uniform_order_available?` (`wsjrdp_role` CMT, UL, IST or BMT). Empty means Ja, shown as "nicht gewählt (=Ja)"; count with `IS NOT FALSE`. |
| Kopfbedeckung | `headgear` | Our equipment. |
| Angaben sind vollständig und wahrheitsgetreu | `jamboree_data_confirmed` | Our confirmation; the organizer's own consent is column B (see `gdpr_agreement` below). |
| T-Shirt Größe (for YP) | `shirt_size` | Asked of everyone, but template column BE "T-Shirt Size WSJ" is for adults only: the export passes it on for adults alone. |

## Mapped values

### Travel document type (columns BW, BX)

| UI | Ruby `travel_document_type` | `travel_document_other` | Template BW / BX |
|---|---|---|---|
| Reisepass | `ordinary_passport` | – | Ordinary passport |
| Personalausweis | `national_identity_card` | "National identity card" (set by the model, field not shown) | Other travel document (please specify) / National identity card |
| Amtlicher Pass | `official_passport` | – | Official passport |
| Diplomatenpass | `diplomatic_passport` | – | Diplomatic passport |
| Dienstpass | `service_passport` | – | Service passport |
| Sonderpass | `special_passport` | – | Special passport |
| Anderes Reisedokument (bitte angeben) | `other_travel_document` | as entered in "Welches andere Reisedokument" | Other travel document (please specify) / the text |

- The template has no identity card. We keep it as its own type so the form
  shows it again as "Personalausweis"; the export only has to map
  `national_identity_card` to "Other travel document (please specify)", BX is
  already stored (`NATIONAL_IDENTITY_CARD_TEXT`).
- `official_passport` used to be labelled "Personalausweis"; migration
  `20261013000100_official_passport_to_national_identity_card` turned every
  value stored until then into `national_identity_card`.
- "Welches andere Reisedokument" is required in the browser while shown
  (`required`; disabled, and so neither sent nor checked, while hidden). The
  server does not require it: a validation would run on every save of a person.

### Allergies (columns EG–FO)

| UI | Ruby | Template |
|---|---|---|
| per allergen: keine / mild / mittel / schwer | form: `allergy_<key>_level`; stored: `allergy_<key>` (boolean) and `allergy_<key>_severity` (`mild`, `medium`, `severe`) | "Do you have an allergy to …?" Yes/No and "What is your allergy severity …?" |
| – | derived: any `allergy_<key>` | EG "Do you have any allergies?" |

- `allergy_<key>_level` is not stored; it reads and writes the two stored keys.
- An allergen without allergy is not stored at all (the key is removed), so
  "keine" and "never answered" look the same. Both are exported as No.
- An allergy without severity can exist (from the earlier form); the form
  warns about it, and the export has no severity for it.
- The log names the box "Allergie Milch" and keeps the severity line as it is.

### Visa questions (columns CC–DA)

Asked only with "Visum benötigt" `visa_needed` = `yes_need_support`. With any
other answer the questions are hidden but the answers stay stored, so a slip
of the select loses nothing; the page and the export use them only with
`yes_need_support`. Likewise every text for Other (`travel_document_other`,
`visa_civil_status_other`, `visa_family_eu_citizen_relation_other`) stays when
its choice changes and is used only while the choice is Other (or, for
`travel_document_other`, a national identity card). A visa choice with a non-trivial term is
labelled with the template's English and a German translation,
"English (Deutsch)", so the answer matches the organizer's wording. Trivial
ones are German only: Ja/Nein, and "Andere (bitte angeben)" for Other;
"Visum benötigt" stays German too.

| UI | Ruby | Template | Values |
|---|---|---|---|
| Geschlecht wie im Reisedokument | `visa_gender_as_in_travel_document` | CI | `female`, `male`, `x` (Female, Male, X). Without an answer the form suggests it from `gender` (w, m, d). |
| Familienstand | `visa_civil_status` | CJ | `single`, `married`, `registered_partnership`, `separated`, `divorced`, `widowed`, `other` ("Andere (bitte angeben)"). |
| Welcher Familienstand | `visa_civil_status_other` | CK | Only with `other` (shown, required in the browser); kept otherwise. |
| Aktueller Studierendenstatus | `visa_current_student_status` | CL | `student`, `not_student`. |
| Familienangehörige mit EU-/EWR-/CH-Staatsangehörigkeit | `visa_family_eu_citizen_relationship` | CM | `yes`, `no` (Ja, Nein). |
| Art der familiären Beziehung | `visa_family_eu_citizen_relation` | CU | `spouse`, `child`, `grandchild`, `dependent_ascendant`, `registered_partnership`, `other` ("Andere (bitte angeben)"); only with `yes`, cleared otherwise. |
| Welche familiäre Beziehung | `visa_family_eu_citizen_relation_other` | CV | Only with `other` (shown, required in the browser); kept otherwise. |
| Wohnsitzland weicht von Staatsangehörigkeit ab | `visa_residence_other_than_nationality` | CW | Ja/Nein buttons storing `true`/`false`, nothing while unanswered (`VISA_YES_NO_ATTRS`; unlike the boxes, `false` is stored). Wohnsitzland `visa_residence_country` and Aufenthaltstitel und Nummer `visa_residence_permit` (CX) only with `true`, cleared otherwise. |
| Wurden bereits Fingerabdrücke … erfasst? | `visa_fingerprints_collected` | CZ | As above. Date and number only with `true`, cleared otherwise. |
| Datum der Fingerabdruckerfassung, Nummer des Visumaufklebers | `visa_fingerprints_date`, `visa_fingerprints_visa_number` | DA | One free text in the template: the date (dd.mm.yyyy) and the number joined, e.g. "04.05.2020, 123456"; either alone if the other is missing. |
| Staatsangehörigkeit bei Geburt | `visa_nationality_at_birth` | CG | Only if it differs from the country of birth (help text). |
| – (Visainformationen) | `visa_information` | CD | CD is a section heading in the template, not a field: no longer asked or shown, stored values stay. |

The questions follow the template's order (CG … DA), except that the EU family
question and its relation (CM, CU, CV) stay together before the employer
(CN–CT), where the template has the employer in between. A detail of a
Ja/Nein question (residence country, fingerprint date and number) is shown
only with Ja.

An empty choice is shown as "nicht gewählt". The country fields are
described under Countries.

### Countries

| UI | Ruby | Template | Mapping |
|---|---|---|---|
| Geburtsland | `country_of_birth` | O, CF | One country: ISO 3166 alpha-2 code (`COUNTRY_ATTRS`), chosen from the country list (`country_select_field`), shown as "Deutschland (DE)". |
| Staatsangehörigkeit | `nationality` | R | One country. Without an answer the form preselects the main nationality of the registration, the first of `passport_nationality` (`nationality_or_default`); it is stored only by saving the form. |
| Ausstellungsland | `travel_document_country` | CB | One country. |
| Staatsangehörigkeit bei Geburt | `visa_nationality_at_birth` | CG | One country; only if it differs from the country of birth. |
| Weitere Staatsangehörigkeiten | `visa_other_nationalities` | CH | Several countries (`COUNTRIES_ATTRS`): the codes as a comma-separated list, "AT, FR", chosen as `visa_other_nationalities_codes` (`country_multi_select_field`). Without an answer the form preselects the further nationalities of the registration, `passport_nationality` after the first (`visa_other_nationalities_codes_or_default`); stored only by saving the form. |
| Arbeitgeber / Bildungseinrichtung, Land | `visa_employer_country` | CT | One country. |
| Wohnsitzland, Aufenthaltstitel und Nummer | `visa_residence_country`, `visa_residence_permit` | CX | One country and a free text. CX is one free text asking for the country, the residence permit and its number: the export joins the country's name and the text, e.g. "<country>, <permit and number>". |
| Erstes Einreiseland im Schengen-Raum | `visa_schengen_first_entry` | CY | One country of the Schengen area only (`Wsjrdp::CountryLookup::SCHENGEN_CODES`). |

The template asks for every country but R as a free text, R from its own
list of nationalities; the export turns the stored codes into the text or
list entry the template wants.

- Saving turns a country name or nationality into its code
  (`Wsjrdp::CountryLookup.find_country_by_any_name`, `jsonb_accessor` with
  `cast: :country`, for a list `cast: :countries`); a value the lookup does
  not know is kept as it is.
- A name stored earlier is converted on the person's next save only, there is
  no mass update. Until then the form preselects its country and the page
  shows it as "Deutschland (DE)"; an unknown value stays a choice, marked
  "(nicht erkannt)", as does a stored country outside the Schengen area for
  the Schengen entry.
- The list finds a country by its German name, its code, its alpha-3 code and
  other names (`search_aliases`); a code or alias typed in full puts its
  country first.

### Other values

| UI | Ruby | Template | Mapping |
|---|---|---|---|
| Rufname / Namensschild | `known_as_name` | I "Known as name" | Empty: `known_as_name_or_default`, i.e. the nickname, else the first of the first names (`nickname_or_short_first_name`). |
| Datenschutzbestimmungen des Jamboree-Veranstalters akzeptiert | `gdpr_agreement` | B | Yes/No. |
| E-Mail | `email` (column of `people`) | Z | With `visa_needed` = `yes_need_support` the person's address may have to be sent, youth participants included (the template asks for it only for a visa). Everyone else: none, or a collective contingent address. |
| Patrol (tab "Patrols" of a unit) | `patrol` (column of `people`) | E "Patrol ID" | As stored; not on this page. |
| Essensgewohnheiten | `diet` (column of `people`) | ED/EE | Preselected "Allesesser" (`omnivorous`), as in the original registration; it is "No special diet". |
| Englisch … Arabisch: Lesen, Schreiben, Sprechen, Hörverstehen | `<language>_<skill>`, levels `none` … `native` | AG–AV | `none` is "Not reading/writing/speaking/listening", the others by name. Without an answer the form preselects "Keine". Languages other than English only for adults, as in the template. |
| Visum benötigt | `visa_needed` | CC | `no`, `yes_have_one` ("Visa exists"), `yes_need_support` ("Yes, I do need a Schengen visa"). Without an answer the form preselects "Nein". |
| An- und Abreise | `arrival_*`, `departure_*` | DD–DN | Same places and types as the template. UL and YP cannot edit them: central logistics books their journey. |
| Arbeitgeber oder Bildungseinrichtung | `visa_employer_name`, `visa_employer_address_1` | CN, CO | The template has address fields only (CO "address 1" … CT country), no name: CO gets the name before address 1, e.g. "<name>, <address 1>". |

## Log

The person log writes every answer of this page (the keys of
`jamboree_data` and `shirt_size`, `uniform_size`, `uniform_long_sleeve`,
`uniform_order`, `headgear`, `diet`) as stored, with its label in brackets
where the label differs: `severe [Schwere anaphylaktische Reaktion
(lebensbedrohlich)]`, `true [Langarm]`, `false [unwohl]`, `2027-07-30
[30.07.2027]`; a free text
as it is, and a value labelled just Ja or Nein too (`true`, `false`, `no`);
a country as its code alone (`DE`)
(`Wsjrdp2027::PaperTrail::VersionDecorator#jamboree_change`). An
allergy's box is named "Allergie <allergen>".
