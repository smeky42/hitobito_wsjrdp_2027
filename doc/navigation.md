# Navigation, Sheets & Tabs (Hitobito + Wagon)

Wie hängen **Hauptnavigation** (oben), **linke Unter-Navigation** und **Tabs**
zusammen, und wie fügt man einen neuen Bereich mit Tabs hinzu? Konkret am
Beispiel des **Finanzen**-Bereichs und der Erweiterung um **Moss**.

Kurzfassung: Ein **Sheet** ist die Rails-seitige Beschreibung einer Seite
(Titel, linke Nav, Tabs, Elternseite). Für jeden Controller wird per Namens­
konvention ein Sheet gewählt. Das Sheet rendert links die Unter-Navigation
(ein Haml-Partial) und oben die **Tabs**.

## 1. Hauptnavigation (oben) — `NavigationHelper`

Core-Datei: `app/hitobito/app/helpers/navigation_helper.rb` mit `NavigationHelper::MAIN`
(Array von Einträgen). Der Wagon patcht das in
[`app/helpers/wsjrdp_2027/navigation_helper.rb`](../app/helpers/wsjrdp_2027/navigation_helper.rb):

- Entfernt ungenutzte Einträge (`:invoices`, Core-`:groups`) und fügt eigene ein
  (`WSJRDP_MAIN_GROUPS`, `WSJRDP_MAIN_FIN`, `WSJRDP_MAIN_CONTINGENT`) an
  definierten Positionen (`MAIN.insert(...)`).
- Jeder Eintrag ist ein Hash: `label:` (i18n), `url:` (Pfad-Helper-Symbol),
  `icon_name:`, `if:` (Sichtbarkeit, z. B. `->(_) { can?(:fin_admin, WsjrdpFinAccount) }`),
  `active_for:` / `inactive_for:` (siehe §3, gleiche Matching-Logik).

Der **Finanzen**-Haupteintrag `WSJRDP_MAIN_FIN` zeigt auf `fin_path`
(die Übersichtsseite `/fin`); da alle Finanzseiten unter `/fin` liegen,
genügt `active_for: %w[fin]`.

Die Übersichtsseite `/fin` zeigt pro Bereich eine **Karte**: Icon, ein Satz zum
Zweck des Bereichs (`fin.areas.<key>.purpose`), die Quicklinks zu seinen Tabs
und zwei bis drei Kennzahlen (`Fin::OverviewFigures`). Links schreibt sie keine
von Hand: `Fin::OverviewHelper#fin_areas` leitet Bereichslink und Quicklinks aus
den `tab`-Deklarationen der sechs `Sheet::Fin::*`-Sheets ab (§5); nur Icon und
Locale-Key stehen in `Fin::OverviewHelper::AREAS`. Der „Übersicht"-Tab wird
dabei am Label-Key `fin.tabs.overview` erkannt und weggelassen, weil er den
Bereichslink verdoppelt; ein Bereich ohne Übersicht-Tab (Konten & Wallets)
verlinkt seinen ersten Tab. Ein neuer Tab in einem Sheet erscheint damit von
selbst auf `/fin`.

Unter dem Quicklink „Konten" listet die Karte eingerückt jedes Konto der
Konten-Seite mit seinem aktuellen Saldo
(`Fin::OverviewHelper#fin_accounts_with_balance`; die Salden kommen aus zwei
gruppierten SQL-Summen — eine je Art von Kontoauszugszeile —, damit die Seite
nicht jede Transaktion und jede Buchung nach Ruby lädt). Hinter jedem
Quicklink und hinter jedem dieser Kontolinks steht das kleine
Neuer-Tab-Icon (`wsjrdp_newtab_link` aus `Fin::LabeledRowsHelper`); die
Kartenüberschrift, die auf den Bereich selbst zeigt, bleibt ohne.

## 2. Linke Unter-Navigation — `fin/_left_nav` + `nav`-Helper

