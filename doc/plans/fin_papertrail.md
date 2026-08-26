# Plan: PaperTrail für Fin-Stammdaten (eigene Versionstabelle)

Status: **PLAN — nicht umgesetzt** (Stand 2026-08-24). Gehört zum
Budget-Vorhaben für Kostenstellen/Sphären; die Budget-Spalten (Jahresbudgets
2025–2028 + `explicit_total_budget` + generiertes `effective_total_budget`)
sind **bereits gebaut** (Create-Migration
`20260818000100_add_wsjrdp_cost_centers.rb`) — dieser Plan ergänzt nur die
Versionierung.

**Ziel:** Änderungen an `WsjrdpCostCenter` und `WsjrdpSphere` (v. a. Budgets,
Manager, Status) nachvollziehbar machen — wer hat wann welches Feld von → auf
geändert. Aufzeichnung über die vorhandene PaperTrail-Infrastruktur
(paper_trail 15.1), aber in eine **wagon-eigene Tabelle** statt in die große
Core-Tabelle `versions`.

## 1. Warum eigene Tabelle

* **Isolation:** Die Core-Tabelle `versions` trägt die Personen-/Gruppen-Logs
  des Systems; Fin-Referenzdaten haben dort nichts verloren (eigene
  Aufbewahrungs-/Löschregeln möglich, Prod-Deploy fasst keine Core-Tabelle an).
* **`jsonb` statt `text`:** PaperTrail erkennt json(b)-Spalten für
  `object`/`object_changes` automatisch und serialisiert dann JSON statt YAML
  ⇒ Änderungen sind per SQL abfragbar (`object_changes ? 'budget_2026'`),
  Decimals landen sauber als Strings.
* **`bigint item_id`:** Core-`versions.item_id` ist `integer`; unsere IDs sind
  `bigserial`.

Geteilt bleibt die gesamte Infrastruktur: der Core-Concern `PaperTrailed`
(in `ApplicationController` eingebunden — gilt damit automatisch für alle
Fin-Controller, **verifiziert**) setzt `whodunnit`, `whodunnit_type` und
`mutation_id` (`request-<id>`) global über `PaperTrail.request`; `reify`,
`versions`-Assoziation und `object_changes` funktionieren unverändert.

## 2. Neue Tabelle `wsjrdp_versions`

Neue Wagon-Migration `db/migrate/20260824000100_add_wsjrdp_versions.rb`
(eigene Migration; die Create-Migrationen der Fin-Tabellen bleiben unberührt):

| Spalte | Typ | Anmerkung |
|---|---|---|
| `id` | `bigserial` PK | |
| `item_type` | `string NOT NULL` | z. B. `WsjrdpCostCenter` |
| `item_id` | `bigint NOT NULL` | bewusst bigint (Abweichung vom Core) |
| `event` | `string NOT NULL` | create / update / destroy |
| `whodunnit` | `string` | Person-/ServiceToken-ID (vom Core-Concern) |
| `whodunnit_type` | `string NOT NULL DEFAULT 'Person'` | **Pflicht**: globale `controller_info` schreibt das Feld — fehlt die Spalte, schlägt jeder Web-Schreibvorgang mit „unknown attribute" fehl |
| `object` | `jsonb` | Zustand vor der Änderung (NULL bei create) |
| `object_changes` | `jsonb` | Diff `{feld: [alt, neu]}` |
| `main_type` / `main_id` | `string` / `bigint` | wie Core (`meta`-Eintrag, zeigt auf den Datensatz selbst); nötig, weil `WsjrdpVersion` von `PaperTrail::Version` erbt (`belongs_to :main`) |
| `mutation_id` | `string` | **Pflicht** (globale `controller_info`), gruppiert Änderungen eines Requests |
| `created_at` | `datetime` | |

Indizes: `[item_type, item_id]`, `[main_type, main_id]`, `mutation_id` —
wie im Core.

## 3. Neue Dateien

* **`app/models/wsjrdp_version.rb`** — Subklasse statt eigenem Concern-Mix,
  damit `perpetrator` (whodunnit → Person) und `belongs_to :main` geerbt
  werden:

  ```ruby
  class WsjrdpVersion < PaperTrail::Version
    self.table_name = "wsjrdp_versions"
  end
  ```

* **`app/models/concerns/wsjrdp_fin_paper_trailed.rb`** — ein Mini-Concern,
  damit die `has_paper_trail`-Optionen nur an einer Stelle stehen:

  ```ruby
  module WsjrdpFinPaperTrailed
    extend ActiveSupport::Concern
    included do
      has_paper_trail versions: {class_name: "WsjrdpVersion"},
        meta: {main_id: ->(r) { r.id }, main_type: ->(r) { r.class.name }}
    end
  end
  ```

* **`app/views/fin/bookkeeping/_versions.html.haml`** — wiederverwendbares
  Partial „Änderungen" (siehe §5).
