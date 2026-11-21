# Reading typed instants (`Wsjrdp::InstantInput`)

One place turns a typed point in time into a `Time` in UTC:
[`app/domain/wsjrdp/instant_input.rb`](../../app/domain/wsjrdp/instant_input.rb),
the sibling of [`Wsjrdp::DateInput`](date_input.md). Use it for every
instant read from a form, a variable or a file, instead of `Time.parse`.

```ruby
Wsjrdp::InstantInput.parse("2026-12-01T08:00")                        # => 2026-12-01 08:00 UTC
Wsjrdp::InstantInput.parse("2026-12-01 08:00:30.5+01:00")             # => 2026-12-01 07:00:30.5 UTC
Wsjrdp::InstantInput.parse("2026-12-01T08:00", zone: "Europe/Berlin") # => 2026-12-01 07:00 UTC
Wsjrdp::InstantInput.parse("2027-05-19")                              # => 2027-05-19 00:00 UTC
Wsjrdp::InstantInput.parse("")                                        # => nil
Wsjrdp::InstantInput.parse("tomorrow")                                # raises Wsjrdp::InstantInput::Invalid
```

- **ISO 8601 only:** a date, `T` or a space, `HH:MM`, optional seconds and
  fraction, optional `Z` or `±HH:MM`.
- A text without a zone is UTC, unless the caller names a zone (`zone:`,
  an IANA name such as `"Europe/Berlin"` or an `ActiveSupport::TimeZone`;
  any other zone is an `ArgumentError`). A local time that does not exist
  or exists twice in that zone is refused: write it with its offset. A UTC
  zone is known by its name, so wrong zone data on a system cannot shift
  it.
- **A bare date is 00:00 UTC of that day, in every zone**:
  `expires_at: 2027-05-19` ends at the start of the 19th.
- A `Time` keeps its instant (as UTC).
- Everything else, a `Date` included (write the date as text), is refused
  with `Invalid` (an `ArgumentError`), whose message never repeats the
  input: it may be a secret in the wrong place.

The spec `spec/domain/wsjrdp/instant_input_spec.rb` is standalone:
`bundle exec rspec spec/domain/wsjrdp/instant_input_spec.rb`.