Das Sheet rendert links ein Partial (siehe §4). Für Finanzen ist das
[`app/views/fin/_left_nav.html.haml`](../app/views/fin/_left_nav.html.haml):

```haml
%ul.nav-left-list
  = nav t("fin.nav.overview"), fin_path
  = nav t("fin.nav.accounts"), wsjrdp_fin_accounts_path, %w[fin/acc fin/tx]
  = nav t("fin.nav.fees"),     fees_path,                %w[fin/fees fin/person_fees fin/payment_plans]
  = nav t("fin.nav.moss"),     moss_path,                %w[fin/moss]
  = nav t("fin.nav.accounting"), bookkeeping_path,       %w[fin/bookkeeping]
  = nav t("fin.nav.reconciliation"), reconciliation_path, %w[fin/reconciliation]
  = nav t("fin.nav.controlling"), controlling_path,      %w[fin/controlling]
```

Der Übersichts-Eintrag braucht keine Fragmente (`current_page?` matcht
`/fin` exakt). Jeder andere Eintrag listet **nur seine eigenen** Pfad-Fragmente
— alle Seiten seines Bereichs, nicht mehr —, deshalb kommt keiner ohne
`inactive_for` in die Quere (§3).

Die **Reihenfolge im Partial = Reihenfolge im Menü**. „Moss" steht zwischen
Beiträge und Buchhaltung, weil die `nav`-Zeile dort steht.

## 3. Wann ist ein Nav-Eintrag „aktiv"? — `section_active?`

Core `NavigationHelper#nav(label, url, active_for = [], inactive_for = [])` setzt
die CSS-Klasse `is-active`, wenn `section_active?` true ist:

```ruby
current_page?(url) ||
  (active_for.any?   { |p| request.path =~ %r{/?#{p}/?} } &&
   inactive_for.none?{ |p| request.path =~ %r{/?#{p}/?} })
```

- `active_for`/`inactive_for` sind **Pfad-Fragmente als Regex** gegen
  `request.path`. `fin` matcht `/fin`, `/fin/moss`, `/fin/acc` …; `fin/moss`
  matcht `/fin/moss` und `/fin/moss/transactions`.
- **Wichtig bei verschachtelten Pfaden:** Ein zu breites Fragment leuchtet auch
  auf fremden Seiten — `fin` allein würde auf jeder Finanzseite matchen und
  bräuchte `fin$ fin/moss fin/bookkeeping fin/reconciliation …` als
  `inactive_for`. Regel in `fin/_left_nav`: **jeder Eintrag listet nur die
  Fragmente seiner eigenen Seiten** (`fin/acc fin/tx` für Konten & Wallets,
  `fin/fees fin/person_fees fin/payment_plans` für Beiträge, …), dann ist kein
  `inactive_for` nötig. Wer doch ein breiteres Fragment braucht, nimmt jeden
  Unterpfad mit eigenem Menüpunkt in dessen `inactive_for` auf.
- **Neue Fragmente gegen die Nachbarn prüfen:** Es ist ein reiner
  Teilstring-Match, also darf `fin/acc` z. B. keinen Pfad eines anderen
  Bereichs treffen (`/fin/bookkeeping/ledger_accounts` enthält kein `fin/acc`,
  passt also). `/fin/ae` (Beitragsbuchungen) und `/fin/pn`
  (Pre-Notifications) hängen unter der Person und tauchen in dieser Nav
  bewusst nirgends auf.

## 4. Sheets — Auswahl je Controller & Rendering

Core: `app/hitobito/app/helpers/sheet/base.rb`. Das aktuelle Sheet kommt über den
`sheet`-Helper (`Sheet::Base.current(self)`), gewählt **per Controller-Name**:

```ruby
# Sheet::Base.controller_sheet_class
controller.class.name.gsub("Controller", "").underscore.singularize.camelize.prepend("Sheet::")
```

Also: `Fin::MossController` → `Sheet::Fin::Moss`,
`Fin::MossTransactionsController` → `Sheet::Fin::MossTransaction`
(**singularisiert**: `moss_transactions` → `moss_transaction`),
`Fin::BookkeepingController` → `Sheet::Fin::Bookkeeping`.