* Helper-Methoden (im vorhandenen `WsjrdpBookkeepingHelper`):
  Versionszeilen aufbereiten (Datum, `perpetrator`, Feld alt → neu mit
  `human_attribute_name`-Labels).

## 4. Anpassungen an bestehenden Dateien

| Datei | Änderung |
|---|---|
| `app/models/wsjrdp_cost_center.rb` | `include WsjrdpFinPaperTrailed` |
| `app/models/wsjrdp_sphere.rb` | `include WsjrdpFinPaperTrailed` |
| `config/locales/wsjrdp_2027.de.yml` | `activerecord.attributes.wsjrdp_cost_center.*` / `…wsjrdp_sphere.*` für deutsche Feldnamen in der Änderungsliste (budget_2025 → „Budget 2025" usw.) |
| `app/views/fin/bookkeeping/cost_center.html.haml` | Partial `_versions` einbinden (nur Standalone-Seite) |
| Controller | **keine** — `PaperTrailed` kommt über `ApplicationController` |

Spec-Idee (Wagon): Update an einer Kostenstelle erzeugt genau eine Zeile in
`wsjrdp_versions` (und keine in `versions`), `object_changes` ist jsonb und
enthält das Feld; `reify` liefert den Vorzustand. (Achtung Test-DB-Falle:
Specs im Dev-Container nur mit `RAILS_TEST_DB_NAME`.)

## 5. Geplante UI-Änderungen

1. **Kostenstellen-Detailseite** (`/bookkeeping/cost_centers/:number`,
   Standalone-Ansicht): neuer Abschnitt **„Änderungen"** unterhalb von
   Metadaten + eingebetteter Buchungsliste. Tabelle mit
   `Datum · Wer · Änderung`; „Wer" als Link auf die Person
   (`version.perpetrator`), „Änderung" als eine Zeile je Feld im Format
   „Budget 2026: 〈alt〉 → 〈neu〉" (Beträge über `eur_display_or_nil`
   formatiert, deutsche Labels über die Locale). Standard: die letzten
   ~10 Versionen, darüber ein „alle anzeigen"-Link (`?versions=all`).
2. **Inline-Detailzeilen** der Kostenstellen-Liste zeigen den Block bewusst
   **nicht** (hält die lazy geladenen Turbo-Frames klein; eine Query je
   aufgeklappter Zeile gespart).
3. **Sphären:** haben derzeit weder Liste noch Detailseite im
   Buchhaltungs-UI. Vorschlag: eigene kleine Seite
   `/bookkeeping/spheres/:number` analog zur Kostenstellen-Seite (Metadaten +
   Budget-Block + Änderungen); bis dahin bleibt der Sphären-PaperTrail zwar
   aufgezeichnet, aber ohne eigene Anzeige.
4. **Kein Bearbeitungs-UI in diesem Plan.** Die Budget-Erfassungsmaske (die
   die Versionen überhaupt erst erzeugt) gehört zum Budget-Plan; solange es
   sie nicht gibt, entstehen Versionen nur über Rails-Konsole/Seeds.

## 6. Grenzen & Risiken

* **Python-Importer erzeugt keine Versionen.** `import_datev_cost_centers.py`
  schreibt per psycopg an ActiveRecord vorbei — Import-Updates (Name, Status,
  `manager_name`, Auto-Verknüpfung `manager_person_id`) bleiben unversioniert.
  Akzeptiert: Historie gilt den Änderungen durch Menschen im UI.
* **Pflicht-Metaspalten**: `whodunnit_type` und `mutation_id` müssen in der
  neuen Tabelle existieren (globale `controller_info`), sonst bricht jeder
  Schreibvorgang aus einem Request.
* Die generierte Spalte `effective_total_budget` erscheint nicht in
  `object_changes` (nicht schreibbar) — gewollt, sie ist ableitbar.
* jsonb serialisiert Decimals als Strings; `reify` castet über die
  AR-Typen zurück — kein Präzisionsverlust.

## 7. Offene Entscheidungen

* Scope später erweitern auf weitere Fin-Modelle (`WsjrdpPersonalAccount`,
  `WsjrdpLedgerAccount`, manuelle Verknüpfungsfelder von `DatevBooking`)?
  Der Concern macht das zu je einer Zeile.
* `only:`/`ignore:`-Liste je Modell (aktuell: alles tracken)?
* Sphären-Detailseite sofort mitbauen oder nachziehen?

## 8. Umsetzungsreihenfolge

1. Migration `wsjrdp_versions` + Modell `WsjrdpVersion` + Concern.
2. `include` in beiden Modellen; Konsolen-Smoke-Test (Update ⇒ Zeile in
   `wsjrdp_versions`, `object_changes` jsonb, `perpetrator` NULL in Konsole).
3. Locale-Labels.
4. Partial + Helper + Einbindung Kostenstellen-Seite; Test über einen echten
   Web-Edit (sobald Budget-Formular existiert) oder Konsole mit
   `PaperTrail.request(whodunnit: …)`.
5. Optional: Sphären-Seite.
