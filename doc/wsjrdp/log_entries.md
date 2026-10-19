# Log entries

Besides the changes PaperTrail records, the wagon writes entries of its own
into `versions`: a tag added or removed, a note such as "informed about the
upcoming direct debit". They show in the log of their `main` (a person's or a
group's log page), whatever their `item` is.

## The columns

- `event`: the event, always starting with `wsjrdp_` (`Wsjrdp::LogEvents`).
- `wsjrdp_data` (jsonb, not null, default `{}`): the data of the event, in the
  keys the event defines below.
- `additional_info` (jsonb, not null, default `{}`): metadata of any entry,
  the same for all events, e.g. the script that wrote it.
- `item`, `main`, `whodunnit`, `whodunnit_type`, `created_at` as for any
  version.

`wsjrdp_data` has a GIN index (`jsonb_path_ops`). It serves containment
queries, not `->>` or `?`:

```sql
SELECT * FROM versions WHERE wsjrdp_data @> '{"category": "pre_notification"}';
```

```ruby
PaperTrail::Version.where("wsjrdp_data @> ?", {category: "pre_notification"}.to_json)
```

## Writing

```ruby
Wsjrdp::LogEntry.record!(item, "wsjrdp_add_tag", {"tag_name" => name})
Wsjrdp::LogEntry.note!(person, category: "pre_notification", message: "…")
```

`main` defaults to the item, `whodunnit` to `PaperTrail.request.whodunnit`.
Nothing is checked. A script writes the same row with an `INSERT` into
`versions` (`wsjrdp_data` as JSON), in the transaction of the change it logs.

## The events

| Event | `wsjrdp_data` | Shown as |
|---|---|---|
| `wsjrdp_add_tag` | `tag_name` (text) | Tag *name* hinzugefügt |
| `wsjrdp_remove_tag` | `tag_name` (text) | Tag *name* entfernt |
| `wsjrdp_note` | `category` (text), `message` (text), any further keys | *Category label*: message |

The tag entries also keep their old form in `object_changes`
(`{"tag" => [old, new]}`); an entry written before `wsjrdp_data` existed has
only that, and the log reads it from there.

Categories of `wsjrdp_note` with a label (`version.wsjrdp_note_categories`):

| Category | Label |
|---|---|
| `pre_notification` | Vorabankündigung Lastschrift |

Any other category is written and shown as it is. The message is shown on one
line (white space squeezed), escaped -- plain text, no HTML.

## Showing

`Wsjrdp2027::PaperTrail::VersionDecorator#changes` shows an entry by its
definition in `Wsjrdp::LogEvents::EVENTS`:

- the data is `wsjrdp_data`; where that is `{}`, what the event's `legacy`
  makes of the YAML in `object_changes`,
- the sentence `version.<event>` with the event's `params`, each value
  escaped and formatted by its type (`:text`, `:date`, `:cents`, `:person`,
  `:group`, `:list`, `:note_category`); a missing or empty value is "–",
- a line "Label: value" per key of the event's `details` that the data has,
- keys the event does not define are not shown.

An event the register does not know, or whose sentence cannot be made, shows
as "Eintrag *event*" with every key and value of its data. The log page never
fails on an entry.

A new event needs a definition in `EVENTS` and its sentence in the locale; a
new note category needs nothing (a label in `version.wsjrdp_note_categories`
if it should have one).