Weitere Sheet-Bausteine:

- `parent_sheet` (`class_attribute`): verschachtelte Seite; das Eltern-Sheet
  liefert Titel-Kontext, linke Nav und Tabs.
- `always_render_parent` (Wagon-Konvention, eigenes `class_attribute`): auf einer
  Detailseite trotzdem die Eltern-Tabs/-Nav rendern.
- **`index`-Sonderfall:** In `sheet_for_controller` gilt: hat das Controller-Sheet
  ein `parent_sheet` **und** die Action ist `index`, wird direkt das **Eltern**-Sheet
  benutzt. → Listen-/Index-Seiten laufen unter dem Bereichs-Sheet (mit den Tabs),
  Detailseiten (`show`) unter dem Kind-Sheet.
- `left_nav?` (→ true) + `render_left_nav` (→ `view.render("fin/left_nav")`)
  schalten die linke Unter-Nav ein. Nur das **Bereichs-Sheet** braucht das;
  Kind-Sheets erben es über `parent_sheet` (Core `render_left_nav` delegiert an
  `root`).

## 5. Tabs — `tab`-Deklaration im Sheet

Im Sheet deklariert, oben auf der Seite gerendert:

```ruby
tab "fin.tabs.overview", :moss_path, no_alt: true
tab "fin.tabs.transactions", :moss_transactions_path
tab :moss_card_transactions_tab_label, :moss_card_transactions_path  # eine von vier Art-Tabs
```

- Args: i18n-Label-Key, Pfad-Helper-**Symbol**, Options.
- **Label als Symbol = Helper-Methode.** Ist das erste Argument ein Symbol statt
  eines i18n-Keys, ruft der Core die gleichnamige **Helper-Methode** mit dem
  Sheet-Entry als einzigem Argument auf und gibt deren Rückgabewert an `link_to`
  (`Sheet::Tab::Renderer#label`); ein `html_safe`-String wird also als **HTML**
  gerendert. So tragen die vier Art-Tabs das Icon ihrer Art vor dem Wort, ohne
  dass der Core gepatcht werden muss — die Methoden
  (`moss_card_transactions_tab_label` …) stehen in
  `Fin::MossTransactionsHelper` und holen das Wort weiterhin aus
  `fin.tabs.<slug>`.
- **Folge für `/fin`:** Die Quicklinks der Übersichtsseite sind dieselben
  `renderer.label` (§1), zeigen also dasselbe HTML — die Art-Links dort tragen
  die Icons ebenfalls. Wer ein Symbol-Label einführt, prüft daher beide Stellen.
- `no_alt: true` = **exakter** Pfad-Match (nur `current_page?`), damit die
  „Übersicht" nicht auch auf den Unterpfaden (`…/transactions`) leuchtet.
- Ohne `no_alt` ist ein Tab auch auf Unterpfaden aktiv (z. B. `transactions`
  auf `/fin/moss/transactions/:id`).
- **Ein Tab braucht keinen eigenen Controller.** Die vier Art-Tabs des
  Moss-Bereichs (Kartenzahlungen, Erstattungen, Rechnungen, Einzahlungen) sind
  dieselbe Liste wie „Transaktionen", auf eine Art festgelegt: eigene Routen
  (`/fin/moss/invoices` …) auf `moss_transactions#index` mit der Art als
  **Routen-Default** (`kind: "MossInvoice"`), also ein Pfad-Helper je Tab —
  das Muster der Anlässe/Kurse-Tabs von Hitobito (`events#index` mit
  `type: 'Event::Course'`). Der Controller liest die Art aus
  `request.path_parameters` und legt sie als versteckten Fix-Slot des
  Tabellen-Filters fest (`Fin::MossTransactionsController::KIND_TABS`).

## 6. Rezept: neuer Finanzen-Bereich mit Tabs (wie „Moss")

