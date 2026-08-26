# Moss-Datenmodell: Export aus Moss → Import in Hitobito

Wie kommen Finanzdaten aus **Moss** (getmoss.com, unser Ausgaben-/Wallet-Tool)
in die Hitobito-Buchhaltung dieses Wagons? Dieses Dokument sammelt

1. die **allgemeinen Regeln** (welche Extraktionswege gibt es?),
2. die **Moss-Entitäten** (deutscher + englischer Name, Hilfeseiten), und
3. je Entität, **ob und wie** ihre Daten extrahierbar sind (API / CSV-Builder +
   SFTP / Ad-hoc-Export), und wohin sie in Hitobito importiert werden.

> **Aktueller Stand WSJ (bestätigt):** Wir nutzen derzeit eine **Mischung aus
> CSV-Builder und manuellem Ad-hoc-Download**; die **Public API** wird evtl.
> später ergänzt. Der endgültige Weg ist noch nicht festgelegt.

> **Wichtig zum Status:** Dokumentiert ist nur, wofür es **Belege** gibt; die
> Quelle steht jeweils als Link dabei. Offene Punkte sind als
> **❓ offene Frage** markiert. Bitte nichts als gesichert lesen, was hier nicht
> mit Quelle belegt ist.
>
> Konkrete Export-**Beispieldateien** liegen (sobald vorhanden) unter
> [`doc/moss_export_examples/`](moss_export_examples/) — dieses Verzeichnis ist
> per `.gitignore` ausgenommen (kann echte Buchungsdaten enthalten und gehört
> **nicht** ins öffentliche Repo).

## Quellen

- Moss Public API / Datenmodell: <https://developers.getmoss.com/>
  - Datenmodell-Übersicht: <https://developers.getmoss.com/data-model/>
  - Anwendungsfälle / Endpunkt-Liste: <https://developers.getmoss.com/use-cases/>
- CSV-Feldreferenz (**Deutsch**):
  <https://help.getmoss.com/de/articles/11703042-csv-feldreferenz-und-tipps-zur-anpassung#h_e86ce8863d>
- CSV field reference (**Englisch**):
  <https://help.getmoss.com/en/articles/11703042-csv-field-reference-and-customization-tips#h_e050825b85>
- Geplante/automatisierte SFTP-Auslieferung (Produktseite):
  <https://www.getmoss.com/integrations/sap-csv>
- **Buchungslogik Moss-Kartenzahlungen → DATEV Unternehmen Online** (3-Schritt-Kette):
  <https://help.getmoss.com/de/articles/7041394-buchungslogik-moss-zahlungen-datev-unternehmen-online>
- Wagon-Schema: [`db/schema.rb`](../db/schema.rb) (Tabelle `moss_balance_movements`),
  Migration [`db/migrate/20260411000100_add_moss_balance_movements.rb`](../db/migrate/20260411000100_add_moss_balance_movements.rb),
  Model [`app/models/moss_balance_movement.rb`](../app/models/moss_balance_movement.rb)
- **Lokale OpenAPI-Spec** (maßgeblich für Endpunkte/Felder):
  [`doc/moss_export_examples/openapi_spec/openapi.yaml`](moss_export_examples/openapi_spec/openapi.yaml)
  (+ `schemas/…`).

---

## Wie extrahiere ich Infos aus der Moss-Doku (ohne API-Calls)

> ⛔ **Keine Moss-API-Calls.** Für Agenten und Skripte in diesem Wagon gilt:
> **niemals** die Moss-API aufrufen — kein `POST /oauth2/token`, keine
> `/v1/...`-Requests, keine Live-Zugriffe auf `public-api.getmoss.com`, auch
> nicht lesend/zu Testzwecken. Der API-Zugang nutzt **echte Produktions-
> Credentials** gegen echte Finanzdaten. (Dieselbe Regel steht in
> [`AGENTS.md`](../AGENTS.md).)

Erlaubte Informationsquellen — in dieser Reihenfolge:

1. **Lokale OpenAPI-Spec** (`doc/moss_export_examples/openapi_spec/`): die
   **maßgebliche** Quelle für Endpunkte, Request-/Response-Schemata und
   Feldnamen. `openapi.yaml` enthält den `paths:`-Block; Schemata liegen unter
   `schemas/<bereich>/<Name>.yaml` (z. B.
   `schemas/bank_transaction/BankTransaction.yaml`).
