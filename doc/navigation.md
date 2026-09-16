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
  `icon_name:`, `if:` (Sichtbarkeit, z. B. `->(_) { can?(:show, WsjrdpFinAccount) }`),
  `active_for:` / `inactive_for:` (siehe §3, gleiche Matching-Logik).

Der **Finanzen**-Haupteintrag `WSJRDP_MAIN_FIN` zeigt auf `fin_path`
(die Übersichtsseite `/fin`); da alle Finanzseiten unter `/fin` liegen,
genügt `active_for: %w[fin]`.

Die Übersichtsseite `/fin` zeigt pro Bereich eine **Karte**: Icon, ein Satz zum
Zweck des Bereichs (`fin.areas.<key>.purpose`), die Quicklinks zu seinen Tabs
und zwei bis drei Kennzahlen (`Fin::OverviewFigures`). Links schreibt sie keine
von Hand: `Fin::OverviewHelper#fin_areas` leitet Bereichslink und Quicklinks aus
den `tab`-Deklarationen der `Sheet::Fin::*`-Sheets ab (§5); nur Icon und
Locale-Key stehen in `Fin::OverviewHelper::AREAS`. Der „Übersicht"-Tab wird
dabei am Label-Key `fin.tabs.overview` erkannt und weggelassen, weil er den
Bereichslink verdoppelt; ein Bereich ohne Übersicht-Tab (Konten & Wallets,
Verwaltung) verlinkt seinen ersten Tab. Ein neuer Tab in einem Sheet erscheint
damit von selbst auf `/fin`. Ein Bereich, dessen Tabs **alle** verborgen sind,
bekommt keine Karte — so bleibt die Verwaltung, deren beide Tabs die Bedingung
`can?(:configure_finance, Group)` tragen, für alle anderen von `/fin` weg.

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
  - if can?(:configure_finance, Group)
    = nav t("fin.nav.admin"), fin_admin_path,             %w[fin/admin]
```

Der Übersichts-Eintrag braucht keine Fragmente (`current_page?` matcht
`/fin` exakt). Jeder andere Eintrag listet **nur seine eigenen** Pfad-Fragmente
— alle Seiten seines Bereichs, nicht mehr —, deshalb kommt keiner ohne
`inactive_for` in die Quere (§3).

Die Verwaltung ist der einzige Eintrag mit einer Bedingung: Ihre Seiten
konfigurieren den Finanzen-Bereich selbst, deshalb sehen sie nur Admins und die
Manage-Stufe (§8).

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
   `authorize!(:show, <Modell des Bereichs>)` -- die Moss-Controller fragen
   `MossTransaction`, die Buchhaltung `DatevBooking`.
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

## 7. Gruppen-Seite: Tab „Finanzen" mit Unter-Tabs

Die Gruppenseite (`/groups/:id`) trägt neben ihren Core-Tabs den Tab
**Finanzen**; dahinter liegen eigene Unter-Tabs, zunächst nur **Buchhaltung**.

Die Buchhaltung zeigt die **Kostenstellen der Gruppe** als Chips (Nummer +
`display_short_name`), gelesen aus `Group#cost_centers`, also aus
`groups.additional_info["cost_center_numbers"]`. Ein Chip verlinkt die
Kostenstelle nur, wenn `can?(:show, WsjrdpCostCenter)` gilt — eine Unit-Leitung
kommt über ihre eigene Gruppe auf die Seite und hält im Finanzen-Bereich
nichts. Ohne Zuordnung steht dort `groups.finance.bookkeeping.no_cost_centers`.
Zugeordnet werden die Nummern ausschließlich in der Verwaltung (§8).

### Tab in der Gruppen-Sheet-Liste

[`app/helpers/wsjrdp_2027/sheet/group.rb`](../app/helpers/wsjrdp_2027/sheet/group.rb)
patcht `Sheet::Group`. Der Wagon filtert und sortiert die Tabs über die
Whitelist `shown_tabs` — ein Tab braucht daher **beides**: den Eintrag in
`shown_tabs` (Position dort = Position im Menü; `groups.tabs.finance` steht am
Ende) und die Deklaration:

```ruby
tab "groups.tabs.finance",
  :group_finance_bookkeeping_path,
  if: :show_finance
```

`if:` als **Symbol** heißt für den Core `view.can?(:show_finance, group)`
(`Sheet::Tab::Renderer#show?`, §5): Wer die Seite dahinter nicht öffnen darf,
sieht den Tab nicht.

### Die Sheet-Kette

| Sheet | Datei | Rolle |
| --- | --- | --- |
| `Sheet::Group` | Core + Wagon-Patch | Haupt-Tabs der Gruppenseite |
| `Sheet::Group::Finance` | [`app/helpers/sheet/group/finance.rb`](../app/helpers/sheet/group/finance.rb) | Bereichs-Sheet, trägt die Unter-Tabs |
| `Sheet::Group::Bookkeeping` | [`app/helpers/sheet/group/bookkeeping.rb`](../app/helpers/sheet/group/bookkeeping.rb) | Blatt-Sheet der Buchhaltung |

`Sheet::Group::Finance` setzt `parent_sheet = Sheet::Group` und überschreibt
zwei Methoden:

- **`model_name` → `"group"`**: `find_entry` holt den Sheet-Entry als
  `@<model_name>` aus dem View, sonst also `@finance` statt `@group` (§4; der
  Core macht das in `Sheet::Group::Statistic` genauso).
- **`path_args` → `parent_sheet.path_args`**: `Sheet::Base#path_args` eines
  verschachtelten Sheets ist `parent_sheet.path_args + [entry]`. Bei einer
  Person passt das (Gruppe + Person); bei einer Gruppe stünde dieselbe Gruppe
  zweimal darin, und Rails nähme das zweite Argument als **Format** —
  `group_map_path(8, 8)` ergibt `/groups/8/map.8`. Die Finanz-Sheets zeigen die
  Gruppe des Gruppen-Sheets, und die Pfad-Helper nehmen sie genau einmal.

`Sheet::Group::Bookkeeping` erbt von `Sheet::Group::Finance` und ändert nur den
Titel; die `tab`-Zeilen erbt es mit. Auf das Sheet abgebildet wird
`Group::BookkeepingController` über die Namenskonvention aus §4.

### Welche Tabs kommen von welchem Sheet?

Das Layout rendert `sheet.render_main_tabs` vom **aktuellen** Sheet, die
Eltern-Sheets über `render_sheets`. Auf `/groups/:id/finance/bookkeeping` heißt
das:

- das Blatt-Sheet (`Sheet::Group::Bookkeeping`) liefert die **Unter-Tabs**, die
  es von `Sheet::Group::Finance` geerbt hat;
- das Eltern-Sheet (`Sheet::Group`) rendert in `render_as_parent` die
  **Haupt-Tabs** der Gruppenseite.

### Action `show`, nicht `index`

`sheet_for_controller` tauscht bei der Action `index` das Controller-Sheet
gegen sein `parent_sheet` (§4). Ein `index` liefe damit unter
`Sheet::Group::Finance` statt unter `Sheet::Group::Bookkeeping` — die
Unter-Tabs fielen weg. Deshalb heißt die Action `show`.

### Berechtigung, Route, i18n

- **Gate:** `Group::BookkeepingController#authorize_action` fragt
  `authorize!(:show_finance, group)`. Alles, was auf diesen Seiten
  **schreibt**, autorisiert zusätzlich `:update_finance`. Wer die beiden
  Rechte hält, steht in [`doc/roles.md`](roles.md) → „Finance on a group's
  page".
- **Route** (`config/routes.rb`, innerhalb `resources :groups do … end`):

  ```ruby
  get "finance/bookkeeping" => "group/bookkeeping#show", as: :finance_bookkeeping
  ```

  Das ergibt den Helper `group_finance_bookkeeping_path(group)` für
  `/groups/:group_id/finance/bookkeeping`.
