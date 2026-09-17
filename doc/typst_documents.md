# Typst documents

PDFs that are letters — something a person or a team reads, on the
contingent's letterhead — are written as [Typst](https://typst.app)
templates and compiled by the `typst` gem. (The registration contract
takes the other route, Prawn in
[`app/domain/wsjrdp_2027/export/pdf/`](../app/domain/wsjrdp_2027/export/pdf/):
it draws a form, not a letter.)

The letter layout comes from the `wsjrdp_scripts` repository, which
compiles the same letters on the Python side. `wsjrdp2027.typ` started
as that copy and has since **diverged**: it carries options the scripts
do not have (the window address field, the contact footer, a choosable
background and top margin). All of them default to the old behaviour, so
a document written for the scripts' copy still compiles here — but a
change made here does not belong in the scripts unchanged.


## Where the files are

| Path | What it is |
| --- | --- |
| `app/domain/wsjrdp_2027/typst/` | the Typst project root: every template, plus what they include |
| `app/domain/wsjrdp_2027/typst/wsjrdp2027.typ` | the letter template (`wsjrdp2027_letter`, `fill-in-box`, `person_id_line`, `signature_line(s)`) |
| `app/domain/wsjrdp_2027/typst/wagon_helpers.typ` | the helpers only our own templates use (`plain_text`) |
| `app/domain/wsjrdp_2027/typst/WSJ_Brief_Hintergrund.pdf` | the letterhead our documents use, set as the page background |
| `app/assets/fonts/Montserrat-*.ttf` | the fonts the compile is given |
| `app/domain/wsjrdp_2027/typst_document.rb` | the wrapper that compiles a template |

The templates sit next to the domain code that fills them, the way the
core keeps its own PDF assets (`app/domain/invoice/assets`). Zeitwerk
leaves the directory alone — it holds no `.rb` file and is therefore no
namespace.

The letterhead sits next to the templates because `wsjrdp2027.typ`
pulls it in with a relative `image(background)`. That whole directory is
the Typst project root, so a template can `#import` its siblings and
read nothing outside.


## What the letter takes

`wsjrdp2027_letter` is applied with `#show: wsjrdp2027_letter.with(…)`.
Beside `body-size`, `title-text`, `footer-text`, `footer-size` and
`role-id-name` it takes:

| Option | Default | What it does |
| --- | --- | --- |
| `background` | `"WSJ_Brief_Hintergrund.pdf"` | the page background; the file lies next to the templates |
| `margin-top` | `none` | where the body starts; unset it is 5.5cm, or 10cm with a window address |
| `window-address` | `none` | `(lines: (…), return-line: …)` sets a DIN 5008 form B address field on page 1: 20mm from the left, 45mm from the top, 85 × 45mm. The first 5mm are the return address above a thin rule, then 2mm of air, then 38mm for the recipient. `return-line` takes an array of lines, a single string, or `""` for none; unset it is the rdp's own two lines. The band holds two lines of 6pt and nothing more — a line too wide for the 85mm is cut off rather than wrapped, so a long sender address is split by the caller |
| `contact-footer` | `false` | sets the three-line contact block (grey, 8.5pt, two columns) at the bottom of every page, 1.6cm above the page edge. It is set in Typst, not drawn into the letterhead, so the e-mail address stays a link |
| `classic-footer` | `true` | the `role-id-name` / `footer-text` line. With the contact block it moves up to 3.2cm above the page edge; `false` leaves it out altogether |

The bottom margin follows: 4cm with both footers, 3cm with one, the
page default with neither.

The letterhead's own header ends about 44mm below the top edge, which is
why the body starts at 5.5cm and the address field at 45mm.


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
does not depend on what is installed on the machine that runs it. The
directory holds the Montserrat faces the templates use: Regular, Italic,
Light and LightItalic (the contact footer and the window's return address
are set light), SemiBold and SemiBoldItalic (headings, emphasised values),
Bold and BoldItalic. A weight without a face of its own would silently be
rendered with the nearest one, so add the file before using a new weight.

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
