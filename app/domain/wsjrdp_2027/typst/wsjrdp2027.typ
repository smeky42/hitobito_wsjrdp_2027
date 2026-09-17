// The contingent's letter, as the wagon writes it.
//
// This file started as the copy in the wsjrdp_scripts repository and has since
// grown options the scripts do not have (a window address field, the contact
// footer, a choosable background and top margin). The two copies therefore
// DIVERGE: a change here does not belong in the scripts unchanged, and the
// scripts' documents keep working here only because every new option defaults
// to the old behaviour.

// The page as it is printed: the letterhead, and the writing area inside it.
#let letter-left = 2.2cm
#let letter-right = 1.8cm
#let letter-width = 21cm - letter-left - letter-right
// Where the contact block and, above it, the classic footer sit -- measured
// from the bottom edge of the page, not from the text.
#let contact-footer-bottom = 1.6cm
#let classic-footer-bottom = 3.2cm
// DIN 5008 form B, for a DIN lang window envelope.
#let window-left = 20mm
#let window-top = 45mm
#let window-width = 85mm
#let window-return-height = 5mm
// The recipient starts a little under the rule, not against it.
#let window-recipient-gap = 2mm
#let window-recipient-height = 38mm
#let window-return-default = (
    "Ring deutscher Pfadfinder*innenverbände e.V. (rdp)",
    "Chausseestraße 128/129 · 10115 Berlin",
)
// Secondary text (the contact block, the return address).
#let contact-grey = rgb("6B6B6B")
// Thin rules: table lines, the rule under the return address.
#let rule-grey = rgb("CCCCCC")
#let thin-rule = 0.4pt + rule-grey

// Who we are, at the bottom of every page: set here rather than drawn into the
// letterhead, so the e-mail address stays a link and the text stays text.
#let wsjrdp2027_contact_footer() = {
    set text(size: 8pt, weight: "light", fill: contact-grey)
    grid(
        columns: (10.7cm - letter-left, 1fr),
        align: (top + left, top + left),
        [
            World Scout Jamboree 2027 \
            #link("https://www.worldscoutjamboree.de/")[German Contingent | Kontyngent Niemiecki] \
            #link("mailto:info@worldscoutjamboree.de")[info\@worldscoutjamboree.de]
        ],
        [
            Ring deutscher Pfadfinder\*innenverbände e.V. (rdp) \
            Chausseestraße 128/129 \
            10115 Berlin
        ]
    )
}

// The return address of the field: up to two lines of 6pt inside the 5mm band
// above the rule. A line that is too wide for the 85mm is cut off rather than
// wrapped -- the band has room for two lines and no more, so a caller with a
// long sender address splits it into lines itself.
#let wsjrdp2027_return_band(return-lines) = {
    box(width: 100%, height: window-return-height, {
        if return-lines.len() > 0 {
            place(bottom + left, dy: -2pt, box(width: 100%, clip: true, block(width: 40cm, {
                set text(size: 6pt, weight: "light", fill: contact-grey, hyphenate: false,
                    top-edge: "cap-height", bottom-edge: "baseline")
                set par(leading: 2pt)
                for (index, return-line) in return-lines.enumerate() {
                    if index > 0 { linebreak() }
                    return-line
                }
            })))
            place(bottom + left, line(length: 100%, stroke: thin-rule))
        }
    })
}

// The address field of a window envelope: the return address with a rule under
// it, then the recipient. Page one only -- the field belongs to the envelope,
// not to the letter.
#let wsjrdp2027_window_address(lines, return-line: none, body-size: 11pt) = {
    let return-lines = if return-line == none {
        window-return-default
    } else if type(return-line) == str {
        if return-line == "" { () } else { (return-line,) }
    } else {
        return-line
    }
    let field-height = window-return-height + window-recipient-gap + window-recipient-height
    box(width: window-width, height: field-height, context {
        if counter(page).get().first() == 1 {
            stack(
                spacing: 0pt,
                wsjrdp2027_return_band(return-lines),
                box(
                    width: 100%,
                    height: window-recipient-gap + window-recipient-height,
                    inset: (top: window-recipient-gap),
                    align(top + left)[
                        #set text(size: body-size)
                        #for (index, recipient-line) in lines.enumerate() {
                            if index > 0 { linebreak() }
                            recipient-line
                        }
                    ]
                )
            )
        }
    })
}

