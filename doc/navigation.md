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

Der **Finanzen**-Haupteintrag `WSJRDP_MAIN_FIN` zeigt auf `wsjrdp_fin_accounts_path`
und ist `active_for: %w[fin bookkeeping reconciliation]`.

## 2. Linke Unter-Navigation — `fin/_left_nav` + `nav`-Helper

Das Sheet rendert links ein Partial (siehe §4). Für Finanzen ist das
[`app/views/fin/_left_nav.html.haml`](../app/views/fin/_left_nav.html.haml):

```haml
%ul.nav-left-list
  = nav t("fin.nav.payments"), wsjrdp_fin_accounts_path, %w[fin], %w[fin/moss bookkeeping bookings reconciliation]
  = nav t("fin.nav.moss"),     moss_path,                %w[fin/moss]
  = nav t("fin.nav.accounting"), bookkeeping_path,       %w[bookkeeping bookings]
  = nav t("fin.nav.reconciliation"), reconciliation_path, %w[reconciliation]
```

Die **Reihenfolge im Partial = Reihenfolge im Menü**. „Moss" steht zwischen
Zahlungsverkehr und Buchhaltung, weil die `nav`-Zeile dort steht.

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
  matcht `/fin/moss` und `/fin/moss/card_transactions`.
- **Wichtig bei verschachtelten Pfaden:** Weil `fin` auch `/fin/moss` matcht, ist
  „Zahlungsverkehr" ohne Gegenmaßnahme auf Moss-Seiten aktiv. Deshalb steht
  **`fin/moss` in dessen `inactive_for`**. Faustregel: jeder Unterpfad, der einen
  eigenen Menüpunkt hat, gehört in das `inactive_for` des breiteren Eltern-Eintrags.

## 4. Sheets — Auswahl je Controller & Rendering

Core: `app/hitobito/app/helpers/sheet/base.rb`. Das aktuelle Sheet kommt über den
`sheet`-Helper (`Sheet::Base.current(self)`), gewählt **per Controller-Name**:

```ruby
# Sheet::Base.controller_sheet_class
controller.class.name.gsub("Controller", "").underscore.singularize.camelize.prepend("Sheet::")
```

Also: `Fin::MossController` → `Sheet::Fin::Moss`,
`Fin::MossCardTransactionsController` → `Sheet::Fin::MossCardTransaction`
(**singularisiert**: `moss_card_transactions` → `moss_card_transaction`),
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
tab "fin.tabs.card_transactions", :moss_card_transactions_path
```

- Args: i18n-Label-Key, Pfad-Helper-**Symbol**, Options.
- `no_alt: true` = **exakter** Pfad-Match (nur `current_page?`), damit die
  „Übersicht" nicht auch auf den Unterpfaden (`…/card_transactions`) leuchtet.
- Ohne `no_alt` ist ein Tab auch auf Unterpfaden aktiv (z. B. `card_transactions`
  auf `/fin/moss/card_transactions/:id`).

## 6. Rezept: neuer Finanzen-Bereich mit Tabs (wie „Moss")

1. **Routes** (`config/routes.rb`, im `scope "fin", module: "fin"`):
   ```ruby
   get :moss, path: "moss", to: "moss#index", as: "moss"
   resources :moss_card_transactions, path: "moss/card_transactions", only: [:index, :show]
   ```
2. **Controller** je Tab (`app/controllers/fin/…`), abgeleitet von
   `Fin::FinController`, mit `before_action :authorize_action` und
   `authorize!(:fin_admin, WsjrdpFinAccount)`.
3. **Bereichs-Sheet** `Sheet::Fin::Moss` (`app/helpers/sheet/fin/moss.rb`):
   `tab …`-Zeilen, `left_nav?` → true, `render_left_nav` → `"fin/left_nav"`,
   `title`. Dieses Sheet bedient zugleich den Übersichts-Controller
   (`Fin::MossController` → `Sheet::Fin::Moss`).
4. **Kind-Sheet** je weiterem Controller
   (`app/helpers/sheet/fin/moss_card_transaction.rb`): innerhalb `class Fin::Moss`
   verschachtelt, `parent_sheet = Sheet::Fin::Moss`, `always_render_parent = true`,
   `title`.
5. **Linke Nav** (`app/views/fin/_left_nav.html.haml`): `nav`-Zeile an der
   gewünschten Position einfügen; das neue Pfad-Fragment ins `inactive_for` der
   breiteren Nachbar-Einträge aufnehmen (hier `fin/moss` bei „Zahlungsverkehr").
6. **i18n** (`config/locales/wsjrdp_2027.de.yml`): `fin.nav.<key>` und
   `fin.tabs.<key>` ergänzen (`fin.tabs.overview` existiert bereits).
7. **Views** (`app/views/fin/<controller>/index.html.haml`, ggf. `show.html.haml`)
   mit `#main`-Wrapper.

**Namens-Fallstricke:**
- Controller `Fin::MossCardTransactionsController` → Sheet **singular**:
  `Sheet::Fin::MossCardTransaction`.
- Kind-Sheet muss unter `module Sheet; class Fin::Moss < Base; class Fin::MossCardTransaction …`
  verschachtelt liegen (siehe bestehende `sheet/fin/booking.rb` /
  `sheet/fin/bookkeeping.rb`).

## Beteiligte Dateien (Moss-Beispiel)

| Zweck | Datei |
| --- | --- |
| Routes | `config/routes.rb` (`get :moss …`, `resources :moss_card_transactions …`) |
| Übersicht-Controller | `app/controllers/fin/moss_controller.rb` |
| Kartentransaktionen-Controller | `app/controllers/fin/moss_card_transactions_controller.rb` |
| Bereichs-Sheet (Tabs + linke Nav) | `app/helpers/sheet/fin/moss.rb` |
| Kind-Sheet (Detailseite) | `app/helpers/sheet/fin/moss_card_transaction.rb` |
| Linke Unter-Nav | `app/views/fin/_left_nav.html.haml` |
| Views | `app/views/fin/moss/index.html.haml`, `app/views/fin/moss_card_transactions/{index,show}.html.haml` |
| i18n | `config/locales/wsjrdp_2027.de.yml` (`fin.nav.moss`, `fin.tabs.card_transactions`) |
| Hauptnav (oben) | `app/helpers/wsjrdp_2027/navigation_helper.rb` |