- **i18n** (`config/locales/wsjrdp_2027.de.yml`): `groups.tabs.finance` für den
  Haupt-Tab, `groups.finance.tabs.bookkeeping` für den Unter-Tab,
  `groups.finance.bookkeeping.title`, `.cost_centers` und `.no_cost_centers`
  für die Seite selbst.

### Rezept: ein weiterer Unter-Tab

1. Eine `tab`-Zeile in `Sheet::Group::Finance` ergänzen:
   `tab "groups.finance.tabs.<key>", :group_finance_<key>_path, if: :show_finance`.
2. Blatt-Sheet `Sheet::Group::<Key>` anlegen, von `Sheet::Group::Finance`
   abgeleitet, mit eigenem `title`.
3. Controller `Group::<Key>Controller` mit der Action **`show`** und
   `before_action :authorize_action` → `authorize!(:show_finance, group)`.
4. Route `get "finance/<key>" => "group/<key>#show", as: :finance_<key>`
   innerhalb `resources :groups`.
5. i18n-Keys ergänzen.
6. Auf dem „Finanzen"-Tab in `wsjrdp_2027/sheet/group.rb` ein `alt:` mit dem
   neuen Pfad-Helper eintragen, damit der Haupt-Tab auch auf dem neuen
   Unterpfad aktiv bleibt.

### Beteiligte Dateien (Finanzen-Tab)

| Zweck | Datei |
| --- | --- |
| Haupt-Tab + Whitelist | `app/helpers/wsjrdp_2027/sheet/group.rb` |
| Bereichs-Sheet (Unter-Tabs) | `app/helpers/sheet/group/finance.rb` |
| Blatt-Sheet | `app/helpers/sheet/group/bookkeeping.rb` |
| Controller | `app/controllers/group/bookkeeping_controller.rb` |
| View | `app/views/group/bookkeeping/show.html.haml` |
| Route | `config/routes.rb` (`get "finance/bookkeeping" …`) |
| i18n | `config/locales/wsjrdp_2027.de.yml` (`groups.tabs.finance`, `groups.finance.*`) |
| Rechte | `app/abilities/wsjrdp_2027/group_ability.rb` |

## 8. Verwaltung (`/fin/admin`)

Der letzte Bereich der linken Unter-Navigation. Er konfiguriert den
Finanzen-Bereich selbst und hat zwei Tabs:

| Tab | Pfad | Was er bearbeitet |
| --- | --- | --- |
| Gruppen-Finanzzugriff | `/fin/admin/finance_groups` | `people.additional_info["finance_group_ids"]` |
| Gruppen-Kostenstellen | `/fin/admin/group_cost_centers` | `groups.additional_info["cost_center_numbers"]` |

Diese beiden Seiten sind die **einzigen** Editoren der beiden Felder; nichts
wird irgendwo abgeleitet oder vorbelegt, und geschrieben wird immer über
`Person#update!` bzw. `Group#update!`, damit die PaperTrail-Version so entsteht,
wie das Modell sie baut.

### Gate

Eine **class-side**-Aktion auf `Group`
([`group_ability.rb`](../app/abilities/wsjrdp_2027/group_ability.rb)):

```ruby
class_side(:configure_finance).if_admin_or_finance_manage
```