#let wsjrdp2027_letter(
    body-size: 11pt,
    footer-size: none,
    role-id-name: "",
    title-text: "World Scout Jamboree 2027",
    footer-text: none,
    background: "WSJ_Brief_Hintergrund.pdf",
    margin-top: none,
    window-address: none,
    contact-footer: false,
    classic-footer: true,
    doc,
) = {
    let footer-size = if footer-size == none { body-size } else { footer-size }
    let footer-text = if footer-text == none { title-text } else { footer-text }
    let footer-right = [#text(size: footer-size)[#footer-text]]
    // Where the body starts: below the letterhead, or below the address field
    // where there is one.
    let top-margin = if margin-top != none {
        margin-top
    } else if window-address == none {
        5.5cm
    } else {
        10cm
    }
    // Room for whatever is set at the bottom.
    let bottom-margin = if contact-footer and classic-footer {
        4cm
    } else if contact-footer or classic-footer {
        3cm
    } else {
        auto
    }
    let classic-block = context [
        #set text(size: footer-size)
        #grid(
            columns: (1fr, measure(footer-right).width),
            column-gutter: .5cm,
            align: (bottom, bottom + right),
            [#role-id-name], [#footer-right]
        )
    ]

    set document(title: title-text)
    set page(
        background: {
            image(background)
            // Everything that is placed by the page edge rather than by the
            // text: the address field and, where they are asked for, the two
            // footers.
            if window-address != none {
                place(top + left, dx: window-left, dy: window-top,
                    wsjrdp2027_window_address(
                        window-address.at("lines", default: ()),
                        return-line: window-address.at("return-line", default: none),
                        body-size: body-size))
            }
            if contact-footer {
                place(bottom + left, dx: letter-left, dy: -contact-footer-bottom,
                    box(width: letter-width, wsjrdp2027_contact_footer()))
                if classic-footer {
                    // Half a line of air between the classic footer and the
                    // contact block below it.
                    place(bottom + left, dx: letter-left,
                        dy: -(classic-footer-bottom + 0.6 * footer-size),
                        box(width: letter-width, classic-block))
                }
            }
        },
        margin: (top: top-margin, left: letter-left, right: letter-right, bottom: bottom-margin),
        // Without the contact block the classic footer stays where it always
        // was: in the bottom margin, set by the page itself.
        footer: if classic-footer and not contact-footer { classic-block } else { none })

    set text(font: "Montserrat", size: body-size)
    show heading: set text(weight: "semibold")
    show title: set text(size: body-size, weight: "semibold")
    show title: set block(below: 1.5em)

    title()

    doc
}

#let fill-in-box(length, height: 1.5em) = [#box(height: height)#box(align(bottom, line(length: length, stroke: 0.4pt)))]

#let person_id_line(hitobitoid: "", issue: "", ticket-type: "Stornierung") = {
    if hitobitoid != "" and issue != "" [
        (Anmeldungs-ID #hitobitoid / Vorgang #ticket-type: #issue)
    ] else if hitobitoid != "" [
        (Anmeldungs-ID #hitobitoid)
    ] else [
        (Anmeldungs-ID #box(height: 1.5em)#box(align(bottom, line(length: 8cm, stroke: 0.4pt))))
    ]
}

#let signature_line(name, columns: (10em, 20em), signature-height: 3.5em) = {
    grid(
      columns: columns,
      rows: (signature-height, auto),
      column-gutter: 1em,
      row-gutter: 3pt,
      align: (x, y) => if y == 0 { bottom } else { top },
      [#box(width: 1fr, line(length: 100%, stroke: 0.4pt))], [#box(width: 1fr, line(length: 100%, stroke: 0.4pt))],
      [#text(size: 9pt)[Ort, Datum]], [#text(size: 9pt)[#name]],
  )
}

#let signature_lines(names, columns: (10em, 20em), signature-height: 3.5em) = {
    for name in names {
        signature_line(if name != "" { name } else [Unterschrift], columns: columns, signature-height: signature-height)
    }
}
