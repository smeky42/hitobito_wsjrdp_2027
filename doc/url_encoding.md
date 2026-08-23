# URL query encoding — policy & reference

> **Note:** this document was written largely by Claude (AI), reviewed by a
> human. The encoder tables were produced by measuring the actual functions in
> this project's Ruby and Node versions, not from memory — but if a statement
> here ever contradicts what you observe, trust the code and fix the page.

How we percent-encode (and deliberately *don't* over-encode) characters in URL
query strings, why, and the **mandatory** helper pattern that makes relaxing the
encoding safe. The last section (Encapsulation) has real security implications —
follow it without exception.

## 1. Policy (must follow)

- **The verified set — must be literal.** Characters that RFC 3986 permits
  unencoded, that we do not use as structural separators, **and that we have
  verified end-to-end** — today exactly `,` and `~` — **must be left literal**
  in the URLs this wagon builds, not percent-encoded. Result: short, readable
  URLs like `?sort=bez,nr~` instead of `?sort=bez%2Cnr%7E`. You discharge this
  obligation by building the URL through the mandatory helpers (§6) — **never**
  by writing your own decode step.
- **Candidates — may be added, only via §6.1.** The other RFC-legal sub-delims
  (`! $ ' ( ) * ;`) are permissible in principle but are **not** relaxed today
  and must stay encoded until they go through the §6.1 process. `;` in
  particular has a history as a query separator outside Rack (proxies, WAFs,
  legacy middleware), so it stays encoded until the whole chain is verified —
  Rack alone is not enough.
- **Never relax these.** `&`, `=`, `+`/`%2B`, `#`, `%` (always `%25`), and
  anything non-ASCII must never be added to the relax set: they carry
  x-www-form-urlencoded or URI structure. Brackets `[` `]` likewise — they are
  gen-delims and encode Rack's param nesting (`show[active_zero]=1`).
  - *Nuance for space:* our encoders emit a space as a literal `+` (not `%20`) —
    that is form-urlencoding, not a relax, and it round-trips correctly. What
    must never be relaxed is `%2B`, i.e. a plus **in the data**.
- **Safe default — when unsure, do not relax.** An over-encoded URL is always
  functionally correct: Rack decodes `%2C` and `,` to the same value, so
  relaxing is purely a readability win. If your case does not fit
  `RelaxedUrlQuery.to_query` / `wsjrdpRelaxedQuery`, emit the fully encoded form
  and raise it in review — do not improvise.
- Note: some browsers percent-decode parts of the URL for address-bar *display*
  (though Firefox and Chromium both keep `%2C` encoded), so the visible bar is
  not the point. The literal form is what lands in copied and shared links,
  generated mails, server logs, and spec expectations.

**Scope.** This policy governs URL-building code **in this wagon** (Ruby helpers
and controllers, and the inline JS partials). The hitobito core is read-only for
us — never patch core merely to relax its URLs. URLs from any other producer
(core, the `wsjrdp_scripts` Python tooling, mail templates, external links) are
out of scope and MAY over-encode freely; the server accepts both spellings.

## 2. Why leaving these literal is safe here

- **RFC 3986 query grammar** (§3.4): `query = *( pchar / "/" / "?" )` with
  `pchar = unreserved / pct-encoded / sub-delims / ":" / "@"`. So every sub-delim
  (`! $ & ' ( ) * + , ; =`) and every unreserved char (incl. `~`) is valid
  *literally* in a query. Percent-encoding them is allowed but **not required**.
- **Our parser is Rack** (Rails). `Rack::Utils.parse_nested_query` splits a query
  on `&` only; it never splits a value on `,` / `;` / etc. So a literal `,`
  round-trips to exactly the same string as `%2C`.
  - Caveat: `;` is safe under *current Rack* only — Rack 2.1 made `&` the sole
    default separator and Rack 3 removed `;` handling entirely. That covers our
    parser, not the rest of the chain (see §1: `;` stays encoded).

## 3. RFC 3986 character classes (quick reference)

```
unreserved  = A-Z a-z 0-9 - . _ ~                 (never needs encoding)
reserved    = gen-delims / sub-delims
  gen-delims = :  /  ?  #  [  ]  @
  sub-delims = !  $  &  '  (  )  *  +  ,  ;  =
pct-encoded = "%" HEXDIG HEXDIG                    (a literal "%" MUST be "%25")
```

Specs & docs:

- RFC 3986 — URI generic syntax (§2.2 reserved, §2.3 unreserved, §3.4 query):
  <https://www.rfc-editor.org/rfc/rfc3986#section-2.2>
- WHATWG URL Standard — `URL`, `URLSearchParams`, the percent-encode sets, and
  `application/x-www-form-urlencoded`: <https://url.spec.whatwg.org/>
- MDN `encodeURIComponent`:
  <https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/encodeURIComponent>
- MDN `encodeURI`:
  <https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/encodeURI>
- MDN `URLSearchParams`:
  <https://developer.mozilla.org/en-US/docs/Web/API/URLSearchParams>
- Ruby `CGI.escape` / `CGI.escapeURIComponent`:
  <https://docs.ruby-lang.org/en/master/CGI.html>
- Ruby `URI.encode_www_form_component`:
  <https://docs.ruby-lang.org/en/master/URI.html#method-c-encode_www_form_component>
- Ruby `ERB::Util.url_encode`:
  <https://docs.ruby-lang.org/en/master/ERB/Util.html#method-c-url_encode>
- Rails `Object#to_query` / `Hash#to_query`:
  <https://api.rubyonrails.org/classes/Object.html#method-i-to_query>
- `Rack::Utils.escape`:
  <https://www.rubydoc.info/gems/rack/Rack/Utils#escape-class_method>

## 4. What each encoder actually does

The point of interest: which of the "leave-literal" chars a function still
percent-encodes (over-encoding, relative to RFC 3986), and whether it even
encodes an **unreserved** char (`~`). Space handling differs too (`+` vs `%20`).

The two wide columns cover every gen-delim, every sub-delim and `~`; the narrow
`encodes …` columns repeat the characters we care about most, for quick lookup
(**yes** = percent-encoded, no = left literal). Alphanumerics and `- . _` are
kept by every encoder listed and are therefore omitted.

### JavaScript (measured on Node 26; matches WHATWG/MDN)

| function | keeps literal | encodes | `~` | `,` | `!` | `(` | `)` | `$` | `'` | `*` | space |
|---|---|---|---|---|---|---|---|---|---|---|---|
| [`encodeURIComponent`][enc-uri-component] | `! ' ( ) * ~` | `: / ? # [ ] @ $ & + , ; =` | no | **yes** | no | no | no | **yes** | no | no | `%20` |
| [`encodeURI`][enc-uri] | `: / ? # @ ! $ & ' ( ) * + , ; = ~` | `[ ]` | no | no | no | no | no | no | no | no | `%20` |
| [`URLSearchParams`][urlsearchparams] / mutating `URL.searchParams` | `*` | `: / ? # [ ] @ ! $ & ' ( ) + , ; = ~` | **yes** | **yes** | **yes** | **yes** | **yes** | **yes** | **yes** | no | `+` |

- [`encodeURIComponent`][enc-uri-component] uses the old RFC 2396 "mark" set: it keeps `! ~ * ' ( )`
  but still encodes `, ; $` (and `& + = : @ / ? #`). Fine for splicing a single
  value into an already-relaxed URL template.
- [`encodeURI`][enc-uri] is for whole URIs, not for values: it preserves every reserved
  character (so a `&` or `=` inside a value would stay structural) and escapes
  only `[ ]` plus the non-ASCII/space range. Never use it on a single param
  value.
- [`URLSearchParams.toString()`][urlsearchparams] is `application/x-www-form-urlencoded`: it encodes
  `~` (an **unreserved** char) and every sub-delim except `*`; space → `+`. It is
  what the JS helper builds on. **Mutating `URL.searchParams` re-serialises the
  *whole* query this way** — which is why a previously literal `sort=bez,nr~`
  turns into `bez%2Cnr%7E` after you touch one unrelated param.

### Ruby (measured on Ruby 3.2.9 in this project)

| function | keeps literal | encodes | `~` | `,` | `!` | `(` | `)` | `$` | `'` | `*` | space |
|---|---|---|---|---|---|---|---|---|---|---|---|
| [`CGI.escape`][cgi] | `~` | `: / ? # [ ] @ ! $ & ' ( ) * + , ; =` | no | **yes** | **yes** | **yes** | **yes** | **yes** | **yes** | **yes** | `+` |
| [`Object#to_query`][to-query] / [`Hash#to_query`][to-query] (uses [`CGI.escape`][cgi]) | `~` | `: / ? # [ ] @ ! $ & ' ( ) * + , ; =` | no | **yes** | **yes** | **yes** | **yes** | **yes** | **yes** | **yes** | `+` |
| [`URI.encode_www_form_component`][uri-www-form-component] | `*` | `: / ? # [ ] @ ! $ & ' ( ) + , ; = ~` | **yes** | **yes** | **yes** | **yes** | **yes** | **yes** | **yes** | no | `+` |
| [`Rack::Utils.escape`][rack-escape] (same as [`URI.encode_www_form_component`][uri-www-form-component]) | `*` | `: / ? # [ ] @ ! $ & ' ( ) + , ; = ~` | **yes** | **yes** | **yes** | **yes** | **yes** | **yes** | **yes** | no | `+` |
| [`ERB::Util.url_encode`][erb-url-encode] | `~` | `: / ? # [ ] @ ! $ & ' ( ) * + , ; =` | no | **yes** | **yes** | **yes** | **yes** | **yes** | **yes** | **yes** | `%20` |
| [`CGI.escapeURIComponent`][cgi] (Ruby ≥ 3.2) | `~` | `: / ? # [ ] @ ! $ & ' ( ) * + , ; =` | no | **yes** | **yes** | **yes** | **yes** | **yes** | **yes** | **yes** | `%20` |

- **None** of the Ruby encoders leave the sub-delims `! $ ' ( ) , ;` literal —
  they all over-encode them relative to RFC 3986.
- The unreserved `~` is **encoded** (`%7E`) by [`URI.encode_www_form_component`][uri-www-form-component]
  and [`Rack::Utils.escape`][rack-escape], but kept literal by [`CGI.escape`][cgi] / [`to_query`][to-query] /
  [`ERB::Util.url_encode`][erb-url-encode] / [`CGI.escapeURIComponent`][cgi].
- Used in the code: [`Hash#to_query`][to-query] is what `RelaxedUrlQuery` (§6) builds on —
  the `%2C`/`%7E` it produces are relaxed straight back, so URLs built through
  that helper carry the literal form. `URI.encode_www_form` is used directly in
  `Person::FeeController` (note it encodes `~`; those are plain button links,
  not list params, so only functional correctness matters there).
- A codebase may also grow its own **encode-forward** helper that deliberately
  under-encodes a single value (leaving e.g. `=` or non-ASCII literal). That can
  be legitimate — Rack and [`URLSearchParams`][urlsearchparams] split each `name=value` pair on the
  **first** `=` only, and both pass UTF-8 through — but it is an *encoder*, never
  a relax step, so §6 does not apply to it. Document any such helper here.
- `ERB::Util.html_escape` is **HTML** escaping, not URL encoding — different
  concern, don't confuse them.

## 5. Relaxing (reversing) the over-encoding

To get the RFC-clean literal form after encoding, decode the `%XX` escapes for
the chars you want literal. The exact escapes depend on the encoder:

| char | escape | produced by |
|---|---|---|
| `,` | `%2C` | all encoders above **except [`encodeURI`][enc-uri]**, which keeps `,` literal |
| `~` | `%7E` | [`URLSearchParams`][urlsearchparams], [`URI.encode_www_form_component`][uri-www-form-component], [`Rack::Utils.escape`][rack-escape] (the others already keep `~`) |
| `!` `$` `'` `(` `)` `*` `;` | `%21 %24 %27 %28 %29 %2A %3B` | relax only those you actually use |

Today we produce and relax exactly `%2C` → `,` and `%7E` → `~`.

## 6. Encapsulation rule — SECURITY, no exceptions

Relaxing means string-replacing `%XX` back to a literal char. **This is safe only
on the output of a proper percent-encoder.** In such output `%` is guaranteed to
be encoded as `%25`, so `%` never appears raw: every `%` starts a `%XX` triplet,
and `%2C` / `%7E` can only ever be the escape of a comma / tilde. (A literal
`%2C` in the *data* is encoded to `%25`​`2C`, which contains no `%2C` substring —
so it is not mis-decoded.)

*Proper* is a checkable property, not a vibe: the encoder must percent-encode
**every** raw `%` in its input as `%25`, unconditionally — `enc("%2C")` must
yield `%252C`. Escape-preserving (idempotent) encoders — anything with
"skip already-encoded sequences" behaviour, e.g. `Addressable::URI`
normalization or hand-rolled `%(?![0-9A-Fa-f]{2})`-style helpers — do **not**
have this property and must never feed a relax step: in their output `%2C` can
be data, which the relax then corrupts. Every function in the §4 tables *does*
have the property; anything not listed there must be verified before it may ever
feed a relax. Rule 3's round-trip tests — especially "the text `%2C` as data" —
are what catch a violation.

Run the same replace on a **raw or partly-decoded** string that may contain a
bare `%`, and you can corrupt data or **forge separators**. The danger grows the
moment the relax set is widened: relax `,`/`~` on a raw value and at worst a
literal `%2C`/`%7E` in the data turns into `,`/`~` (harmless — Rack never splits
on those); but relax a separator like `&` (`%26`) or `=` (`%3D`) on raw input and
a value's literal `%26` collapses into a real `&`, splitting off a forged
parameter. That is a genuine parameter-injection risk — which is exactly why the
relax step must never see anything but fresh encoder output.

Therefore, **mandatory**:

1. **Encode and relax in ONE helper.** The relax `.gsub` / `.replace` must only
   ever be fed the *immediate* output of the encoder. Never write a standalone
   "relax this string" function, and never call the `%XX` replace on a value that
   did not come straight out of an encoder in the same expression/helper.
2. **Relax the query component only** — never regex the whole URL string (a path
   or fragment octet must stay as-is). On the client, run the replace on
   `searchParams.toString()` and reassemble `path + "?" + query + hash`; never on
   `url.toString()`.
   - *Destination assembly:* build the path part only from a component that
     cannot itself contain a `?` (`URL.pathname`, `location.pathname`,
     `request.path`) — never concatenate `"?" + query` onto something that might
     already carry one (`request.fullpath`, an `action` attribute, an `href`).
     When you hold a `URL`, use `wsjrdpRelaxedQuery.href()` rather than
     concatenating by hand.
   - *Protocol-relative edge:* a `pathname` may begin with `//` (WHATWG keeps an
     empty first segment: `new URL("https://app//evil.example/x").pathname ===
     "//evil.example/x"`). Returned as-is that is a network-path reference that
     resolves to **another origin** — an open-redirect primitive. `href()`
     collapses leading slashes; any hand-rolled assembly must do the same.
3. **Any new or copied helper of this kind must be extensively tested and
   documented.** Round-trip tests at minimum: `value → encode+relax → parse back
   == value` for tricky inputs including a literal `%`, the text `%2C` as data,
   `&`, `=`, `+`, space, and non-ASCII. No exceptions.
4. **Do not scatter** raw `.gsub("%2C", ",")` calls. If you need this behaviour in
   a new place, route it through a single tested helper rather than copying the
   inline expression.
5. **This is enforced, not just asked.** `spec/models/url_encoding_guard_spec.rb`
   scans `app/` and `lib/` (`.rb`, `.haml`, `.erb`, `.js`) and fails on any
   percent-escape replacement outside the two mandatory helpers. If it flags your
   change, call `RelaxedUrlQuery` / `wsjrdpRelaxedQuery` instead. Extending the
   guard's allowlist is itself a policy change — see §6.1.

### 6.1 Widening the relax set — decision rule & checklist

A character MAY be added to the relax set only if **all** of these hold:

1. **RFC 3986 permits it literally in a query** (§3: unreserved or sub-delim).
   Gen-delims (`: / ? # [ ] @`) never qualify; `[` `]` are additionally
   structural for Rack's param nesting.
2. **No decoder in the chain treats it as a separator** — and "the chain" is not
   just Rack: reverse proxy, CDN/cache, WAF, and log tooling all parse these
   URLs. *Verify* concretely: add literal-in-value **and** "X as data"
   round-trip cases to **both** test matrices and to both fuzz charsets, and
   confirm they pass. For `;` additionally confirm the deployed Rack major
   version (≥ 3 removed `;` handling) *and* the non-Rack hops.
3. **We actually emit the character** in a list-style param — never relax
   speculatively.

One PR must change together: `RELAXATIONS` (+ its comment), the JS replace
chain, both test suites, and this document. When in doubt, don't — see the safe
default in §1.

### The mandatory helpers (use these, never inline the pattern)

Exactly one implementation exists per language. **Always call these; never write
a new inline `gsub`/`replace` of `%XX` sequences.**

- **Ruby** — [`RelaxedUrlQuery`](../app/models/relaxed_url_query.rb)
  (`app/models/relaxed_url_query.rb`): the only public API is
  `RelaxedUrlQuery.to_query(params_hash)` → query string with `,`/`~` literal.
  Encode ([`Hash#to_query`][to-query]) and relax are one method; it **raises `TypeError` on
  anything but a Hash**, so a pre-built string can never reach the relax, and the
  relax pieces are `private_constant` so they cannot be reassembled from outside.
  Typical use in a URL-building helper:

  ```ruby
  "#{request.path}?#{RelaxedUrlQuery.to_query(query_params)}"
  ```

  Tests: `spec/models/relaxed_url_query_spec.rb` — readability, round-trips
  through `Rack::Utils.parse_nested_query` for raw `%`, the literal text
  `%2C`/`%7E` as data, separators (`&`, `=`, `+`, `#`), non-ASCII, nested
  hashes/arrays, hostile injection values, a 500-case seeded fuzz, and the
  API-surface assertions. Deliberately standalone (no Rails boot, no DB — also
  so a test run can never be pointed at a shared dev database):

  ```bash
  # from the core app directory, inside the dev container
  bundle exec rspec ../hitobito_wsjrdp_2027/spec/models/relaxed_url_query_spec.rb
  ```

- **JavaScript** — `window.wsjrdpRelaxedQuery`
  ([`app/views/shared/_relaxed_query_js.html.haml`](../app/views/shared/_relaxed_query_js.html.haml)):
  `serialize(URLSearchParams | FormData)` → relaxed query string, and
  `href(URL)` → `pathname + "?" + relaxed query + hash`. Both **throw a
  `TypeError` on plain strings** — the API only accepts structured input, so the
  replacement can never run on a string with a raw `%`; `href` reassembles from
  components (so path/fragment octets are never touched) and collapses a leading
  `//` so its result can never be a cross-origin network-path reference. Render
  the partial (`= render "shared/relaxed_query_js"`, idempotent per
  request/page) before any script that uses it — typically from an inline
  `:javascript` block that rewrites the URL (`history.replaceState`) or builds a
  navigation target from form fields.

  Tests: `spec/javascripts/relaxed_query.test.mjs` mirrors the Ruby matrix and
  adds the type-contract and protocol-relative checks; it extracts the
  implementation from the partial's marker comments, so partial and test cannot
  drift apart:

  ```bash
  # from the wagon root; no dependencies (built-in node runner).
  # Quote the glob -- a bare directory argument does not work.
  node --test "spec/javascripts/**/*.test.mjs"
  ```

Both suites run in CI: the Ruby one as part of the wagon specs, the JS one in the
`javascript specs` job of `.github/workflows/wagon-tests.yml`. Changing either
helper (especially widening the relax set, §6.1) requires extending BOTH suites
first; run them plus `bundle exec rubocop -a .` before committing.

**Adopting the helpers.** Existing code that builds a query with a plain
[`Hash#to_query`][to-query] (redirect targets, link helpers) is not broken — it just emits
the over-encoded spelling, which the server accepts (§2). Migrate such a site to
`RelaxedUrlQuery.to_query` when you touch it; never "fix" it with an inline
relax (§6). Keep a list of the remaining ones here as they are found.

## 7. Operational notes

- **Two spellings, one page.** The encoded and relaxed forms are different
  *strings* but identical to the server (§2). Old bookmarks and externally
  generated links in the encoded form keep working; we never redirect to
  normalize. Consequence: client-side URL-string consumers (Turbo's page cache,
  history entries, analytics) may see both variants of the same page. Expected
  and harmless.
- **Never compare URLs as strings.** In JS and in specs, parse and compare
  params ([`URLSearchParams`][urlsearchparams], `Rack::Utils.parse_nested_query`) instead of
  matching query strings textually — a comparison written against one spelling
  breaks intermittently against the other.
- **Searching logs.** Access logs contain whichever form the client sent, so
  grep for both (e.g. `sort=bez,nr~` *and* `sort=bez%2Cnr%7E`) when tracing a
  request.
- **Application-level separators.** §2 argues transport safety only: a literal
  `,`/`~` parses to the same param *value* as `%2C`/`%7E`. But a list-style param
  typically uses `,` and `~` as its **own** separators inside that value (a comma
  list, a `~` marker). So the tokens themselves — column keys, sort symbols, row
  ids — must never contain `,` or `~`, or the value is silently mis-parsed. Keep
  such tokens `[a-z0-9_]`, and assert it where the tokens are defined.

[enc-uri-component]: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/encodeURIComponent
[enc-uri]: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/encodeURI
[urlsearchparams]: https://developer.mozilla.org/en-US/docs/Web/API/URLSearchParams
[cgi]: https://docs.ruby-lang.org/en/master/CGI.html
[uri-www-form-component]: https://docs.ruby-lang.org/en/master/URI.html#method-c-encode_www_form_component
[erb-url-encode]: https://docs.ruby-lang.org/en/master/ERB/Util.html#method-c-url_encode
[to-query]: https://api.rubyonrails.org/classes/Object.html#method-i-to_query
[rack-escape]: https://www.rubydoc.info/gems/rack/Rack/Utils#escape-class_method
