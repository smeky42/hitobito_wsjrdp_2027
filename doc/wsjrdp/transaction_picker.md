# The transaction picker

`shared/wsjrdp/_transaction_picker` lets a form pick bank and Moss
transactions of the contingent's own accounts. It searches on the server,
so it is not limited to what a page loaded, and it hands the chosen rows to
its host form as hidden fields. The Umbuchung form uses it for "Buchung
hinzufügen"; the same partial fits wherever a statement row has to be chosen
(the original of a return, a bank transaction for a Beitragsbuchung, …).

- Widget: `app/views/shared/wsjrdp/_transaction_picker.html.haml`, styles and
  script in `_transaction_picker_assets.html.haml` (once per response)
- Results: `Fin::TransactionPickerController` (`GET /fin/transaction_picker`,
  `app/views/fin/transaction_picker/index.html.haml`)
- Search: `Fin::TransactionSearch` (`app/domain/fin/transaction_search.rb`)
- Rows: `Fin::InternalTransferLeg` (key, account, amount, date, text, party)
- Specs: `spec/domain/fin/transaction_search_spec.rb`,
  `spec/controllers/fin/transaction_picker_controller_spec.rb`

## Using it

```haml
= render "shared/wsjrdp/transaction_picker", id: "ret-original",
  name: "original_keys[]", label: "Original wählen", sign: "out",
  anchor: payment_return.value_date, target: -payment_return.amount, multi: false
```

| local | meaning |
|---|---|
| `id` | unique on the page; names the results frame `tp-results-<id>` |
| `name` | the field name of a picked row; the value is the row's key, `camt:<id>` or `moss:<id>` |
| `label` | the button's text, "Buchung auswählen" by default |
| `sign` | `"out"` (money leaving), `"in"` (arriving) or `nil` (both) |
| `sources` | `%w[camt moss]` by default |
| `accounts` | the accounts offered as chips; every account by default |
| `anchor` | the date the window centres on (±3 / ±10 / ±30 days, ±10 at first); without one the last 30 / 90 days |
| `anchor_label` | what the anchor is, shown under the window with the dates it covers ("Bezugsdatum" by default) |
| `target` | a signed amount; offered as the chip "gleicht aus", on at first |
| `multi` | several rows (`true`, the default) or one (`false`: a new pick replaces the old) |
| `exclude` | keys never to offer, e.g. the rows already chosen |
| `data` | further data attributes on the picker, for the host's script |

The host reads the picked keys from `params[name]` and resolves them with
`Fin::InternalTransferLeg.find_all(keys)`.

## How it works

- The button (a `<details>`) opens the panel and hides while it is open: on
  top "Auswahl schließen", then the filters, the results frame and the foot
  with the summary, "Abbrechen" (puts the tray back as it was when the panel
  opened) and "Übernehmen" (keeps it). The **tray** below the button -- a chip with
  ✕ and a hidden field per picked row -- stays visible when the panel is
  closed, so the choice is always in sight.
- Every filter change sets the frame's `src`; typing in the amount or the text
  waits 300 ms first, Enter searches at once (and never submits the host
  form). The filter fields carry no `name`, so the host form never sees them.
- The results show at most `Fin::TransactionSearch::LIMIT` (100) rows, the
  nearest to the anchor first, and say how many match in all. A row that
  already is a leg of an Umbuchung shows only with "auch schon verknüpfte
  zeigen", disabled and linked to its transfer.
- A result's checkbox has no `name`. Ticking it copies the row into the tray;
  every change of the tray bubbles a `change` event from the picker, and a
  hidden field carries `data-tp-chosen` and `data-amount`, so a host can sum
  the choice (the Umbuchung form's "Summe nach dem Speichern" does).
- A host whose open rest changes calls
  `window.wsjrdpTransactionPicker.setTarget(picker, amount)` (`0`/`null`:
  none); the chip "gleicht aus" follows, and an open panel searches again. The
  Umbuchung form does it on every change, per side with the rest the other
  rows leave open (not counting the side's own picks, so picking keeps the
  list as it is).
- The script attaches its listeners once per page and a newer copy replaces
  the handlers, so a page reached by a Turbo visit runs the current code.
- The amount filter reads `677` as 677,00 to 677,99, `677,48` exactly and
  `600-700` as a range -- always on the magnitude; the sign is `sign`'s job.
  Text words must all appear in the row's text or counterparty.
- The layout follows the room the picker has (a container query), not the
  window: in a narrow column, as on a phone, a row is a card: the amount, then date and account, then the text.

The endpoint only reads; it asks `:show` on the sources it searches, so every
finance tier may use a picker.