1. **Routes** (`config/routes.rb`, im `scope "fin", module: "fin"`):
   ```ruby
   get :moss, path: "moss", to: "moss#index", as: "moss"
   resources :moss_transactions, path: "moss/transactions", only: [:index, :show]
   ```
2. **Controller** je Tab (`app/controllers/fin/…`), abgeleitet von
   `Fin::FinController`, mit `before_action :authorize_action` und
   `authorize!(:fin_admin, WsjrdpFinAccount)`.
3. **Bereichs-Sheet** `Sheet::Fin::Moss` (`app/helpers/sheet/fin/moss.rb`):
   `tab …`-Zeilen, `left_nav?` → true, `render_left_nav` → `"fin/left_nav"`,
   `title`. Dieses Sheet bedient zugleich den Übersichts-Controller
   (`Fin::MossController` → `Sheet::Fin::Moss`).
4. **Kind-Sheet** je weiterem Controller
   (`app/helpers/sheet/fin/moss_transaction.rb`): innerhalb `class Fin::Moss`
   verschachtelt, `parent_sheet = Sheet::Fin::Moss`, `always_render_parent = true`,
   `title`.
5. **Linke Nav** (`app/views/fin/_left_nav.html.haml`): `nav`-Zeile an der
   gewünschten Position einfügen, mit den Pfad-Fragmenten **aller** Seiten des
   Bereichs (`fin/acc fin/tx` bei „Konten & Wallets") — und prüfen, dass keines
   davon in einen Nachbar-Bereich hineinmatcht (§3).
6. **i18n** (`config/locales/wsjrdp_2027.de.yml`): `fin.nav.<key>` und
   `fin.tabs.<key>` ergänzen (`fin.tabs.overview` existiert bereits).
7. **Views** (`app/views/fin/<controller>/index.html.haml`, ggf. `show.html.haml`)
   mit `#main`-Wrapper.

**Namens-Fallstricke:**
- Controller `Fin::MossTransactionsController` → Sheet **singular**:
  `Sheet::Fin::MossTransaction`.
- Auch der Übersichts-Controller eines Bereichs wird singularisiert:
  `Fin::FeesController` → `Sheet::Fin::Fee`, **nicht** `Sheet::Fin::Fees`.
  Deshalb hat der Beiträge-Bereich ein Kind-Sheet `Sheet::Fin::Fee` mit
  `parent_sheet = Sheet::Fin::Fees`; über den `index`-Sonderfall (§4) rendert
  die Seite dann das Bereichs-Sheet mit dessen Tabs. Bereiche, deren Name schon
  singular ist (`moss`, `bookkeeping`, `controlling`), brauchen das nicht.
- Kind-Sheet muss unter `module Sheet; class Fin::Moss < Base; class Fin::MossCardTransaction …`
  verschachtelt liegen (siehe bestehende `sheet/fin/booking.rb` /
  `sheet/fin/bookkeeping.rb`).

## Beteiligte Dateien (Moss-Beispiel)

| Zweck | Datei |
| --- | --- |
| Routes | `config/routes.rb` (`get :moss …`, `resources :moss_transactions …`) |
| Übersicht-Controller | `app/controllers/fin/moss_controller.rb` |
| Transaktionen-Controller | `app/controllers/fin/moss_transactions_controller.rb` |
| Bereichs-Sheet (Tabs + linke Nav) | `app/helpers/sheet/fin/moss.rb` |
| Kind-Sheet (Detailseite) | `app/helpers/sheet/fin/moss_transaction.rb` |
| Linke Unter-Nav | `app/views/fin/_left_nav.html.haml` |
| Views | `app/views/fin/moss/index.html.haml`, `app/views/fin/moss_transactions/{index,show}.html.haml` |
| i18n | `config/locales/wsjrdp_2027.de.yml` (`fin.nav.moss`, `fin.tabs.transactions`, `fin.tabs.card_transactions` … für die Art-Tabs) |
| Hauptnav (oben) | `app/helpers/wsjrdp_2027/navigation_helper.rb` |
