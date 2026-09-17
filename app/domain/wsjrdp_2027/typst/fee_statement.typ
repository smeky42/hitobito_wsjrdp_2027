// What a person paid towards their fee, as the fee page lists
// it. Every value comes from sys.inputs -- the entries as JSON -- and
// is placed as text, never evaluated as markup.
//
// The page is the Kontoauszug of the deregistration confirmation in
// wsjrdp_scripts (registration_tools/bestätigung_abmeldung.typ): same
// heading, same lines, same table, same footer.

#import "wsjrdp2027.typ": *
#import "wagon_helpers.typ": *

#let title_text = sys.inputs.at("title", default: "Kontoauszug")
#let role_id_name = sys.inputs.at("role_id_name", default: "")
#let statement_date = sys.inputs.at("statement_date", default: "")
#let balance = sys.inputs.at("balance", default: "")
#let entries = json(bytes(sys.inputs.at("entries", default: "[]")))

#show: wsjrdp2027_letter.with(
    body-size: 10pt,
    title-text: title_text,
    footer-text: context [
        Kontoauszug #statement_date | Seite #counter(page).get().first() / #counter(page).final().first()
    ],
    role-id-name: role_id_name,
    contact-footer: true,
)

Datum: #statement_date \
Kontostand: #balance

#let description_cell(entry) = block(breakable: false)[
    #set par(spacing: 10pt)
    #plain_text(entry.description)
    #if entry.short_dbtr != "" [
        #parbreak()
        #emph[#plain_text(entry.short_dbtr)]
    ]
]

// A thin grey rule between the rows, no fill; the balance stands above the
// table, so there is no sum row.
#set text(size: 10pt)
#table(
    columns: (2.3cm, 1fr, 2.5cm),
    align: (right, left, right),
    stroke: (x, y) => (
        top: thin-rule,
        bottom: thin-rule,
        left: none,
        right: none,
    ),

    table.header([*Datum*], [*Beschreibung*], [*Betrag*]),
    ..entries.map(entry => (
        { entry.date },
        { description_cell(entry) },
        { entry.amount },
    )).flatten()
)
