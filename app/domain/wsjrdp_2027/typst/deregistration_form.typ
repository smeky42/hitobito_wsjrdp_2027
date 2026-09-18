// The declaration a person signs to withdraw from the contract for the World
// Scout Jamboree 2027 -- the wagon's copy of the scripts' Abmelde-Formular
// (registration_tools/create_deregistration_form.typ), in the same wording.
//
// Every value comes from sys.inputs and defaults to empty: this file carries
// the layout, never any data. An empty value is one the page does not know and
// becomes a line to fill in by hand. See doc/typst_documents.md.

#import "wsjrdp2027.typ": *

// An amount as a number, so the text can ask whether there is one at all: none
// where nothing is known.
#let cents_or_none(key) = {
    let value = sys.inputs.at(key, default: "")
    if value == "" { none } else { int(value) }
}

// An amount as it is written, or a line to fill in with the euro sign behind it.
#let display_or_line(key, length: 4cm) = {
    let value = sys.inputs.at(key, default: "")
    if value != "" { value } else [#fill-in-box(length)~€]
}

// Anything else the running text states, or a line of `length` to fill in.
#let text_or_line(key, length, height: 1.5em) = {
    let value = sys.inputs.at(key, default: "")
    if value != "" { value } else { fill-in-box(length, height: height) }
}

#let role_id_name = sys.inputs.at("role_id_name", default: "")
#let contract_names = json(bytes(sys.inputs.at("contract_names", default: "[\"Unterschrift Teilnehmer*in\", \"\", \"\"]")))
#let hitobitoid = text_or_line("hitobitoid", 3.9cm)
#let full_name = text_or_line("full_name", 14cm)
#let birthday_de = text_or_line("birthday_de", 4cm)
#let cancellation_date_de = text_or_line("cancellation_date_de", 4cm)
#let refund_iban = text_or_line("refund_iban", 10cm, height: 2em)
#let refund_account_holder = text_or_line("refund_account_holder", 10cm, height: 2em)

#let amount_paid_cents = cents_or_none("amount_paid_cents")
#let actual_compensation_cents = cents_or_none("actual_compensation_cents")
#let contractual_compensation_cents = cents_or_none("contractual_compensation_cents")
#let refund_amount_cents = cents_or_none("refund_amount_cents")
#let missing_amount_cents = cents_or_none("missing_amount_cents")

#let amount_paid_display = display_or_line("amount_paid_display")
#let actual_compensation_display = display_or_line("actual_compensation_display")
#let contractual_compensation_display = display_or_line("contractual_compensation_display")
#let refund_amount_display = display_or_line("refund_amount_display")
#let missing_amount_display = display_or_line("missing_amount_display")

#let has-contractual-compensation-amount = contractual_compensation_cents != none

#let rdp = [Ring deutscher Pfadfinder*innenverbände e.V. (rdp)]

// Where a refund goes: the person's own account, as it is stored with the bank
// details.
#let konto-auszahlung = grid(
    columns: (1.5cm, 4cm, auto),
    align: bottom,
    [], [Kontoinhaber*in:], refund_account_holder,
    [#box(height: 1.5em)], [IBAN:], refund_iban,
)

// Where an outstanding amount goes: the Jamboree account, with the remittance
// information the payment is found by.
#let betreff_einzahlung = if role_id_name != "" [#role_id_name Beitrag WSJ27] else [\<Anmeldungs-ID\> \<Name\> Beitrag WSJ27]
#let konto-einzahlung = grid(
    columns: (1.5cm, 4cm, auto),
    align: bottom,
    [], [Verwendungszweck:], [#betreff_einzahlung],
    [#box(height: 1.5em)], [Kontoinhaber*in:], [Ring deutscher Pfadfinder\'innen],
    [#box(height: 1.5em)], [IBAN:], [DE13 3706 0193 2001 9390 44],
    [#box(height: 1.5em)], [Bank:], [Pax-Bank],
)

#show: wsjrdp2027_letter.with(
    body-size: 10pt,
    title-text: [Abmeldung von der Teilnahme am World Scout Jamboree 2027],
    role-id-name: role_id_name,
    footer-text: [Abmeldung],
    contact-footer: true,
)

Hiermit #(if contract_names.len() == 1 [erkläre ich] else [erklären wir])
zum #cancellation_date_de
beim #rdp,
Chausseestraße 128/129, 10115 Berlin
den Rücktritt vom Vertrag zur Teilnahme im deutschen Kontingent
zum 26. World Scout Jamboree 2027 in Polen von

#par(first-line-indent: 1.5cm, [#full_name])
#par(first-line-indent: 1.5cm, [geboren am #birthday_de #h(2em) Anmeldungs-ID: #hitobitoid])



#v(.6em)
#if refund_amount_cents == none [
    Falls es eine Rückzahlung gibt, soll diese auf folgendes Konto überwiesen werden: #konto-auszahlung

    #v(.6em)
    Ausstehende Beiträge werden wir auf das Jamboree-Konto überweisen: #konto-einzahlung
] else if missing_amount_cents > 0 [
    Den ausstehenden Betrag von #missing_amount_display
    #(if contract_names.len() == 1 [werde ich] else [werden wir]) auf das Jamboree-Konto überweisen: #konto-einzahlung
] else [
    Die Rückzahlung von
    #refund_amount_display
    soll auf folgendes Konto überwiesen werden: #konto-auszahlung]



#v(.6em)
Bisher #(if contract_names.len() == 1 [habe ich] else [haben wir]) Teilnahmebeiträge
in Höhe von #amount_paid_display bezahlt.

#if actual_compensation_cents != none and contractual_compensation_cents != none and (actual_compensation_cents < contractual_compensation_cents) [
  #(if contract_names.len() == 1 [Ich nehme] else [Wir nehmen]) das Angebot an,
  für den Rücktritt vom Teilnahmevertrag dem #rdp eine Entschädigung in Höhe von
  #actual_compensation_display
  zu leisten.
] else [
  #(if contract_names.len() == 1 [Ich verpflichte mich] else [Wir verpflichten uns]),
  dem #rdp eine Entschädigung in Höhe von
  #actual_compensation_display
  zu leisten.
]

#if has-contractual-compensation-amount [
    #set text(fill: gray)
    #(if contract_names.len() == 1 [Mir] else [Uns])
    ist bekannt, dass dem #rdp laut Abschnitt 7.2 der
    Teilnahme- und Reisebedingungen eine Entschädigung in Höhe von
    #contractual_compensation_display
    zusteht.]



#signature_lines(contract_names, signature-height: 3em)