`if_admin_or_finance_manage` ist `if_admin || if_finance_manage` — Admin
(`:admin`) oder die Manage-Stufe, und die gilt erst, wenn sie für die Sitzung
gewählt wurde ([`doc/roles.md`](roles.md) → „The finance cap"). Beide
Controller fragen `authorize!(:configure_finance, Group)`; dieselbe Bedingung
trägt jeder der beiden Tabs, der Nav-Eintrag und damit auch die Karte auf
`/fin` (§1). Der Name ist `:configure_finance` und nicht `:admin_finance`, weil
`:admin_finance` auf den Finanz-Modellen allein der Manage-Stufe gehört, hier
aber auch die Admins zugreifen.

### Welche Gruppen, welche Personen

- `Group.finance_configurable` (in
  [`wsjrdp_2027/group.rb`](../app/models/wsjrdp_2027/group.rb)): jede
  `Group::Unit` und `Group::Ist`, deren Name kein „Warteliste" enthält.
- `Person.finance_group_candidates` (in
  [`wsjrdp_2027/person.rb`](../app/models/wsjrdp_2027/person.rb)): Personen mit
  einer **aktiven** Rolle `Group::Root::Leader`, `Group::Unit::Manager` oder
  `Group::Ist::Leader` — nur für sie wirkt `finance_group_ids`. Bestehende
  Einträge anderer Personen stehen trotzdem in der Liste und lassen sich dort
  entfernen.

Die Zugriffs-Liste markiert eine Zeile, deren Rechte die Person **auch ohne den
Eintrag** hält (`Fin::FinanceGroupsHelper#finance_by_role` fragt eine
Ability für eine Kopie der Person mit geleertem `finance_group_ids`).

### tom-select und die Chips-Combobox

Die beiden **Filter-Selects** des Gruppen-Finanzzugriffs benutzen `tom-select`
aus dem **Core** (`app/javascript/javascripts/modules/tom_select.js`). Es wird
allein über die CSS-Klasse aktiviert: jedes Element mit `tom-select` bekommt auf
`turbo:load` und `turbo:render` eine TomSelect-Instanz, ein einfaches `<select>`
also ein durchsuchbares Dropdown. Der Text „keine Einträge" kommt aus
`data-chosen-no-results`. Geschrieben wird das wie im Core als
`class: "form-select tom-select"`; das Element braucht eine `id`.

**Gruppen-Kostenstellen** und das Formular zum Hinzufügen des
Gruppen-Finanzzugriffs benutzen die geteilte **Chips-Combobox** des Wagons
(`shared/wsjrdp/_chips_combobox_styles` und `shared/wsjrdp/_chips_combobox_js`,
dasselbe Widget wie im Filter-Builder —
[`wsjrdp/generic_filter_builder.md`](wsjrdp/generic_filter_builder.md) §2.5).
Auch sie wird allein über ein Attribut aktiviert: jedes
`select[multiple][data-chips-combobox]` bekommt beim Laden und nach jedem
Turbo-Besuch ein Feld aus Chips und Suchfeld. Das `<select>` bleibt versteckt
das Formularfeld und bekommt jede Änderung als `option.selected` und als
`change`-Ereignis. Optionsliste und Tastaturhinweise stehen nur, solange das
Feld den Fokus hat.

### Gruppen-Kostenstellen: eine Seite, ein Formular

Die Seite ist **ein** Formular über alle konfigurierbaren Gruppen. Pro Zeile
steht ein `<select multiple name="cost_center_numbers[<Gruppen-Id>][]">` mit
allen Kostenstellen als Optionen; die gespeicherten Nummern sind ausgewählt und
erscheinen als Chips. Vor jedem Select liegt ein verstecktes Feld mit leerem
Wert — ein geleerter Select schickt sonst nichts, und die leere Liste käme nie
an. Nummern, die noch eine andere Gruppe führt, stehen als kleiner Hinweis
unter dem Select.

Gespeichert wird alles mit **einem** Button am Ende des Formulars. Ober- und
unterhalb der Tabelle steht je ein Hinweis „Änderungen sind noch nicht
gespeichert."; beide tragen `hidden`, bis ein `change`-Ereignis aus dem
Formular kommt — ein kurzer `:javascript`-Block nimmt dann bei beiden das
Attribut weg.

`#update` bekommt `cost_center_numbers` als Hash Gruppen-Id → Nummern-Array,
verwirft die leeren Einträge und prüft erst alles: eine Gruppe außerhalb von
`Group.finance_configurable` oder eine unbekannte Nummer heißt Fehler und
**nichts** wird gespeichert. Danach werden nur die Gruppen geschrieben, deren
Liste sich wirklich unterscheidet (Vergleich der sortierten Listen), jede über
`Group#update!` — eine unveränderte Zeile erzeugt also auch keine Version. Die
Meldung nennt die Zahl der gespeicherten Gruppen oder sagt „Keine Änderungen.".

### Gruppen-Finanzzugriff: ein zweistufiger Editor

Die Seite bearbeitet **erst lokal**. Jede Zeile trägt ihren gespeicherten Stand
in Data-Attributen (`data-person-id`, `data-group-id`, `data-level`,
`data-person-name`, `data-group-name`); ein `:javascript`-Block der View führt
die offene Runde in einer Map `"<Personen-Id>:<Gruppen-Id>"` → Stufe und
zeichnet sie in die Tabelle ein. Geschrieben wird nichts, bis „Anwenden"
gedrückt ist.

Die Stufe ist kein Menü, sondern eine Bootstrap-`btn-group` aus zwei
`<button type="button" data-level>`. Der gespeicherte trägt `active` und
`aria-pressed="true"`; ein Klick auf den anderen merkt eine Stufen-Änderung vor
und zeigt sie als „Anzeigen → Anzeigen + Bearbeiten" daneben, ein Klick zurück
auf den gespeicherten nimmt sie wieder weg. „Entfernen" streicht die Zeile
durch, markiert sie mit „wird entfernt" und bietet „Rückgängig". Eine
gespeicherte Token-Liste, für die die Seite keine Stufe kennt (etwa `update`
allein), steht weiterhin als Rohtext daneben, und keiner der Buttons ist aktiv.

Das Formular zum Hinzufügen nimmt **mehrere** Personen und **mehrere** Gruppen
auf einmal — zwei `select[multiple][data-chips-combobox]` nebeneinander — plus
eine der beiden Stufen als Radio-Paar (`btn-check`, die erste vorausgewählt).
„Hinzufügen" ist ein `type="button"`: es merkt jede Kombination aus Person und
Gruppe vor. Eine Zeile, die die gewählte Stufe schon trägt, bleibt wie sie ist;
eine mit anderer Stufe wird zur Stufen-Änderung; ein neuer Eintrag kommt als
Zeile aus `<template id="finance-group-row-template">` an die Tabelle. Auswahl
und Stufe bleiben stehen, damit die nächste Fuhre von hier aus geht.

Über der Tabelle steht `#finance-groups-pending`: solange nichts offen ist
`hidden`, sonst „%{added} neu, %{changed} geändert, %{removed} entfernt – noch
nicht angewendet" mit „Anwenden" und „Abbrechen". „Abbrechen" verwirft die
ganze Runde und stellt die Zeilen wieder her. „Anwenden" schickt ein
verstecktes Formular (PATCH auf `/fin/admin/finance_groups`) mit dem einen Feld
`changes` — einem JSON-Array aus `{person_id, group_id, level}`, `level` ist
`"show"`, `"show,update"` oder `null` fürs Entfernen.

Solange etwas offen ist, sind die Filter **gesperrt** — ein Filter lädt die
Seite neu und würde die Runde wegwerfen. Gesperrt heißt dasselbe wie bei den
Schnellauswahl-Buttons des Filter-Builders: `aria-disabled="true"`, kein
`href`, `pointer-events: none`, ausgegraut, mit dem Titel „Filter sind gesperrt,
solange Änderungen nicht angewendet sind."; derselbe Satz steht als Hinweis
neben den Filtern.

`#apply` liest `params[:changes]`. Kaputtes JSON oder etwas, das kein Array
ist, heißt Fehler. Danach wird **jede** Änderung geprüft, bevor irgendetwas
geschrieben wird: die Stufe muss eine der beiden sein, für eine Stufe muss die
Gruppe in `Group.finance_configurable` und die Person in
`Person.finance_group_candidates` stehen; fürs Entfernen muss die Person nur
existieren (die Gruppe darf beliebig sein, damit ein veralteter Eintrag
wegkann). Eine einzige unzulässige Änderung lässt die **ganze** Liste
ungespeichert. Dann wird je Person gemischt — Stufen ins gespeicherte Hash,
Entfernungen heraus — und nur die Person geschrieben, deren Hash sich wirklich
unterscheidet, über `Person#update!`: eine Version je Person. Gezählt wird
gegen den **gespeicherten** Stand, eine Änderung auf die schon gesetzte Stufe
zählt also nichts. Die Meldung nennt die drei Zahlen oder sagt „Keine
Änderungen.".

Vor den beiden bestehenden Filtern steht der **Bereichs-Filter**: eine
`btn-group` aus Links mit dem GET-Parameter `family`, die die übrigen
Filter-Parameter mitnehmen. Die Einträge leiten sich aus
`Group.finance_configurable` ab — „Alle", je eine Unit-Familie (der
Anfangsbuchstabe eines Namens nach `/\A([A-Z])\d+\z/`, Parameter `unit:A`),
„Sonstige Units" (`unit:other`, jede andere Unit) und „IST-Gruppen" (`ist`).
Der aktive Eintrag trägt `active`. Der Filter grenzt die Zeilen ein und wirkt
mit Gruppen- und Personen-Filter zusammen.

