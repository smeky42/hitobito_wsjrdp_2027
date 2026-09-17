# Typst documents

PDFs that are letters — something a person or a team reads, on the
contingent's letterhead — are written as [Typst](https://typst.app)
templates and compiled by the `typst` gem. (The registration contract
takes the other route, Prawn in
[`app/domain/wsjrdp_2027/export/pdf/`](../app/domain/wsjrdp_2027/export/pdf/):
it draws a form, not a letter.)

The templates are shared with the `wsjrdp_scripts` repository, which
compiles the same letter layout on the Python side. Keep
`wsjrdp2027.typ` and `WSJ_Brief_blanko.pdf` identical to their copies
there; a change belongs in both.


## Where the files are

| Path | What it is |
| --- | --- |
| `app/domain/wsjrdp_2027/typst/` | the Typst project root: every template, plus what they include |
| `app/domain/wsjrdp_2027/typst/wsjrdp2027.typ` | the shared letter template (`wsjrdp2027_letter`, `fill-in-box`, `person_id_line`, `signature_line(s)`) |
| `app/domain/wsjrdp_2027/typst/WSJ_Brief_blanko.pdf` | the letterhead, set as the page background by `wsjrdp2027_letter` |
| `app/assets/fonts/Montserrat-*.ttf` | the fonts the compile is given |
| `app/domain/wsjrdp_2027/typst_document.rb` | the wrapper that compiles a template |

The templates sit next to the domain code that fills them, the way the
core keeps its own PDF assets (`app/domain/invoice/assets`). Zeitwerk
leaves the directory alone — it holds no `.rb` file and is therefore no
namespace.

The letterhead sits next to the templates because `wsjrdp2027.typ`
pulls it in with a relative `image("WSJ_Brief_blanko.pdf")`. That whole
directory is the Typst project root, so a template can `#import` its
siblings and read nothing outside.


## The wrapper

```ruby
Wsjrdp2027::TypstDocument.compile_pdf("refund_receipt.typ", sys_inputs: {...})
# => the PDF as one binary String
```

- `template` is a **file name** inside the typst directory, never a
  path. An unknown name raises `ArgumentError`.
- `sys_inputs` becomes Typst's `sys.inputs`. Typst inputs are Strings
  and nothing else, so every value is stringified on the way in;
  structured data goes in as JSON (`to_json`) and comes back out in the
  template with `json(bytes(...))` — see how the scripts' cancellation
  letter passes its account statement.
- The return value is the complete PDF. A controller hands it to the
  browser directly:

  ```ruby
  send_data pdf, type: "application/pdf", disposition: "inline", filename: name
  ```

- `require "typst"` sits at the top of the wrapper: gemspec
  dependencies are not auto-required, see
  [`using_thirdparty_gems.md`](using_thirdparty_gems.md).


## Fonts

`compile_pdf` passes `app/assets/fonts` as the font path, so the output
does not depend on what is installed on the machine that runs it.

## Adding a document

1. Put the template in `app/domain/wsjrdp_2027/typst/<name>.typ` and
   start it with `#import "wsjrdp2027.typ": *`.
2. Read every value from `sys.inputs`, each with a default, so the
   template also compiles on its own:

   ```typst
   #let full_name = sys.inputs.at("full_name", default: "")
   ```

   Defaults are empty (or a fill-in line) — a template carries layout,
   never data, and no personal data at all. Text that somebody typed is
   placed as a plain string, never evaluated as markup: see
   `plain_text` in `refund_receipt.typ`.
3. Apply the letter template and write the body:

   ```typst
   #show: wsjrdp2027_letter.with(
       body-size: 10pt,
       title-text: [Überweisung einer Rückzahlung],
       footer-text: [Rückzahlung],
       role-id-name: role_id,
   )
   ```

   `title-text` is both the PDF title and the heading on the page;
   `footer-text` goes bottom right, `role-id-name` bottom left.
4. Collect the inputs in a domain object (`app/domain/wsjrdp_2027/`)
   with a `to_sys_inputs` that returns Strings, and let it call
   `TypstDocument.compile_pdf`. The controller then only authorizes and
   sends.
