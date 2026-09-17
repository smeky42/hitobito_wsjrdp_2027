// The slip the finance team pays a deregistration back from. Every value comes
// from sys.inputs and defaults to empty: this file carries the layout, never
// any data. See doc/typst_documents.md.

#import "wsjrdp2027.typ": *
#import "wagon_helpers.typ": *

#let title_text = sys.inputs.at("title", default: "Überweisung einer Rückzahlung")
#let greeting = sys.inputs.at("greeting", default: "")
#let show_explanation = sys.inputs.at("show_explanation", default: "true") == "true"
#let kind = sys.inputs.at("kind", default: "withdrawal")
#let generated_on = sys.inputs.at("generated_on", default: "")
#let generated_by = sys.inputs.at("generated_by", default: "")
#let role_name = sys.inputs.at("role_name", default: "")
#let person_name = sys.inputs.at("person_name", default: "")
#let person_id = sys.inputs.at("person_id", default: "")
#let team_unit = sys.inputs.at("team_unit", default: "")
#let creditor_name = sys.inputs.at("creditor_name", default: "")
#let total_fee = sys.inputs.at("total_fee", default: "")
#let amount_paid = sys.inputs.at("amount_paid", default: "")
#let compensation = sys.inputs.at("compensation", default: "")
#let refund = sys.inputs.at("refund", default: "")
#let booking_text = sys.inputs.at("booking_text", default: "")
#let requested_date = sys.inputs.at("requested_date", default: "")
#let effective_date = sys.inputs.at("effective_date", default: "")
#let ticket = sys.inputs.at("ticket", default: "")
#let amount = sys.inputs.at("amount", default: "")
#let purpose = sys.inputs.at("purpose", default: "")
#let account_holder = sys.inputs.at("account_holder", default: "")
#let iban = sys.inputs.at("iban", default: "")

#show: wsjrdp2027_letter.with(
    body-size: 10pt,
    title-text: title_text,
    contact-footer: true,
    classic-footer: false,
)

#let strong-value(body) = text(weight: "semibold")[#body]
// The booking text is what is copied into Moss, so it is the one value the
// page points at.
#let booking-value(body) = text(weight: "semibold", fill: rgb("1F5F8B"))[#body]

// A date that is not known yet is a line to fill in by hand, the way the
// contingent's other letters leave a missing value.
#let requested_date_or_line = if requested_date != "" { requested_date } else { fill-in-box(3cm) }

// Said in full, so the receipt can be read on its own: what happened, what the
// fee is, what was paid, what is kept, what comes back.
#let explanation = [
    #if kind == "termination" [
        Am #requested_date_or_line ist der Reisevertrag von #person_name durch das deutsche Kontingent gekündigt worden.
    ] else [
        Am #requested_date_or_line ist der Rücktritt von #person_name vom Reisevertrag erklärt worden.
    ]
    Die Teilnahme, als #role_name, im deutschen Kontingent kostet #total_fee.
    Bisher wurden #amount_paid bezahlt.
    Als Entschädigung ans deutsche Kontingent wurden #compensation vereinbart.
    Daraus ergibt sich eine Erstattung von #refund.
]

#v(1em)

#if greeting.trim() != "" [
    #plain_text(greeting)
]

#if show_explanation [
    #explanation
]

#v(1em)

#table(
    columns: (30%, 70%),
    stroke: thin-rule,
    align: (left + horizon, left + horizon),

    [Person], [#person_name],
    [Anmeldungs-ID], [#person_id],
    [Team/Unit], [#team_unit],
    [Kreditor], [#creditor_name],
    [Buchungstext], [#booking-value(booking_text)],
    [Abmeldung angefragt am], [#requested_date],
    [Abmeldung zum], [#effective_date],
    [Rechnungsnummer], [#booking-value(ticket)],
    [Betrag], [#booking-value(amount)],
    [Verwendungszweck], [#purpose],
    [Kontoinhaber], [#account_holder],
    [IBAN], [#iban],
)

#v(1.5em)

// Who asked for the receipt, and when -- without the name where none is known.
#let created_line = if generated_by != "" {
    "Erstellt am " + generated_on + " von " + generated_by
} else {
    "Erstellt am " + generated_on
}

#text(fill: contact-grey, size: 9pt)[#created_line]