### Sheets und Routen

Der Bereich hat keine eigene Seite: `/fin/admin` rendert den ersten Tab.
Bereichs-Sheet ist `Sheet::Fin::Admin`, die beiden Controller-Sheets sind —
singularisiert (§6) — `Sheet::Fin::FinanceGroup` und
`Sheet::Fin::GroupCostCenter`, beide mit `parent_sheet = Sheet::Fin::Admin` und
`always_render_parent`.

**Fallstrick:** In den Sheets liegt alles unter `module Sheet`, und dort löst
das nackte `Group` auf `Sheet::Group` auf. Die Tab-Bedingungen schreiben
deshalb `::Group`.

### Beteiligte Dateien (Verwaltung)

| Zweck | Datei |
| --- | --- |
| Bereichs-Sheet (Tabs + linke Nav) | `app/helpers/sheet/fin/admin.rb` |
| Kind-Sheets | `app/helpers/sheet/fin/finance_group.rb`, `app/helpers/sheet/fin/group_cost_center.rb` |
| Controller | `app/controllers/fin/finance_groups_controller.rb`, `app/controllers/fin/group_cost_centers_controller.rb` |
| Helper | `app/helpers/fin/finance_groups_helper.rb` |
| Views | `app/views/fin/finance_groups/index.html.haml`, `app/views/fin/group_cost_centers/index.html.haml` |
| Chips-Combobox | `app/views/shared/wsjrdp/_chips_combobox_styles.html.haml`, `app/views/shared/wsjrdp/_chips_combobox_js.html.haml` |
| Routen | `config/routes.rb` (`get :admin …`, `scope "admin" do … end`) |
| Linke Unter-Nav | `app/views/fin/_left_nav.html.haml` |
| Karte auf `/fin` | `app/helpers/fin/overview_helper.rb` (`AREAS`, `#fin_areas`) |
| i18n | `config/locales/wsjrdp_2027.de.yml` (`fin.nav.admin`, `fin.tabs.finance_groups`, `fin.tabs.group_cost_centers`, `fin.finance_groups.*`, `fin.group_cost_centers.*`, `fin.areas.admin.purpose`) |
| Rechte | `app/abilities/wsjrdp_2027/group_ability.rb` |

Die Routen-Helfer: `fin_admin_path`, `fin_admin_finance_groups_path` (GET) und
`fin_admin_apply_finance_groups_path` (PATCH, derselbe Pfad) sowie
`fin_admin_group_cost_centers_path` — letzterer für GET und als PATCH-Ziel
`fin_admin_save_group_cost_centers_path`. Beide Seiten schicken **eine**
Änderungsliste über alle Zeilen, deshalb ist der Schreib-Pfad je Seite eine
**Collection-Route**; Member-Routen gibt es in diesem Bereich nicht.