2. **Developer-Doku im Browser** — erlaubt **nur** auf der Domain
   `https://developers.getmoss.com/` (nicht verlassen). Mit **WebFetch** lesbar.
   Nützliche Seiten:
   - Übersicht/Datenmodell: `/`, `/data-model/`, `/use-cases/`
   - **Pro-Operation-Seiten**: `/api/<operation-in-kebab-case>`, z. B.
     [`/api/search-bank-transactions`](https://developers.getmoss.com/api/search-bank-transactions).
     Die `<operation>` = `operationId` aus der Spec in kebab-case
     (`searchBankTransactions` → `search-bank-transactions`). Diese Seiten geben
     eine gute Übersicht, sind aber teils **gekürzt** — im Zweifel die lokale
     Spec heranziehen.
3. **Help-Center** (`https://help.getmoss.com/`, DE/EN) für die CSV-Exporte
   (Feldreferenz), s. Abschnitt 3.

---

## 1. Allgemeine Regeln: die drei Extraktionswege

Es gibt (mindestens) drei Wege, Daten aus Moss herauszubekommen. Für **jede**
Entität ist zu klären, welche davon möglich/genutzt sind.

### A) Public API

REST-API, versioniert unter `/v1`. **⛔ Nicht aufrufen** (siehe „Wie extrahiere
ich Infos aus der Moss-Doku" oben) — hier nur zur Dokumentation der Struktur.
Quelle: lokale OpenAPI-Spec + <https://developers.getmoss.com/>

- **Basis-URL:** `https://public-api.getmoss.com/v1`
- **Auth:** OAuth 2.0 *client credentials* (API Key ID `kid_…` + Secret `sk_…`
  → Bearer-Token via `POST /oauth2/token`, Token ~1 h gültig). API-Keys können
  nur Admins anlegen.
- **Methoden:** `GET` (lesen), `POST` (anlegen), `PATCH` (teil-aktualisieren).
- **Rate-Limits:** lesend 180 req/min, schreibend 20 req/min.
- **Zeitfilter** zum inkrementellen Abholen, z. B. bei Suppliers
  `create_date__gte`, `create_date__lte`, `update_time__gte`, `update_time__lte`;
  Expenses via `page` / `page_size` paginiert.

Quelle: <https://developers.getmoss.com/use-cases/>

### B) CSV-Builder + automatischer Upload (Scheduled Data Transfer / SFTP)

Moss hat einen **CSV-Builder**: man baut aus den verfügbaren Feldern eine
Export-Vorlage (Empfehlung laut Doku: mit Preset **„Generic CSV"** starten, das
alle Felder enthält, und dann Spalten entfernen). Felder lassen sich per Formel
kombinieren (`${fieldName1} und ${fieldName2}`); die Soll/Haben-Kennzeichen
heißen per Default **„Haben"/„Soll"** und lassen sich nur über den Support
umbenennen.
Quelle:
[CSV-Feldreferenz (DE)](https://help.getmoss.com/de/articles/11703042-csv-feldreferenz-und-tipps-zur-anpassung),
[CSV field reference (EN)](https://help.getmoss.com/en/articles/11703042-csv-field-reference-and-customization-tips).

Diese Vorlagen können **automatisch per Scheduled Data Transfer (SFTP)** an einen
Zielserver ausgeliefert werden (Frequenz einstellbar; Datensätze wählbar).
Quelle: <https://www.getmoss.com/integrations/sap-csv>.

> **Stand WSJ:** Der CSV-Builder wird genutzt; ob die Auslieferung per **SFTP**
> automatisiert läuft oder die Vorlagen manuell heruntergeladen werden, ist noch
> nicht abschließend entschieden (aktuell Mischbetrieb mit Weg C).

### C) Ad-hoc-Export aus der Moss-Oberfläche

Manueller Download einer CSV/Datei direkt aus dem Moss-UI (ohne CSV-Builder-Vorlage
/ ohne SFTP). **Diesen Weg gibt es und wir nutzen ihn** (bestätigt). Beim Ad-hoc-
Export lässt sich zusätzlich ein **Format** wählen (Standard-CSV in der jeweiligen
UI-Sprache, oder ein DATEV-Paket).

**Namenskonvention der Beispieldateien** (unter
[`doc/moss_export_examples/`](moss_export_examples/)): Präfix = Entität, Suffix =
gewählte Export-Auswahl. Beispiel für die Entität *Kontobewegungen*:

| Dateiname (Muster) | Export-Auswahl |
| --- | --- |
| `balance-movements_<datum>_EN.csv` | Standard-Ad-hoc-CSV, **englische** UI/Spalten |
| `balance-movements_<datum>_DE.csv` | Standard-Ad-hoc-CSV, **deutsche** UI/Spalten |
| `balance-movements_<datum>_custom_csv_builder.csv` | **Custom-CSV** aus dem CSV-Builder (Weg B) |
| `balance-movements_<datum>_DATEV.zip` | **DATEV-Paket** (DATEV-XML, siehe unten) |

Für **Kartentransaktionen** (Präfix `transactions_`) gibt es zusätzliche
Formate/Beilagen (s. 5.2.1):

| Dateiname (Muster) | Export-Auswahl |
| --- | --- |
| `transactions_<datum>_EN.csv` / `_DE.csv` | Standard-Ad-hoc-CSV (EN/DE) |
| `transactions_<datum>_WSJ27.csv` | **Custom-CSV (CSV-Builder)**, WSJ-Format (94 Spalten, Superset; s. 5.2.7) |
| `transactions_<datum>_DATEV.csv` | Ad-hoc **DATEV-CSV** (EXTF-Buchungsstapel, ohne EXTF-Kopfzeile) |
| `transactions_<datum>_Addison.csv` | Ad-hoc **Addison/DATEV** (EXTF-Buchungsstapel **mit** EXTF-Kopfzeile) |
| `transactions_<datum>_attachments.zip` / `_attachments/` | Beleg-**Sammel-PDF** je Transaktion (`<Transaction-ID>.pdf`) |
| `transactions_<datum>_receipts.zip` / `_receipts/` | **Einzelbelege** (in `Invoice File Name` referenziert) |

> **Beispiele nötig für die übrigen Entitäten:** Für jede weitere per Export
> extrahierbare Entität (Transaktionen, Rechnungen, Rückerstattungen)
> bitte je Format ein Beispiel nach `doc/moss_export_examples/` legen. Sobald
> Beispiele vorliegen, wird das jeweilige Format hier dokumentiert.
> ❓ Für **welche weiteren Entitäten** gibt es einen Ad-hoc- bzw. DATEV-Export?

---

## 2. Moss-Entitäten (Datenmodell)

Das API-Datenmodell nennt **13 Kern-Entitäten**.
Quelle: <https://developers.getmoss.com/data-model/>. (Deutsche Namen, soweit
in der CSV-Feldreferenz belegt, sind ergänzt; sonst als „—" markiert.)

| Entität (EN) | Entität (DE) | Kurzbeschreibung (Quelle: data-model) |
| --- | --- | --- |
| **Bank Account** | Moss-Wallet / Bankkonto | Von der Organisation gehaltenes Moss-Wallet; Status `ACTIVE`/`CLOSED`, Funding `CREDIT`/`DEBIT`. |
| **Bank Transaction** | Kontobewegung¹ | Geldbewegung auf einem Moss-Konto: `CARD`, `PAYOUT`, `WITHDRAWAL`, `TOP_UP`, `REPAYMENT`. |
| **Expense** | Ausgabe | Ein Ausgabenposten (Kartentransaktion, Rechnung oder Rückerstattung) inkl. Buchungsattributen; in Positionen (line items) splitbar. |
| **Expense Account** | Sachkonto | Sachkonto/Kontenrahmen-Position, auf die eine Ausgabe gebucht wird (z. B. Travel, Software). |
| **Dimension** | Dimension | Tagging-Achse für mehrdimensionale Buchhaltung; fix: **Cost Center** + **Cost Carrier**, plus eigene. |
| **Dimension Item** | Dimensionswert | Einzelner Wert innerhalb einer Dimension (z. B. „Project A"). |
| **Department** | Abteilung | Übergeordnete Org-Einheit aus mehreren Teams. |
| **Team** | Team | Org-Einheit innerhalb der Organisation (Gruppierung, Freigabe-Workflows). |
| **User** | Nutzer\*in | Person mit Moss-Account. |
| **Organisation** | Organisation | Rechtliche Einheit / Firmenkonto in Moss (oberster Scope). |
| **Supplier** | Lieferant / Kreditor | Kreditor, an den Zahlungen/Rechnungen gehen. |
| **Tax Rate** | Steuersatz | USt/Steuer-Behandlung (Prozent, Code, Land). |
| **Payment Term** | Zahlungsbedingung | Vereinbarte Fälligkeitsbedingungen einer Rechnung. |
| **File** | Datei / Beleg | An eine Ausgabe angehängtes Dokument. |

¹ „Kontobewegung" ist über den CSV-Export-Namen abgeleitet (Abschnitt 3,
Kontobewegungen/Balance Movements); die API-Entität heißt **Bank Transaction**
(`POST /v1/bank-transactions/search-query`). API-*Bank Transaction* und
CSV-*Balance Movement* sind **nicht** dieselbe Datenmenge: `BankTransaction` ist
schlank (Betrag/Datum/Typ/Gebühren), die Buchhaltungsfelder des CSV stammen aus
`Expense`. Details in **5.1.4**.

### Expense-Typen & Status (Quelle: data-model)

- **Expense-Typen:** Card Transaction (`EXPENSE`/`REFUND`/`CASHBACK`),
  Invoice (`EXPENSE`/`CREDIT_NOTE`), Reimbursement (`EXPENSE`).
- **Lifecycle-Status:** `DRAFT`, `SUBMITTED`, `REVIEWED`, `APPROVED`, `REJECTED`,
  `FLAGGED`, `APPROVAL_SKIPPED`, `VERIFIED`, `VERIFICATION_SKIPPED`, `COMPLETED`,
  `DELETED`, `INHERITED`, `UNKNOWN_DEFAULT_OPEN_API`.
- **Line-Item-Subtypen:** `MAIN` (Standard) / `CORRECTION` (negative Korrektur).
- Alle Ressourcen: ISO-8601-Zeitstempel `createTime`/`updateTime`/`deleteTime`,
  Scope über `organisationId`.

### API-Endpunkte (vollständig)

Quelle: **lokale OpenAPI-Spec** `paths:`-Block
(`doc/moss_export_examples/openapi_spec/openapi.yaml`). **⛔ Nur Referenz — nicht
aufrufen.** Der `operationId` ist zugleich der kebab-case-Slug der
Developer-Doku-Seite `/api/<operation>`.

| Methode & Pfad | operationId | Zweck |
| --- | --- | --- |
| `GET /v1/expenses` | `getExpenses` | Ausgaben (Kartentransaktionen, Rechnungen, Rückerstattungen) inkl. Buchungsattribute. |
| `GET /v1/expense-accounts` · `/{id}` | `getAllExpenseAccounts` · `getExpenseAccountById` | Sachkonten (Kontenrahmen). |
| `GET /v1/dimensions` · `POST` · `GET/PATCH /{id}` | `getAllDimensions` · `createDimension` · `getDimensionById` · `updateDimension` | Dimensionen (Kostenstellen/-träger, eigene). |
| `GET /v1/dimensions/{id}/items` · `POST` · `GET/PATCH /{itemId}` | `getAllDimensionItems` · `createDimensionItem` · `getDimensionItemById` · `updateDimensionItem` | Dimensionswerte. |
| `GET /v1/suppliers` · `POST` · `GET/PATCH /{id}` | `getAllSuppliers` · `createSupplier` · `getSupplierById` · `updateSupplier` | Kreditoren-Stammdaten. |
| `GET /v1/payment-terms` · `/{id}` | `getAllPaymentTerms` · `getPaymentTermById` | Zahlungsbedingungen. |
| `GET /v1/tax-rates` · `/{id}` | `getAllTaxRates` · `getTaxRateById` | Steuer-/USt-Sätze. |
| `GET /v1/users` · `/{id}` | `getAllUsers` · `getUserById` | Nutzer\*innen. |
| `GET /v1/teams` · `/{id}` | `getAllTeams` · `getTeamById` | Teams. |
| `GET /v1/departments` · `/{id}` | `getAllDepartments` · `getDepartmentById` | Abteilungen. |
| `GET /v1/bank-accounts` | `getAllBankAccounts` | Moss-Wallets/Bankkonten. |
| `GET /v1/bank-accounts/{id}/balance` | `getBankAccountBalance` | Kontostand eines Wallets. |
| `POST /v1/bank-transactions/search-query` | `searchBankTransactions` | **Kontobewegungen** (Geldbewegungen auf Moss-Wallets); Filter u. a. `bookingDateFrom/To`, `accountIds`. |
| `POST /v1/files/search-query` | `searchFiles` | Dateien/Belege zu Ausgaben suchen. |
| `GET /v1/files/{fileId}/content` | `downloadFile` | Beleg-/Dateiinhalt (PDF, Bild) herunterladen. |

Die Spec enthält weitere Schema-Bereiche ohne öffentlichen Pfad in diesem
`paths:`-Block (u. a. `accounting_event`, `reconciliation_*`,
`general_ledger_account`, `accounting_period`, `document`) — für unseren
Export/Import derzeit nicht relevant, aber in `schemas/` vorhanden.

---

## 3. CSV-Export-Typen (CSV-Builder)

### 3.1 Unterstützte Format-Optionen (Stand August 2026)

Im CSV-Builder wählt man beim Anlegen eines Formats unter **„Format"** die zu
exportierende Entität. **Stand August 2026** stehen u. a. folgende Formate zur
Auswahl (Quelle: Nutzerangabe / CSV-Builder-UI Format-Dropdown; der Screenshot in
3.2 zeigt nur den gewählten Wert „Konto-Bewegungen"):

| Format (DE, UI) | Entität (EN) | Feldreferenz belegt? | Hinweis |
| --- | --- | --- | --- |
| **Transaktion** | **Transaction** (Kartentransaktion) | ja (Feldgruppen s. u.) | |
| **Rückerstattung** | **Reimbursement** | ja | |
| **Rechnung** | **Invoice** | ja | |
| **Konto-Bewegung** | **Balance Movement** | ja (vollständig: Abschnitt 5.1) | von uns genutzt → `moss_balance_movements` |
| **Einkauf** | **Purchase** | nein — **nicht** in der Help-Doku, existiert aber lt. UI | für WSJ (noch) nicht genutzt |
| **Haushalt** | **Budget** | nein — **nicht** in der Help-Doku, existiert aber lt. UI | für WSJ (noch) nicht genutzt |
| *(Aktive Rechnungsabgrenzung)* | **Prepayment** / Accrual | ja | im Dropdown vorhanden, **für WSJ nicht relevant** |

> Hinweise: **Prepayment** ist im UI-Dropdown vorhanden (oben nur der
> Vollständigkeit halber gelistet — für WSJ irrelevant). **Einkauf (Purchase)**
> und **Haushalt (Budget)** existieren real im CSV-Builder, sind aber in der
> öffentlichen [CSV-Feldreferenz](https://help.getmoss.com/de/articles/11703042-csv-feldreferenz-und-tipps-zur-anpassung)
> **nicht** dokumentiert — Feldlisten dafür daher nur aus einem echten Export
> gewinnbar (Beispiel nach `doc/moss_export_examples/`, falls je gebraucht).

**Feldgruppen laut Feldreferenz** (für die dort dokumentierten Typen):

| Export-Typ (DE) | Export-Typ (EN) | Feldgruppen (Auszug, Quelle: Feldreferenz) |
| --- | --- | --- |
| **Transaktionen** (Kartentransaktionen) | **Card Transaction Exports** | Transaktionsgrundlagen · Daten & Zeiträume · Beträge & Währung · Händler & Lieferant · Buchhaltung & Kategorisierung · Mitarbeiter & intern · Links & Anhänge · Flugreisen & Aufschlüsselung |
| **Rechnungen** | **Invoice Exports** | Rechnungsgrundlagen · Beträge & Währung · Daten · Buchhaltung & Kategorisierung · Mitarbeitende & Teams · Lieferant & Zahlungsdetails · Kostenstellen & Projekte · Referenzen/Verknüpfung · Skonto |
| **Rückerstattungen** | **Reimbursement Exports** | Grundlagen · Daten & Zeiträume · Beträge & Währungen · Buchhaltung & Kategorisierung · Personen & Teams · Lieferant & Reisedetails |
| **Kontobewegungen** | **Balance Movements Exports** | Transaktionsdetails · Daten & Zeiträume · Beträge & Währungen · Buchhaltung & Kategorisierung · Verknüpfte Dokumente & Referenzen · Lieferant & interne Team-Daten |
| **Aktive Rechnungsabgrenzungsposten** | **Prepayment Exports** (Accrual entries) | Grundlagen Abgrenzung · Beträge & Währung · Buchhaltung & Kategorisierung · Rechnung & Datum · Notizen |

Quelle:
[CSV-Feldreferenz (DE)](https://help.getmoss.com/de/articles/11703042-csv-feldreferenz-und-tipps-zur-anpassung#h_e86ce8863d),
[CSV field reference (EN)](https://help.getmoss.com/en/articles/11703042-csv-field-reference-and-customization-tips#h_e050825b85).

> Die **vollständigen** Feldlisten je Gruppe stehen in der verlinkten
> Feldreferenz und werden hier nicht kopiert. Sobald wir eine konkrete
> Export-Vorlage/Beispieldatei haben, wird deren tatsächliches Spalten-Set in
> **Abschnitt 5** (Feldreferenz je Entität) dokumentiert. Bislang vollständig:
> **Kontobewegungen** (5.1) und **Kartentransaktionen** (5.2).

### 3.2 Format-Einstellungen für WSJ-Custom-Formate (Referenz)

**Regel:** Neue Custom-CSV-Builder-Formate für WSJ werden mit **denselben
Format-Einstellungen** angelegt wie das Referenz-Format **„Balance Movements
WSJ27"** (nur die Entität unter „Format" und die Spaltenauswahl ändern sich).

![CSV-Builder Formateinstellungen des Formats „Balance Movements WSJ27"](images/moss_csv_builder_format_settings.png)

Einstellungen laut Screenshot (Stand August 2026):

| Einstellung | Wert für „Balance Movements WSJ27" |
| --- | --- |
| **Name** | `Balance Movements WSJ27` (pro Entität anpassen) |
| **Format** | `Konto-Bewegungen` (= die zu exportierende Entität; s. 3.1) |
| **Datumsformat** | `YYYY-MM-DD` |
| **Betragsformat** | `Standard (wie auf der Seite angezeigt)` |
| **Spaltentrennzeichen** | `;` (Semikolon) |
| **Dezimaltrennzeichen** | `.` (Punkt) |
| **Dateiformat** | `UTF-8` |
| **Spaltenüberschriften in den Export einbeziehen** | ✅ an |
| **Spaltenunterüberschriften auch exportieren** | ☐ aus |
| **Erstelle für jede Zahlung einen Buchungskopf und eine Buchungszeile** | ☐ aus |

> Diese Kombination erzeugt genau das Format der Datei
> `balance-movements_…_custom_csv_builder.csv` (Trennzeichen `;`, Dezimalpunkt,
> UTF-8, ISO-Datum, Kopfzeile mit Spaltennamen), das `moss_balance_movements`
> füllt. Die Import-Skripte/Parser erwarten diese Einstellungen — bei neuen
> Formaten **nicht** abweichen (insb. `;`, Dezimal-`.`, UTF-8, ISO-Datum).

---

## 4. Import nach Hitobito

### 4.1 Aktueller Stand: `moss_balance_movements`

Bislang existiert im Wagon **genau eine** Moss-Tabelle:
`moss_balance_movements` (Model `MossBalanceMovement`, Migration
`20260411000100`). Sie wird an ein eigenes `WsjrdpFinAccount` „Moss Wallet"
gehängt (`fin_accounts.transaction_type = 'MossBalanceMovement'`, angelegt in
derselben Migration) und über den `WsjrdpTransaction`-Concern mit
`AccountingEntry`s abgeglichen (`accounting_entries.moss_balance_movement_id`).

Die Spalten entsprechen erkennbar dem CSV-Export **Kontobewegungen / Balance
Movements** (Abschnitt 3). Kommentare in der Migration ordnen einige Spalten
DATEV-Begriffen zu:

| Spalte (Auszug) | Bedeutung / Mapping |
| --- | --- |
| `moss_transaction_id`, `sub_row_number` | Moss-Transaktions-ID + Zeilennummer (Unique-Index zusammen). |
| `unique_item_number` | fachlicher Eindeutigkeits-Schlüssel der Zeile (Unique). |
| `transaction_state`, `transaction_type` | Zustand/Typ der Bewegung. |
| `payment_date`, `booking_date` | Zahl-/Buchungsdatum. |
| `amount`, `currency`, `amount_excl_vat` | Betrag (Cent-Umrechnung im Model via `amount_cents`), Währung, netto. |
| `original_amount*`, `original_currency`, `conversion_rate*` | Fremdwährung + Umrechnungskurs (inkl. Gebühren-Variante). |
| `fees_amount`, `payment_fee`, `transaction_amount_excluding_fees` | Gebühren. |
| `supplier_account` / `supplier_name` | Kreditor-Nr. / Kreditor-Name. |
| `account_number` / `name_of_expense_account` | Sachkonto-Nr. / Sachkonto-Name. |
| `category`, `moss_balance_account`, `cash_in_transit_account` | Kategorie, Moss-Verrechnungskonten. |
| `reason_for_purchase`, `note`, `payment_reference` | Zweck/Notiz/Verwendungszweck. |
| `recipient_account_number`, `recipient_bank_code` | Empfänger-Kontodaten. |
| `invoice_number`, `team_name`, `cardholder`, `client_number` | Referenzen/Zuordnung. |
| `moss_expense_id`, `moss_invoice_id`, `moss_reimbursement_id` | Verknüpfung zur zugrunde liegenden Ausgabe/Rechnung/Rückerstattung. |
| `moss_attachment_url` | Beleg-Link. |
| `first_export_date` | Export-Zeitpunkt. |

Quelle **bestätigt:** `moss_balance_movements` wird aus dem CSV-Export
**Kontobewegungen / Balance Movements** befüllt (nicht über die API), und zwar
konkret aus der **Custom-CSV des CSV-Builders** (Weg B). Beleg: die 41 Spalten der
Beispieldatei `balance-movements_…_custom_csv_builder.csv` entsprechen **1:1** den
Tabellenspalten (inkl. der in der Migration auskommentierten Felder `record_type`,
`csv_line_type`, `period`). Die vollständige Spalten-↔Feld-Zuordnung steht in
**Abschnitt 5** (Feldreferenz Kontobewegungen).

### 4.2 Geplante weitere Tabellen

Neu hinzugekommen: **`moss_card_transactions`** (Kartentransaktionen, Migration
`20260823000100`, angewandt) — Details/Feldreferenz in **5.2**, plus Backlink
`accounting_entries.moss_card_transaction_id`. Weitere `moss_*`-Tabellen
(Rechnungen/Rückerstattungen) folgen bei Bedarf.
(Verwandte Stammdaten-Tabellen wie Kreditoren/Kostenstellen/Sachkonten sind
Gegenstand von [`doc/bookkeeping_schema_review.md`](bookkeeping_schema_review.md);
deren Verhältnis zu den Moss-Entitäten **Supplier / Dimension / Expense Account**
ist noch zu klären.)

---

## 5. Feldreferenz je Entität

Pro Entität eine Tabelle. Spalten:

1. **API-Feld** — Feldname der Public API (Datenmodell/Endpunkt).
2. **Wagon-Spalte** — Spalte der zugehörigen `moss_*`-Tabelle.
3. **CSV-Builder (EN)** — Feldname im CSV-Builder / englische Feldreferenz.
4. **CSV-Builder (DE)** — Feldname im CSV-Builder / deutsche Feldreferenz.
5. **Ad-hoc (EN / DE)** — Spaltenname im Standard-Ad-hoc-Export (EN- bzw.
   DE-Sprachvariante), `—` falls dort nicht enthalten.
6. **Erklärung / Beispiel** — kurze Bedeutung; Beispiele sind **synthetisch**
   (keine echten Buchungsdaten).

> **API-Feld-Spalte:** Die API bildet die reichen Buchhaltungsfelder des
> Kontobewegungen-CSV **nicht** in *einer* Ressource ab. Die API-Entität für eine
> Geldbewegung ist **`BankTransaction`** (`POST /v1/bank-transactions/search-query`)
> mit nur wenigen Feldern; Kreditor/Sachkonto/Kategorie/USt./Verknüpfungen hängen
> an der **`Expense`**-Ressource (`GET /v1/expenses`). Der CSV-Export ist also ein
> **konsolidierter/gejointer** Export, kein 1:1-Spiegel einer API-Ressource. In
> Spalte 1 stehen daher nur die **sicher** zuordenbaren `BankTransaction`-Felder
> (Quelle: lokale Spec `schemas/bank_transaction/BankTransaction.yaml`); „≈" =
> plausibel, aber nicht 1:1 belegt. Details in **5.1.4**.

Quellen der Feldnamen:
[CSV-Feldreferenz DE](https://help.getmoss.com/de/articles/11703042-csv-feldreferenz-und-tipps-zur-anpassung#h_e86ce8863d) ·
[EN](https://help.getmoss.com/en/articles/11703042-csv-field-reference-and-customization-tips#h_e050825b85)
sowie die Beispieldateien `balance-movements_…_{custom_csv_builder,EN,DE}.csv`.

### 5.1 Kontobewegungen / Balance Movements

Feeds die Tabelle **`moss_balance_movements`** aus der **Custom-CSV (CSV-Builder)**.
Der Custom-Builder-Export (41 Spalten) deckt sich 1:1 mit der Tabelle; der
Standard-Ad-hoc-Export (33 Spalten, EN/DE) hat ein **teils anderes** Feldset (u. a.
USt.- und Kostenstellen-Felder, die die Tabelle nicht führt — siehe 5.1.2).

#### 5.1.1 Felder aus dem CSV-Builder-Katalog (Reihenfolge lt. Feldreferenz)

| API | Wagon-Spalte | CSV-Builder (EN) | CSV-Builder (DE) | Ad-hoc (EN / DE) | Erklärung / Beispiel |
| --- | --- | --- | --- | --- | --- |
| — | — | Transaction Ordinal | Transaktions-Ordnungszahl | — | Fortlaufende Tx-Nr.; nur Builder-Katalog, in unseren Vorlagen ungenutzt. |
| — | — | Row Number | Zeilennummer | — | Zeilennr. der Bewegung; ungenutzt. |
| — | `sub_row_number` | Sub-row Number | Unterzeilennummer | — | Split-Position innerhalb einer Tx; Teil des Unique-Index (mit `moss_transaction_id`). Bsp. `0`. |
| — | `moss_transaction_id` | Transaction ID | Transaktions-ID | Transaction ID / Transaktions-ID | Moss-Transaktions-ID. |
| — | `transaction_state` | Transaction State | Transaktionsstatus | Transaction State / Transaktionsstatus | Zustand der Bewegung. |
| `transactionType` | `transaction_type` | Transaction Type | Transaktionstyp | — | Typ der Bewegung. |
| — | `record_type` *(auskomm.)* | Record Type | Datensatz-Typ | — | Datensatz-Typ; Tabellenspalte in Migration auskommentiert. |
| `valueDate` ≈ | `payment_date` | Payment Date | Zahlungsdatum | Payment Date / Zahlungsdatum | Zahldatum. Bsp. `2026-08-23`. Model: `value_date = payment_date`. |
| `bookingDate` | `booking_date` | Booking Date | Buchungsdatum | Booking Date / Buchungsdatum | Buchungsdatum. |
| — | `first_export_date` | First Export Date | Erstes Exportdatum | First Export Date / Erster Export Datum | Erster Export dieser Zeile. |
| — | — | Month end date | Ende des Monats | — | Monatsende; ungenutzt. |
| — | `period` *(auskomm.)* | Period | Zeitraum | — | Periode; Spalte auskommentiert. |
| — | — | Period YYYY/MM | Zeitraum JJJJ/MM | — | Periode als `JJJJ/MM`; ungenutzt. |
| `amount.amount` | `amount` | Amount | Betrag | Amount / Betrag | Betrag (API: `Money{amount,currency}`, inkl. Gebühren); im Model → `amount_cents` (×100). |
| — | — | Amount Negated | Negierter Betrag | — | Vorzeichen-invertiert; ungenutzt. |
| — | — | Amount Debit | Soll-Betrag | — | Soll-Betrag; ungenutzt. |
| — | — | Amount Credit | Haben-Betrag | — | Haben-Betrag; ungenutzt. |
| — | `amount_excl_vat` | Amount (excl. VAT) | Betrag (exkl. USt.) | — | Nettobetrag. |
| — | — | Amount (excl. VAT) Negated | Negierter Betrag (exkl. USt.) | — | ungenutzt. |
| — | — | Amount Debit (excl. VAT) | Soll-Betrag (exkl. USt.) | — | ungenutzt. |
| — | — | Amount Credit (excl. VAT) | Haben-Betrag (exkl. USt.) | — | ungenutzt. |
| `amount.currency` | `currency` | Currency | Währung | Currency / Buchung Währung | Buchungswährung. Bsp. `EUR`. *(Ad-hoc-DE-Name: „Buchung Währung".)* |
| — | `original_amount` | Original Amount | Ursprünglicher Betrag | Original Amount / Ursprünglicher Betrag | Betrag in Ursprungswährung. |
| — | — | Original Amount Negated / Debit / Credit (je exkl. USt.) | Negierter/Soll-/Haben-Betrag (ursprünglich, je exkl. USt.) | — | Sechs Ursprungsbetrag-Varianten; ungenutzt. |
| — | `original_amount_excl_vat` | Original Amount (excl. VAT) | Ursprünglicher Betrag (exkl. USt.) | — | Netto in Ursprungswährung. |
| — | `original_currency` | Original Currency | Ursprüngliche Währung | Original Currency / Währung | Ursprungswährung. *(Ad-hoc-DE-Name: „Währung".)* |
| — | `conversion_rate` | Conversion Rate | Wechselkurs | Conversion Rate / Wechselkurs | Umrechnungskurs (Verhältnis). |
| — | `conversion_rate_including_fees` | Conversion Rate Including Fees | Wechselkurs inkl. Gebühren | — | Kurs inkl. Gebühren. |
| — | `transaction_amount_excluding_fees` | Transaction Amount Excluding Fees | Transaktionsbetrag ohne Gebühren | — | Betrag ohne Gebühren. |
| — | `fees_amount` | Fees Amount | Gebührenbetrag | — | Gebühren. |
| — | `payment_fee` | Payment Fee | Zahlungsgebühr | Payment Fee / Zahlung gebühren | Zahlungsgebühr. |
| — | — | Account Debit/Credit | Konto Soll/Haben | — | Soll/Haben-Konto; ungenutzt. |
| — | — | Account Debit/Credit Reverse | Gegenkonto Soll/Haben | — | Gegenkonto; ungenutzt. |
| — | `account_number` | Account Number | Kontonummer | Account Number / Buchungskonto | Sachkonto-Nr. Bsp. `67000`. |
| — | `name_of_expense_account` | Name of Expense Account | Name des Ausgabenkontos | Account Name / Name des Sachkontos | Sachkonto-Bezeichnung. *(Ad-hoc-Name „Account Name".)* |
| — | `category` | Category | Kategorie | — | Moss-Kategorie. |
| — | `supplier_name` | Supplier Name | Lieferant | Supplier Name / Lieferant | Kreditor-Name. |
| — | `supplier_account` | Supplier Account | Lieferantenkonto | Supplier Account / Lieferantenkonto | Kreditor-Kontonr. Bsp. `700013`. |
| — | `cardholder` | Cardholder | Karteninhaber | — | Karteninhaber\*in. |
| — | `reason_for_purchase` | Reason for Purchase | Kaufgrund | — | Kaufgrund. |
| — | `team_name` | Team Name | Teamname | — | Moss-Team. *(Ad-hoc führt stattdessen „Cost Center - Team", s. 5.1.2.)* |
| — | `client_number` | Client Number | Kundennummer | — | Kundennummer. |
| — | `moss_balance_account` | Moss Balance Account | Moss-Bilanzkonto | Moss Balance Account / Moss Bilanzkonto | Moss-Verrechnungskonto. |
| — | `cash_in_transit_account` | Cash in Transit Account | Geldtransitkonto | Cash In Transit Account / Geldtransitkonto | Geldtransitkonto. |
| — | `note` | Note | Notiz | Note / Notiz | Freitext-Notiz. |
| — | `invoice_number` | Invoice Number | Rechnungsnummer | Invoice Number / Rechnungsnummer | Rechnungsnummer. |
| — | `moss_invoice_id` | Linked Invoice ID | Verknüpfte Rechnungs-ID | Linked Invoice ID / Verknüpfte Rechnungs-ID | Verknüpfte Moss-Rechnung. |
| — | `moss_reimbursement_id` | Linked Reimbursement ID | Verknüpfte Erstattungs-ID | Linked Reimbursement ID / Verknüpfte Erstattungs-ID | Verknüpfte Erstattung. |
| — | `payment_reference` | Payment Reference | Zahlungsreferenz | Payment Reference / Zahlungsreferenz | Verwendungszweck; im Model `description`. |
| — | `recipient_account_number` | Recipient Account Number | Kontonummer des Empfängers | Recipient Account Number / Kontonummer des Empfängers | Empfänger-Konto. |
| — | `recipient_bank_code` | Recipient Bank Code | Bankcode des Empfängers | Recipient Bank Code / Bankcode des Empfängers | Empfänger-Bankleitzahl. |
| — | `unique_item_number` | Unique Item Number | Eindeutige Artikelnummer | — | Fachlicher Eindeutigkeits-Schlüssel (Unique-Index). |
| — | `csv_line_type` *(auskomm.)* | CSV Line Type | *(kein DE-Beleg)* | — | Zeilentyp im CSV; im Custom-Export vorhanden, Spalte auskommentiert. |
| — | `moss_attachment_url` | Moss Attachment URL | *(kein DE-Beleg)* | — | Beleg-Link. *(Ad-hoc führt „Moss Record URL", s. 5.1.2.)* |
| — | `moss_expense_id` | *(kein Quellfeld im Kontobewegungen-Export)* | — | — | ❓ Tabellenspalte ohne passendes Feld in diesem Export — Herkunft (anderer Export/API?) noch offen. |

*„auskomm." = Spalte in der Migration angelegt, aber auskommentiert (`# t.string …`). „ungenutzt" = im Builder-Katalog wählbar, in unserer Vorlage/Tabelle nicht enthalten.*

**Hitobito-interne Spalten** von `moss_balance_movements` (nicht aus Moss):
`fin_account_id` (→ FinAccount „Moss Wallet"), `subject_id/subject_type`
(Verknüpfung, i. d. R. Person), `comment`, `status`, `additional_info` (jsonb),
`created_at`/`updated_at`, `accounting_entry_id` (transient).

#### 5.1.2 Nur im Standard-Ad-hoc-Export (nicht im Custom-Builder / nicht in der Tabelle)

Der Standard-Ad-hoc-Export enthält zusätzlich folgende Felder, die die
Custom-Vorlage und damit `moss_balance_movements` **nicht** übernehmen:

| Ad-hoc (EN) | Ad-hoc (DE) | Erklärung |
| --- | --- | --- |
| VAT Name | USt. Szenario | USt.-Szenario/Bezeichnung. |
| VAT Rate | USt. Steuersatz | Steuersatz. |
| VAT Code | BU-Schlüssel | DATEV-BU-Schlüssel. |
| Cost Center - Team | Kostenstelle | Kostenstelle (Team). |
| Cost Carrier - Name | Kostenträger - Name | Kostenträger-Name. |
| Cost Carrier - Number | Kostenträger - Nummer | Kostenträger-Nummer. |
| Invoice File Name | Dateiname Rechnung | Dateiname des Belegs. |
| Merchant and Card Description | Händler und Kartenbeschreibung | Händler-/Kartentext. |
| Moss Record URL | Moss Record URL | Link zum Moss-Datensatz (≠ „Moss Attachment URL" im Builder). |

**Datenbelegung im Beispiel (2026-08-23):** In den vorliegenden Exporten (EN, DE
und Custom-Builder enthalten **exakt dieselben** 722 Kontobewegungen, zeilengleich
per `Transaction ID` abgeglichen) sind **alle** oben genannten Ad-hoc-Sonderfelder
über **alle 722 Zeilen leer** — d. h. `VAT Name/Rate/Code`, `Cost Center - Team`,
`Cost Carrier - Name/Number`, `Invoice File Name`, `Merchant and Card Description`
und `Moss Record URL` tragen hier **keinerlei Daten**. Damit:

- Es gibt **nichts abzuleiten** und der Custom-Builder-Export (→ Tabelle) verliert
  gegenüber dem Ad-hoc-Export in diesem Datensatz **keine** Information.
- Diese Felder sind offenbar in diesem Moss-Mandanten/Zeitraum **nicht befüllt**
  (Kostenstellen/-träger, USt.-Zerlegung, Merchant-Text nicht genutzt). **Caveat:**
  „leer im Beispiel" ist **nicht** dasselbe wie „strukturell immer leer" — würde
  Moss sie künftig befüllen, ließen sie sich **nicht** aus den behaltenen Spalten
  rekonstruieren (eigenständige Moss-Daten). Dann neu bewerten.

*(Weiterer Nebenbefund: auch `Invoice Number` ist im Ad-hoc-Export durchgehend
leer, während das gleichnamige Custom-Builder-Feld in einigen Zeilen befüllt ist —
die beiden „Invoice Number" sind also nicht deckungsgleich.)*

**Vollständigkeits-Abgleich Ad-hoc → Custom-Builder (2026-08-23):** Verglichen
wurde für jede Ad-hoc-Spalte **mit Daten**, ob die Information auch im Custom-
Builder-Export steht. Ergebnis: **eine** Ad-hoc-Spalte trägt Werte, die ihr
direktes Custom-Pendant nicht hat —

| Ad-hoc (EN / DE) | Custom-Pendant (leer in) | ableitbar? |
| --- | --- | --- |
| `Account Name` / `Name des Sachkontos` | `Name of Expense Account` (7 Zeilen leer) | **Ja, 1:1.** `Account Name` **== `Category`** in **allen 722 Zeilen** (100 %). Das Ad-hoc-„Account Name" ist faktisch die Moss-**Kategorie**, nicht der Sachkonto-Name. → über Wagon-Spalte `category` vollständig reproduzierbar. |

Alle übrigen Ad-hoc-Spalten mit Daten haben ein **exaktes** Custom-Pendant
(Beträge, Daten, `Note`, `Supplier*`, `Account Number`, `Recipient*`, `Payment
Fee`, `Linked *`, …; Format-/Sprachunterschiede zählen nicht als Zusatzinfo).

**Fazit:** Der Ad-hoc-Export enthält **keine** Information, die nicht auch im
Custom-Builder-Export (→ `moss_balance_movements`) steht — der einzige scheinbare
Sonderfall (`Account Name`) ist aus `category` ableitbar. (Datensatz-spezifisch,
gleiche Caveats wie oben.)

#### 5.1.3 DATEV-Format (Spezialfall)

Der Ad-hoc-Export „DATEV" liefert **kein** Buchungs-CSV, sondern ein **ZIP** im
**DATEV-Belegtransfer-Format**: eine `document.xml` (Index) plus je Buchung eine
XML (`Payment_<uuid>.xml` / `Invoice_<uuid>.xml`; im Beispiel mehrere hundert
Payment- und einige Invoice-XML). Belege (PDF/Bild) sind in diesem Beispiel-ZIP
**nicht** enthalten — nur die Buchungssatz-XML.

Verwendete DATEV-Schemata (aus den Dateien):

- Index: `http://xml.datev.de/bedi/tps/document/v05.0`
  (`archive/header/{date,description}`, `archive/content/document/extension` mit
  `@datafile`/`@type` und `property @key/@value`).
- Buchungssätze: `http://xml.datev.de/bedi/tps/ledger/v050`
  (`LedgerImport/consolidate/accountsPayableLedger`).

**Felder je Buchungssatz** (`accountsPayableLedger`) und ihre Entsprechung im
Kontobewegungen-Export:

| DATEV-Element | entspricht CSV-Feld | Erklärung |
| --- | --- | --- |
| `accountNo` | Account Number | Sachkonto. |
| `amount` | Amount | Betrag. |
| `currencyCode` | Currency | Währung. |
| `date` | Booking Date | Datum. |
| `exchangeRate` *(nur Payment)* | Conversion Rate | Wechselkurs. |
| `bpAccountNo` | Supplier Account | Kreditor-Kontonr. |
| `supplierName` | Supplier Name | Kreditor-Name. |
| `invoiceId` | Invoice Number / Linked Invoice ID | Rechnungsnummer/-referenz. |
| `paidAt` | Payment Date | Zahldatum. |
| `bookingText` | *(zusammengesetzt)* | DATEV-Buchungstext, aus vorhandenen Feldern formatiert. |
| `information` *(nur Payment)* | *(zusammengesetzt)* | DATEV-Zusatztext, aus vorhandenen Feldern. |
| `consolidate @consolidated{Amount,CurrencyCode,Date,InvoiceId}` | — | Zusammenfassungs-Attribute (DATEV-Struktur). |

> **Verifikation (Auftrag):** Auf Ebene der **Feld-/Element-Struktur** enthält das
> DATEV-Paket **keine zusätzlichen Geschäftsdaten** gegenüber dem
> Kontobewegungen-CSV — alle DATEV-Felder sind ein **Teilmenge/Ableitung** der
> CSV-Felder. DATEV ergänzt nur **Struktur** (`LedgerImport`/`consolidate`) und
> **formatierte Textfelder** (`bookingText`, `information`), die aus bereits
> vorhandenen Feldern zusammengesetzt sind. Geprüft wurde die Element-/Attribut-
> Struktur aller XML, nicht jeder Einzelwert.

#### 5.1.4 API-Bezug (BankTransaction vs. Expense)

Quelle: lokale OpenAPI-Spec (**nicht aufrufen**).
`schemas/bank_transaction/BankTransaction.yaml`,
`schemas/bank_transaction/BankTransactionFee.yaml`.

**`BankTransaction`** (`POST /v1/bank-transactions/search-query`) — Felder:

| Feld | Typ | entspricht CSV (Kontobewegungen) |
| --- | --- | --- |
| `id` | uuid | (Moss-Tx-ID; genaue Entsprechung zu `Transaction ID` nicht belegt) |
| `bankAccountId` | uuid | Wallet-Zuordnung (nicht im CSV) |
| `organisationId` | uuid | — |
| `transactionType` | enum `BankTransactionType` | Transaction Type |
| `amount` | `Money{amount,currency}` | Amount + Currency (**inkl. Gebühren**) |
| `bookingDate` | date | Booking Date |
| `valueDate` | date | ≈ Payment Date |
| `description` | string | ≈ Payment Reference / Note (nicht belegt) |
| `counterparty` | string | ≈ Supplier Name / Empfänger (nicht belegt) |
| `fees[]` | `BankTransactionFee{feeType,amount}` | ≈ Fees Amount / Payment Fee |

`BankTransaction` trägt **keine** Felder für Sachkonto, Kategorie, USt., Kreditor-
Konto, Team, Verknüpfungen zu Rechnung/Erstattung. Diese stammen aus der
**`Expense`**-Ressource (`GET /v1/expenses`, Typen Card Transaction/Invoice/
Reimbursement). Ein feldgenaues Expense→CSV-Mapping ist noch offen (die
`Expense`-Schemata liegen in `schemas/`, aber der Join CSV↔Expense ist nicht
dokumentiert — nicht erraten).

### 5.2 Kartentransaktionen / Card Transactions

Ziel-Tabelle: **`moss_card_transactions`** (Migration
`20260823000100_add_moss_card_transactions.rb`) — Schwester von
`moss_balance_movements`. Grundlage: die Beispiel-Exporte
`transactions_2026-08-23--16-59_*` (alle **dieselben 183 Kartentransaktionen**,
gleichzeitig exportiert).

#### 5.2.1 Vorliegende Dateien: Formate & Encoding

Alle Text-Dateien **UTF-8, ohne BOM, Zeilenende LF**.

| Datei / Ordner | Export-Auswahl | Struktur |
| --- | --- | --- |
| `…_EN.csv` | Standard-Ad-hoc, **EN** | 32 Spalten, Trenner **`,`**, 183 Datenzeilen |
| `…_DE.csv` | Standard-Ad-hoc, **DE** | 32 Spalten, Trenner **`;`**, 183 Zeilen (gleiches Set wie EN, nur Sprache) |
| `…_DATEV.csv` | Ad-hoc **DATEV-CSV** | DATEV-**EXTF „Buchungsstapel"**, 114 Spalten, Trenner `;`, Zeile 0 = Spaltennamen, 183 Buchungszeilen |
| `…_Addison.csv` | Ad-hoc **Addison/DATEV** | wie DATEV.csv, aber Zeile 0 = **EXTF-Metazeile** (`EXTF;…;Buchungsstapel;…`), Zeile 1 = Spaltennamen; die 114 Spaltennamen sind **identisch** zu DATEV.csv |
| `…_attachments.zip` → `…_attachments/` | Belege (Sammel-PDF) | **181** PDFs, benannt `<Transaction-ID>.pdf` |
| `…_receipts.zip` → `…_receipts/` | Einzelbelege | **262** Dateien (jpg/pdf/png), sprechend benannt |

> `_attachments/` und `_receipts/` sind die entpackten Inhalte der gleichnamigen
> ZIPs. `DATEV.csv` = `Addison.csv` **ohne** die EXTF-Kopfzeile.

#### 5.2.2 Ad-hoc-Spalten (EN/DE) → `moss_card_transactions`

EN und DE sind **positionsgleich** (32 Spalten, nur Sprache). Zuordnung:

> Hinweis: Die Spalte **Wagon-Spalte** unten zeigt die frühere (Ein-Tabellen-)
> Benennung. Aktuell gilt die **Zwei-Tabellen**-Aufteilung aus **5.2.6**
> (u. a. `moss_transaction_uuid` → `card_transaction_uuid`, `note` → `description`
> auf `…_bookings`, `Category` entfernt, Kostenstelle/Sphäre buchungs-seitig).

| # | EN | DE | Wagon-Spalte | Hinweis |
| --- | --- | --- | --- | --- |
| 0 | Transaction State | Transaktionsstatus | `transaction_state` | |
| 1 | Payment Date | Zahlungsdatum | `payment_date` | |
| 2 | Booking Date | Buchungsdatum | `booking_date` | |
| 3 | Settlement Date | Abrechnungsdatum | `settlement_date` | kartenspezifisch (fehlt bei Kontobewegungen) |
| 4 | Transaction ID | Transaktions-ID | `moss_transaction_uuid` | UUID; = `attachments/<id>.pdf` |
| 5 | Amount | Betrag | `amount` | |
| 6 | Currency | Buchung Währung | `currency` | |
| 7 | Original Amount | Ursprünglicher Betrag | `original_amount` | |
| 8 | Original Currency | Währung | `original_currency` | Ad-hoc-DE-Name „Währung" |
| 9 | Conversion Rate | Wechselkurs | `conversion_rate` | |
| 10 | Merchant Name | Händlername | `merchant_name` | kartenspezifisch |
| 11 | Account Name | Name des Sachkontos | `category` | Ad-hoc „Account Name" **== Category** (wie 5.1.2); *nicht* der Sachkonto-Name |
| 12 | Account Number | Buchungskonto | `account_number` | Sachkonto |
| 13 | Note | Notiz | `note` | |
| 14 | Cardholder | Kreditkarteninhaber | `cardholder` | |
| 15 | Card Used | Kreditkarte | `card_used` | kartenspezifisch |
| 16 | Team Name | Teamname | `team_name` | |
| 17 | Cost Center - Team | Kostenstelle | `cost_center_name` | Ad-hoc-Name „Cost Center - Team" |
| 18 | Cost Carrier - Name | Kostenträger - Name | `cost_carrier_name` | |
| 19 | Cost Carrier - Number | Kostenträger - Nummer | `cost_carrier_number` | |
| 20 | VAT Name | USt. Szenario | `vat_name` | **im Beispiel leer** |
| 21 | VAT Rate | USt. Steuersatz | `vat_rate` | **im Beispiel leer** |
| 22 | VAT Code | BU-Schlüssel | `vat_code` | **im Beispiel leer** |
| 23 | Moss Balance Account | Moss Bilanzkonto | `moss_balance_account` | |
| 24 | Cash In Transit Account | Geldtransitkonto | `cash_in_transit_account` | |
| 25 | First Export Date | Erster Export Datum | `first_export_date` | |
| 26 | Invoice Number | Rechnungsnummer | `invoice_number` | 161/183 belegt; **DATEV-Brücke** (= Belegfeld 1) |
| 27 | Supplier Name | Lieferant | `supplier_name` | Kreditor-Name |
| 28 | Supplier Account | Lieferantenkonto | `supplier_account` | Kreditor-Nr. |
| 29 | Invoice File Name | Dateiname Rechnung | `invoice_file_name` | Beleg-Dateinamen, Pipe-getrennt → `receipts/` |
| 30 | Merchant and Card Description | Händler und Kartenbeschreibung | `merchant_and_card_description` | |
| 31 | Moss Record URL | Moss Record URL | `moss_record_url` | `https://getmoss.com/app/transactions/all/<id>` |

Bis auf `VAT Name/Rate/Code` (leer) und `Note` (182/183) sind alle Spalten in
allen 183 Zeilen befüllt.

#### 5.2.3 Belege: `attachments/` und `receipts/` → Zeilen-Zuordnung

- **`attachments/<Transaction-ID>.pdf`** — der Dateiname (UUID) **ist exakt die
  Moss `Transaction ID`** (181/181 Treffer). Also **ein Sammel-PDF je
  Transaktion**, direkt joinbar über `moss_transaction_uuid`. 181 von 183
  Transaktionen haben eins (2 ohne). Entspricht dem Feldreferenz-Feld
  **„Transaction ID PDF filename"**.
- **`receipts/…`** — die **exakten** Dateinamen stehen in der CSV-Spalte
  **`Invoice File Name`** (bei mehreren Belegen mit ` \| ` getrennt). Alle 262
  referenziert, **keine verwaisten**. Belege je Transaktion: 1× (132), 2× (24),
  3× (25), 4× (1), 5× (1) → **eine Transaktion kann mehrere Belege haben**.
  Dateinamensmuster (maskiert):
  `YYYY-MM-DD-«HÄNDLER»-«BETRAG»-EUR-«KARTENINHABER»-«hex8».«ext»`.
  Der `«hex8»`-Suffix ist eine **eigene Moss-Beleg-ID** (kein Präfix der
  Transaction ID und keiner Attachment-UUID).

→ Zuordnung eindeutig: `attachments/` über die UUID, `receipts/` über
`Invoice File Name`.

#### 5.2.4 Abgleich mit der Feldreferenz „Card Transaction"

Quelle:
[CSV field reference – Card Transaction](https://help.getmoss.com/en/articles/11703042-csv-field-reference-and-customization-tips).
Felder der Feldreferenz, die in **keiner** der vorliegenden Dateien mit **Daten**
erscheinen:

- **Nur im Custom-CSV, nicht im Ad-hoc/DATEV** (daher hier fehlend, aber
  grundsätzlich exportierbar): `Type`, `Transaction Ordinal`, `Row Number`,
  `Sub-row Number`, `Sub Item Row Number`, `Record Type`, `Unique Item Number`,
  `Month end date`, `Period`, `Period YYYY/MM`, die Betrags-Varianten
  (`… Negated/Debit/Credit`, `… (excl. VAT)`), `VAT`/`Original VAT`,
  `Conversion Rate Including Fees`, `Transaction Amount Excluding Fees`,
  `Fees Amount`, `Cost Center - Name`/`- Number` (Ad-hoc hat nur „Cost Center - Team").
- **In diesem Datensatz leer** (Spalte vorhanden, keine Werte): `VAT Name`,
  `VAT Rate`, `VAT Code`.
- **In gar keiner Datei** (auch nicht im Custom-CSV-Katalog belegt/genutzt):
  `Merchant City`, `Merchant Country`, `Card Acceptor Name`,
  `CUSTOMER GROUP - Customer G Name`/`- Value`, `Distribution combination`,
  die granularen Karten-Felder `Card Purpose` / `Card Holder Label` /
  `Card Holder Name` / `Card Label` / `Card Name`, `Post Spend Approval Status`,
  sowie die Flugreise-Felder `Airline Ticket Number`, `Unit Price`, `Quantity`,
  `% of Total`.
- Realisiert (nicht „fehlend"): `Transaction ID PDF filename` = die
  `attachments/<id>.pdf`-Benennung (5.2.3).

#### 5.2.5 DATEV-Export & Verknüpfung DATEV-Buchung ↔ Kartentransaktion

Es gibt **zwei verschiedene** DATEV-Darstellungen einer Kartenzahlung — nicht
verwechseln:

**(A) Der Ad-hoc-„DATEV/Addison"-CSV-Export** (die vorliegenden Dateien
`…_DATEV.csv` / `…_Addison.csv`): **eine** Buchung je Transaktion,
Konto = Sachkonto (`66500`/`66630`/`63040`/…) **an Gegenkonto `36100`**
(Moss-Konto), KOST2 = `3` (Sphäre), Belegfeld 1 = Rechnungsnummer,
Buchungstext = „«Händler»; «Karteninhaber»; «Zweck»", Beleglink = Beleg-Dateiname,
Beleginfo Art 1–7 = Lieferant/Kreditkarteninhaber/Kreditkarte/Grund des
Einkaufs/Dateiname Rechnung/Kategorie/Teamname. **Kein Moss-UUID.** Diese Datei
ist eine vereinfachte Einzelbuchung und **nicht** das, was in `datev_bookings`
liegt.

**(B) Die produktive Kette „DATEV Unternehmen Online"** — der **andere Exportweg**,
aus dem die `datev_bookings` in Hitobito stammen. Laut
[Moss-Buchungslogik](https://help.getmoss.com/de/articles/7041394-buchungslogik-moss-zahlungen-datev-unternehmen-online)
je Kartenzahlung **drei** aufeinanderfolgende Buchungen. WSJ-Konten (Nutzerangabe):
**Moss-Konto `36100`**, **Moss-Sammelkreditor `700002`**, **Geldtransitkonto `13720`**.

| Schritt | Buchung (Soll → Haben) | In `datev_bookings` (Konto ↔ Gegenkonto) | Beleg? |
| --- | --- | --- | --- |
| 1 Ausgabenerfassung | **Sachkonto → Moss-Sammelkreditor** | `EXPENSE`(66xxx/63xxx) ↔ `700002` | **ja** (Belegfeld 1, Beleginfo, `bedi_guid`) |
| 2 Kreditorenausgleich | **Moss-Sammelkreditor → Moss-Konto** | `36100` ↔ `700002` | ja (mitgeführt) |
| 3 Rückzahlung | **Moss-Konto → Geldtransitkonto** | `36100`/Bank ↔ `13720` | nein (Sammel-Ausgleich) |

**Belege/Verifikation in der Dev-DB** (`datev_bookings`, 6809 Zeilen; read-only):

- **Schritt 1** (`account_type='EXPENSE' AND offsetting_account_number='700002'`):
  **182** Buchungen ≈ die 183 Kartentransaktionen (Rest: neuere, noch nicht
  gebucht). Alle mit Belegfeld 1 + Beleginfo + `bedi_guid`.
- Alle Buchungen mit Bezug zu `700002` (Schritte 1+2+…): 372.
- Die Moss-Beleginfo-Labels (Kreditkarteninhaber …) sind **nicht** erhalten;
  stattdessen `D_Rechnung`/`D_RechPositionen`/`D_Nachricht` (ReWe-Umbau). **Kein
  Moss-UUID** in `datev_bookings`.
- **Brücke Rechnungsnummer:** Moss `Invoice Number` (= Belegfeld 1) ↔
  `datev_bookings.document_field_1` deckt sich in **133/157** Fällen mit den
  Schritt-1-Buchungen (Rest: ohne Rechnungsnummer / noch nicht gebucht).

**Empfohlene Erkennung Moss-abgeleiteter DATEV-Buchungen beim Import:**

1. **Karten-Kette identifizieren** über die drei WSJ-Konten: Buchungen mit Bezug zu
   `700002` (Sammelkreditor), `36100` (Moss-Konto) bzw. `13720` (Geldtransit).
2. **Belegtragende Einzelbuchung** = Schritt 1: `account_type='EXPENSE' AND
   offsetting_account_number='700002'` — **eine** je Kartentransaktion.
3. **Join** zur Kartentransaktion: `document_field_1 = moss_card_transactions.invoice_number`
   (≈ 85 %), zur Eindeutigmachung zusätzlich **Betrag + `booking_date` + Sachkonto**
   (`account_number`).
4. Da weder Rechnungsnummer garantiert eindeutig noch die UUID vorhanden ist, bleibt
   die Verknüpfung **heuristisch mit Score** — passend zum
   [`recon_linking`](recon_linking.md)-Muster (Link auf der `datev_bookings`-Seite,
   Folge-Migration).

> In der Dev-DB paart sich `36100` auch mit Kreditor **`700000`** (327 Buchungen)
> — das sind **vermutlich Rückerstattungsbuchungen** (Refunds), nicht der
> Sammelkreditor-Fluss `700002`. Beim Erkennen der Karten-Ausgaben daher auf
> `700002` (Schritt 1) abstellen; `700000` separat als Rückerstattung behandeln.

##### Reicht `invoice_number` + Betrag + `booking_date` zum Matchen?

Geprüft gegen die 182 Schritt-1-Buchungen (Dev-DB):

- **Ja, für Transaktionen *mit* Rechnungsnummer** (161/183): über die
  gemeinsamen Rechnungsnummern stimmen **Betrag, Datum und Sachkonto zu 136/136**
  überein — die Kombination `(invoice_number, Betrag, booking_date)` ist praktisch
  **eindeutig** (genau **1** Kollision: die eine gesplittete Transaktion; mit
  `account_number`/`sub_row` auflösbar).
- ⚠️ **Datumsformat beachten:** der Ad-hoc-**EN**-Export schreibt das Datum als
  `27 Apr 2026`, DATEV/DB als ISO `2026-04-27` — beim Matchen **normalisieren**.
  Der Custom-CSV (Datumsformat `YYYY-MM-DD`, wie „Balance Movements WSJ27")
  vermeidet das.
- **Nein, für die 22 Transaktionen *ohne* Rechnungsnummer:** dort ist
  `(Betrag, Datum, Sachkonto)` **nicht** eindeutig (7 Kollisionsgruppen, 22
  Zeilen) → zusätzliche Merkmale nötig (Kreditor/`supplier_account`,
  `cardholder`, oder Beleg).

##### Enthält die Ad-hoc-DATEV/Addison-Datei Infos, die im EN/DE-CSV fehlen?

Zeilen richten sich 1:1 (183/183, gleiche Reihenfolge). Ergebnis: **keine
zusätzlichen Moss-Geschäftsdaten.** Alle fachlichen Felder (Händler, Karteninhaber,
Karte, Lieferant, Rechnungsnr., Kostenstelle, Kategorie, Datum, Beträge,
Beleg-Dateiname) stehen bereits im EN/DE-CSV. DATEV-spezifisch (nicht im EN/DE),
aber **abgeleitet/Mechanik** statt neuer Information:

- `Soll/Haben-Kennzeichen`, `Kurs`, `Basis-Umsatz`, `Festschreibung`,
  `Buchungstext` (= zusammengesetzt „Händler; Karteninhaber; Zweck"), `KOST2 = 3`
  (Sphäre) — DATEV-Buchungsmechanik.
- `Konto` = Sachkonto (= EN `Account Number`), `Gegenkonto` = `36100`
  (= EN `Moss Balance Account`), `KOST1` = EN `Cost Center - Team` (identisch,
  183/183), `Beleginfo 'Grund des Einkaufs'` ≈ EN `Note` (182/183).
- **Addison** unterscheidet sich von `DATEV.csv` nur durch die **EXTF-Kopfzeile**
  (Berater/Mandant/Zeitraum) — **keine** per-Transaktion-Zusatzinfo.

##### Custom-CSV: welche Feldreferenz-Felder liefern *zusätzliche* Information?

Der Hauptgewinn eines Custom-CSV (wie bei Kontobewegungen) sind die **stabilen
Schlüssel** und das ISO-Datum, die dem Ad-hoc fehlen:

- **Für Tabelle/Import nötig:** `Unique Item Number`, `Sub-row Number` (Splits!),
  `Record Type`, `Type`/`Transaction Type`.
- **Echte Zusatz-Geschäftsinfo** (in keiner vorliegenden Datei): `Merchant City`,
  `Merchant Country`, `Card Acceptor Name`; granulare Karten-Felder
  (`Card Purpose`, `Card Holder Name`, `Card Label`, `Card Name`);
  `Post Spend Approval Status`; die Flugreise-Felder (`Airline Ticket Number`,
  `Unit Price`, `Quantity`, `% of Total`).
- **Sauberer als der Ad-hoc** (dort nur indirekt/vermischt): `Category` explizit
  (statt „Account Name"), `Cost Center - Name`/`- Number` explizit (statt nur
  „Cost Center - Team"), sowie die Betrags-Aufschlüsselung
  `Amount (excl. VAT)` / `VAT` / `Fees Amount` /
  `Transaction Amount Excluding Fees` (falls USt./Gebühren relevant werden).
- **Ohne Nutzen hier:** `VAT Name/Rate/Code` (im Datensatz leer).

#### 5.2.6 Tabellen `moss_card_transactions` + `moss_card_transaction_bookings`

Wegen der **Splits** (eine Kartentransaktion kann über mehrere Sachkonten
aufgeteilt sein — eine CSV-Zeile je Split) ist das Modell auf **zwei Tabellen**
aufgeteilt (Migration `20260823000100`, angewandt):

| | `moss_card_transactions` | `moss_card_transaction_bookings` |
| --- | --- | --- |
| Körnung | **eine Zeile je `Transaction ID`** | **eine Zeile je Split/Buchung** |
| Inhalt | Felder, die über alle Splits **gleich** sind | Felder, die je Split **unterschiedlich** sind (inkl. Kostenstelle, Sphäre, Buchungstext) |
| Schlüssel | **`card_transaction_uuid`** (unique, natürlicher Schlüssel) | `unique_item_number` (unique), `(card_transaction_uuid, sub_row_number)` (unique) |
| Verweis | — | **`card_transaction_uuid`** **NOT NULL** → Transaktion (natürlicher Schlüssel, kein Surrogat-FK) |

Die Aufteilung wurde **empirisch** aus den Split-Zeilen des WSJ27-Beispiels
bestimmt; Kostenstelle/Sphäre/Buchungstext sind zusätzlich **bewusst** buchungs-
seitig (können pro Buchung abweichen). **Booking-Level**: `unique_item_number`,
`sub_row_number`, `amount`, `amount_excl_vat`, `home_amount`, `original_amount`,
`original_amount_excl_vat`, `transaction_amount_excluding_fees`, `account_number`,
`name_of_expense_account`, `original_expense_account`, **`cost_center_number`**,
**`sphere_number`** (= Moss „Cost Carrier - Number"), `distribution_combination`,
**`description`** (= Moss „Note", Buchungstext je Buchung). **Transaction-Level**:
alles andere (Datumsangaben, Merchant/Karte/Lieferant, **`Total *`**-Beträge,
Währungen, Kurse, `invoice_number`, **`parent_booking_text`** = Buchungstext der
Gesamt-Transaktion …). *Caveat:* die im Sample konstant-0-en
`vat_amount`/`original_vat`/`fees_amount` blieben transaktions-seitig — falls je
echte USt./Gebühren pro Zeile auftreten, nach `…_bookings` verschieben. **Entfernt:**
`Category` (nicht gespeichert; s. 5.2.7).

- **Namensregel:** Moss-UUID-Spalte = **`card_transaction_uuid`** (Typ `string`);
  die Bookings referenzieren die Transaktion direkt darüber.
- **`invoice_number`**: indexiert (DATEV-Brücke), transaktions-seitig.
- **`person_id`** (optional → `people`): `MossCardTransaction belongs_to :person`,
  `Person has_many :moss_card_transactions`. Ferner `has_many :bookings`
  (natürlicher Schlüssel `card_transaction_uuid`). *(Der frühere
  `accounting_entries`-Backlink wurde entfernt.)*
- **DATEV-Verknüpfung je Buchung** (strikt 1:1, optional): jede
  `moss_card_transaction_bookings`-Zeile kann zwei `datev_bookings` referenzieren
  (Migration-Header 5.2.5, „3-Schritt-Kette"):
  - `expense_datev_booking_id` — Schritt 1 (Sachkonto → Sammelkreditor 700002).
  - `clearing_datev_booking_id` — Schritt 2 (Sammelkreditor → Moss-Konto 36100).
  Beide Spalten haben einen **Unique-Index**; `DatevBooking` hat je eine
  `has_one`-Rückrichtung (`expense_…` / `clearing_moss_card_transaction_booking`).
- **JSONB:** beide Tabellen tragen `additional_info` (eigene Daten) **und**
  `other_columns` (WSJ27-Spalten ohne eigene Spalte, s. 5.2.7).
- **Import:** `accounting_tools/import_moss_card_transactions.py` (im Repo
  `wsjrdp_scripts`) — CSV→DB-Mapping, splittet je Zeile in Transaktion + Buchung; idempotent
  (verifiziert). Logik: neue `Transaction ID` → INSERT Transaktion + Buchungen;
  vorhandene → TX-Felder diffen/UPDATE + Buchungen über `Unique Item Number`
  matchen (1:1 → UPDATE; abweichende Zahl/UINs → **Fehler**). Manuelle Felder
  (`person_id`, `comment`, `status`, `additional_info`, die DATEV-Refs) bleiben
  beim UPDATE erhalten.

#### 5.2.7 Custom-CSV `…_WSJ27.csv` (CSV-Builder) — Analyse

Datei `transactions_…_WSJ27.csv`: **94 Spalten**, UTF-8 ohne BOM, LF, Trenner `;`,
183 Zeilen — dieselben Transaktionen, **Superset** der Ad-hoc-Felder. Dies ist die
vorgesehene **Import-Quelle** (5.2.6).

**Eindeutige ID (ja):**
- **`Unique Item Number`** — **183/183 eindeutig** → der Zeilenschlüssel
  (`unique_item_number`, Unique-Index).
- **`(Transaction ID, Sub-row Number)`** — ebenfalls eindeutig (183); `Transaction ID`
  allein nur 181 (2 Splits).
- **`Transaction ID PDF filename`** = `<Transaction ID>.pdf` (183/183) → identisch
  mit der `attachments/`-Benennung (5.2.3).

**Deckung der Ad-hoc-Felder:** **alle** EN/DE-Spalten sind enthalten — **nichts
fehlt**. Nur teils sauberer benannt/aufgeteilt: Ad-hoc `Account Name` → hier
**`Category`** *und* **`Name of Expense Account`** (getrennt); Ad-hoc
`Cost Center - Team` → **`Cost Center - Number`/`- Name`**; `Cash In/in Transit`
(Schreibweise). `VAT Name/Rate/Code` bleiben leer (wie im Ad-hoc).

**Neue, *befüllte* Informationen (nicht im Ad-hoc/DATEV):**
- **Beträge/Aufschlüsselung:** `Home Amount`/`Home Currency` (Basiswährung EUR),
  `Amount (excl. VAT)`, `VAT Amount`, `Original VAT`, `Original Amount (excl. VAT)`,
  `Fees Amount`, `Conversion Rate Including Fees`, `Transaction Amount Excluding Fees`,
  `Total Amount(+ excl. VAT)`, `Total Original Amount(+ excl. VAT)`.
- **Händler-Detail:** `Merchant City`, `Merchant Country`, `Card Acceptor Name` (nur 3).
- **Karten-Detail:** `Card Holder Name`, `Card Holder Label`, `Card Label`,
  `Card Name`, `Card Purpose`.
- **Freigabe-Workflow:** `Approval Date`, `Approver Name`, `Post Spend Approval Status`
  (je 182).
- **Weitere Felder/Datumsangaben:** `Reason for Purchase` (explizit, 183 — im Ad-hoc
  nur ≈ `Note`), `Name of Expense Account`, `Original Expense Account`,
  `Receipt Date` (183), `Service Date` (146), `Month end date`, `Period`,
  `Distribution combination`, `General Transaction Type`, `Transaction Type`,
  `Is Prepayment?`, `Sage Payment/Transaction Type`, `Moss Attachment URL`,
  Struktur (`Transaction Ordinal`, `Row Number`, `Sub Item Row Number`).

**Neue Spalten, die *leer* sind** (im Datensatz ohne Nutzen): `Supplier IBAN`,
`Supplier BIC`, `Supplier Vat ID`, `Client Number`, `Accounting Period`,
`Record Type`, `Airline Ticket Number`, `Prepayment Start/End Date`,
`Number of Months in Release Plan`, `Period Day`, `Period Month`.

**Fehlt aus dem Ad-hoc:** nichts (Superset).

**Neue Hilfen für den `datev_bookings`-Abgleich:**
- **`Home Amount` (+`Home Currency`) = DATEV `Basis-Umsatz` (183/183).** Der
  **Basiswährungs-Betrag (EUR)** ist das robuste Match-Feld gegen
  `datev_bookings.absolute_base_amount` — besonders bei Fremdwährung, wo der
  Transaktions-`Amount` ≠ EUR ist (hier alle EUR, daher gleich).
- **`Unique Item Number` / `Sub-row Number`** lösen die eine
  Invoice+Betrag+Datum-**Split-Kollision** (5.2.5) sauber auf.
- **Disambiguierung der 22 Transaktionen ohne Rechnungsnummer:** `Reason for
  Purchase`, `Card Holder Name`, `Merchant City/Country` als Zusatzmerkmale.
- **Kein exakter Schlüssel:** `Supplier IBAN`/`BIC`/`Vat ID` wären ideal, sind hier
  aber **leer**. `Parent Booking Text` ≠ der DATEV-Buchungstext (0/183 im
  DATEV-Export; nur 42/145 Überlappung mit `datev_bookings.original_posting_text`)
  → **nicht** als Join-Schlüssel geeignet. Ein Moss-UUID gibt es in
  `datev_bookings` weiterhin nicht.

**Umgesetzt** (Migration `20260823000100`): die WSJ27-Exportspalten sind auf die
**zwei Tabellen** aus 5.2.6 verteilt (`moss_card_transactions` +
`moss_card_transaction_bookings`). Jede WSJ27-Spalte fällt in eine von fünf
Kategorien:

**a) Eigene Spalte** (WSJ27-Feld mit > 30 % Füllgrad) — je nach 5.2.6-Aufteilung
transaktions- **oder** buchungs-seitig. Alle Betrags- und Währungsspalten als
`decimal(20,3)` (Beträge) bzw. `decimal(20,8)` (Kurse), auch wenn hier teils
wertgleich. **`home_amount`** (buchungs-seitig) ist der **Abstimmungs-Anker** gegen
`datev_bookings.absolute_base_amount` (Arbeitsthese). `Card Holder Label` /
`Card Label` bleiben (auf Wunsch) als Spalten, obwohl konstant.

**b) `other_columns` (JSONB)** für Spalten, die in > 70 % leer sind — nur befüllt,
wenn ein Wert vorliegt: `Record Type`, `Supplier IBAN/BIC/Vat ID`,
`VAT Code/Name/Rate`, `Unit Price`, `Quantity`, `Card Acceptor Name`,
`Client Number`, `Airline Ticket Number`, `Number of Months in Release Plan`,
`Prepayment Start/End Date`. `Supplier IBAN/BIC/Vat ID` werden bei nur **einem**
Sammelkreditor ohnehin nie befüllt.

**c) Aus `card_transaction_uuid` ableitbar** → **keine** Spalte; das Model
`MossCardTransaction` liefert den abgeleiteten Wert (oder den Override aus
`other_columns`, falls der Import je einen abweichenden Wert speichert):

| Spalte / Methode | Ableitung aus `card_transaction_uuid` |
| --- | --- |
| `moss_record_url` | `https://getmoss.com/app/transactions/all/<uuid>` (183/183) |
| `moss_attachment_url` | diese URL **ohne** `https://` (183/183) |
| `transaction_id_pdf_filename` | `<uuid>.pdf` (183/183) |

**d) Beim Import ignoriert** (im CSV vorhanden, **nicht** gespeichert — ableitbar
oder redundant, auch **nicht** in `other_columns`):

| Spalte | Grund / Ableitung |
| --- | --- |
| `Cost Center - Name` | über `bookings.cost_center_number` → `wsjrdp_cost_centers` auflösbar |
| `Cost Carrier - Name` | über `bookings.sphere_number` (= „Cost Carrier - Number", Sphäre, fix meist `3`=Zweckbetrieb; keine eigene Tabelle nötig) |
| `Category` | **entfernt** — nicht gespeichert (im Ad-hoc == „Account Name"; hier ohne eigenen Nutzen) |
| `Card Name` | = `{Card Purpose} - Virtual - (**** {last4 aus Card Used})` — **183/183** |
| `Period` | = `YYYY-MM` von `Payment Date` (183/183) — **keine** Period-Spalte importiert |
| `Period Day`, `Period Month`, `Accounting Period` | im Datensatz leer; ebenfalls nicht importiert. Ob `Accounting Period` sich vom Payment Date ableitet, ist **nicht belegt** (keine Werte). |

**e) Nicht exportiert** (aus dem WSJ27-Format entfernt, daher gar keine Spalte):
`CSV Line Type`, `Month end date`, `Row Number`, `Transaction Ordinal`,
`Sub Item Row Number`, `Merchant and Card Description`.

`Merchant and Card Description` (= `{Merchant}; {Initial. Nachname}; {last4}`) war
nur **161/183** aus `Cardholder` reproduzierbar (Abkürzung verlustbehaftet) und
wird aus dem Export entfernt.

**Behalten, obwohl im Datensatz konstant** (echte Bedeutung, Konfig/Default):
`Supplier Account`=700002 (Sammelkreditor), `Moss Balance Account`=36100,
`Cash in Transit Account`=13720, `Cost Carrier - Number`=3/„Zweckbetrieb",
`Supplier Name`=„Default Moss Supplier", Währungen=EUR, Kurse=1, `VAT/Fees`=0,
`Transaction State`=ACCEPTED, `Is Prepayment?`=0.

Model: [`app/models/moss_card_transaction.rb`](../app/models/moss_card_transaction.rb)
(+ `AccountingEntry belongs_to :moss_card_transaction`).

### 5.3 Weitere Entitäten (ausstehend)

Für **Rechnungen** und **Rückerstattungen** liegen noch keine Beispiel-Exporte
vor. Sobald sie unter `doc/moss_export_examples/` liegen, werden hier analoge
Tabellen ergänzt. Die Formate **Prepayment**, **Einkauf (Purchase)** und
**Haushalt (Budget)** sind für WSJ derzeit nicht relevant (s. 3.1).

---

## 6. Offene Fragen (Sammlung)

1. **Expense→CSV-Mapping:** Die reichen Buchhaltungsfelder des Kontobewegungen-CSV
   stammen aus `Expense`, nicht `BankTransaction` (s. 5.1.4). Der genaue
   Join/Feld­mapping `Expense`↔CSV ist nicht dokumentiert — bei Bedarf aus der
   lokalen Spec (`schemas/…`) erarbeiten, **nicht** erraten.
2. **`moss_expense_id`:** Tabellenspalte ohne Quellfeld im Kontobewegungen-Export
   — Herkunft klären (anderer Export/API oder ungenutzt?).
3. **Weitere Entitäten:** Für Rechnungen/Rückerstattungen fehlen noch
   Beispiel-Exporte → nach `doc/moss_export_examples/`.
4. **SFTP vs. manuell:** Wird der CSV-Builder-Export automatisiert per SFTP
   ausgeliefert oder manuell heruntergeladen?
5. **Entity-spezifische Hilfeseiten (DE/EN):** bisher belegt ist nur die
   gemeinsame CSV-Feldreferenz (Artikel 11703042). Dedizierte Hilfeseiten je
   Entität/Export-Typ noch sammeln.
6. **Kartentransaktionen — Custom-CSV liegt vor** (`…_WSJ27.csv`, 94 Spalten;
   Analyse 5.2.7). `moss_card_transactions` **revidiert** (86 Spalten, `home_amount`,
   `other_columns` JSONB). Offen: nach Excel-Review evtl. feste Spalten wieder in
   `other_columns` verschieben.
7. **DATEV-Verknüpfung (Kartentransaktion ↔ `datev_bookings`):** Buchungslogik
   geklärt (3-Schritt-Kette 700002/36100/13720, s. 5.2.5); Anker = Schritt-1-
   Buchung (`EXPENSE` → `700002`). Heuristik `invoice_number` deckt 133/157 ab.
   Offen: (a) die 22 Transaktionen **ohne** Rechnungsnummer sind über
   Betrag+Datum+Sachkonto **nicht** eindeutig (s. 5.2.5) → Zusatzmerkmale
   (Kreditor/Karteninhaber/Beleg) nötig; (b) Folge-Migration: Link-Spalten auf
   `datev_bookings` (`moss_card_transaction_id` + Provenienz) nach
   `recon_linking`-Muster. Kreditor `700000` = **Rückerstattungen** (geklärt).
8. **`moss_card_transactions.fin_account_id`:** Welcher FinAccount steht für das
   Kreditkartenkonto? (aktuell nullable, kein Default — anders als bei
   `moss_balance_movements`, das an „Moss Wallet" hängt.)
9. **Belege als eigene Tabelle?** `receipts/` (mehrere je Transaktion) sind
   aktuell nur als `invoice_file_name`-String abgebildet — ggf. Kind-Tabelle
   `moss_card_transaction_receipts` sinnvoll.

*Erledigt:* API-Endpunkte + `BankTransaction`-Schema aus der lokalen OpenAPI-Spec
(Abschnitt 2, 5.1.4); Kartentransaktionen-Exporte analysiert + `moss_card_transactions`
angelegt (5.2).
