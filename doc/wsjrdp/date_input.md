# Reading typed dates (`Wsjrdp::DateInput`)

One place turns a date that people or scripts type into a `Date`:
[`app/domain/wsjrdp/date_input.rb`](../../app/domain/wsjrdp/date_input.rb).
Use it wherever the wagon reads a date from a form, a parameter or a file,
instead of `Date.parse` (which completes fragments) or a hand-written
`strptime`.

```ruby
Wsjrdp::DateInput.parse("2026-10-31")      # => Date 2026-10-31
Wsjrdp::DateInput.parse("31.10.2026")      # => Date 2026-10-31
Wsjrdp::DateInput.parse("1.2.26")          # => Date 2026-02-01
Wsjrdp::DateInput.parse("")                # => nil (blank is no date)
Wsjrdp::DateInput.parse("3")               # raises Wsjrdp::DateInput::Invalid
Wsjrdp::DateInput.parse_or_nil("31.02.26") # => nil
Wsjrdp::DateInput.valid?("1.2.26")         # => true
```

## What is a date

| Form | Examples | Notes |
| --- | --- | --- |
| ISO 8601 calendar date `YYYY-MM-DD` | `2026-10-31`, `2026-1-5` | leading zeros of month and day optional |
| German `D.M.YYYY` | `31.10.2026`, `1.2.2026` | day and month one or two digits |
| German `D.M.YY` | `1.2.26`, `31.12.68`, `1.1.69` | POSIX pivot as `Date.strptime("%y")`: 69..99 → 1969..1999, 00..68 → 2000..2068 |
| a `Date`, `Time`, `TimeWithZone` | | its day |

Surrounding whitespace is ignored. Everything else is refused with
`Wsjrdp::DateInput::Invalid` (an `ArgumentError`): fragments `Date.parse`
would complete (`3`, `1.1`, `Mai 5`), other separators (`31/10/2026`), a time
part, and days that do not exist (`31.02.2026`).

## In a model

The deregistration writers of the person (`Wsjrdp2027::Person`) show the
pattern for a form field:

- the writer parses with `Wsjrdp::DateInput.parse` and rescues only
  `Wsjrdp::DateInput::Invalid` (`read_deregistration_input`, which the
  amount writers share);
- on a refused text it leaves the stored value and notes the field with its
  error and the typed text (`deregistration_input_invalid`);
- a `validate` adds the noted errors, so they survive `valid?` (an error
  added inside a writer is cleared by validation);
- `timeliness_cache_attribute` answers the typed text, so the core's
  `StandardFormBuilder#date_field` shows it again next to the error.

## Tests

`spec/domain/wsjrdp/date_input_spec.rb` is standalone (no Rails boot, no
database):

```bash
bundle exec rspec spec/domain/wsjrdp/date_input_spec.rb
```
