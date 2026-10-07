# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Column definitions of the Individuelle Ratenpläne list on the Ratenpläne tab
# of the Beiträge area (/fin/payment_plans): one Fin::IndividualPaymentPlanRow per
# person with an active or a planned individual installment plan. The rows are
# an array (the fee comes from the payment role, the plan from the person's
# columns), so every column sorts by an extractor. The plan's figures (Beginn,
# Ende, Anzahl, Gesamt ...) are those of the plan the row shows: the active one,
# or the standard plan while only a planned one exists.
module Fin::IndividualPaymentPlansColumns
  # The merge key of issue and comment -- also the name of their block in the
  # columns menu.
  NOTES = "Notizen"

  PLANNED_ICON = '<i class="fas fa-clock" title="Geplanter Ratenplan"></i>'.html_safe
  PLANNED_LABEL = '<i class="fas fa-clock"></i> Geplant'.html_safe
  # The payment method's header: the mandate icon alone, the name in its tooltip.
  PAYMENT_METHOD_ICON = '<i class="fas fa-file-signature" aria-label="Zahlungsart"></i>'.html_safe

  # Widths: the longest content or the header with its sort arrow, whichever
  # is wider, plus the cell padding, so that every row stays on one line. With
  # room to spare the person and the notes widen first (`grow:`), then the gaps.
  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "ipcol") do |c|
    # A clock in the line of a plan (the row's sub-row): the clock as the
    # header, "Geplant" with the clock in the columns menu; not sortable.
    c.column key: "planned", abbr: "pl", label: PLANNED_LABEL, header_label: PLANNED_ICON, width: "1.25rem",
      default: true
    # Right-aligned, so the date sits next to the person; "noch nicht" (nil)
    # sorts last in either direction.
    c.column key: "activated_at", abbr: "at", label: "Aktiviert", numeric: true, width: "5.25rem",
      sort: ->(row) { row.activated_at }, sort_first: "desc", default: true
    # Wide enough for the longest name in the list today to stay on one line;
    # it does not widen beyond its gap.
    c.column key: "name", abbr: "nm", label: "Person", width: "13.5rem",
      sort: ->(row) { row.person.short_full_name_with_nickname.to_s.downcase }, default: true
    # One role: the common one, both where the contingent's role and the role
    # on the Jamboree differ (contingent first); the tooltip names both.
    c.column key: "role", abbr: "ro", label: "Rolle", width: "6.25rem",
      sort: ->(row) { [row.person.wsjrdp_role.to_s, row.person.effective_wsj_role.to_s] }, default: true
    # The registration status (people.status), in a word; the full label is the
    # cell's tooltip.
    c.column key: "status", abbr: "st", label: "Status", width: "5.5rem",
      sort: ->(row) { Settings.status.keys.map(&:to_s).index(row.person.status.to_s) || -1 }, default: true
    # In colour: green for the fee paid, orange for more, red for less than
    # is due today (Fin::PaymentProgress).
    c.column key: "paid", abbr: "pd", label: "bezahlt",
      header_tooltip: "Kontostand der Person: grün = Beitrag bezahlt, orange = überbezahlt, rot = in Verzug",
      numeric: true,
      width: "6.25rem",
      sort: ->(row) { row.paid_cents }, sort_first: "desc", default: true
    c.column key: "total", abbr: "tt", label: "Gesamt", header_tooltip: "Summe der Raten", numeric: true,
      width: "5.5rem",
      sort: ->(row) { row.shown_plan&.total_cents }, sort_first: "desc", default: true
    # The plan as a strip of months, one bar each (Fin::IndividualPaymentPlansHelper).
    # The width here is the standard span's (18 months); the list sets the
    # width of its longest strip at render time.
    c.column key: "plan", abbr: "pn", label: "Ratenplan",
      header_tooltip: "Ein Balken je Monat, Dezember 2025 bis Mai 2027 – länger, wo ein Plan darüber hinausreicht",
      width: "10.625rem", default: true
    # The payment method as an icon (mandate = direct debit, bank = credit
    # transfer); the header the mandate icon, "Zahlungsart" as its tooltip.
    c.column key: "payment_method", abbr: "pm", label: "Zahlungsart", header_label: PAYMENT_METHOD_ICON,
      header_tooltip: "Zahlungsart", width: "2rem", header_align: "center",
      sort: ->(row) { row.shown_plan&.payment_method.to_s }, default: true
    # Issue and comment: a header each (each sorts), ONE cell -- the issue in
    # its first line, the comment in up to three lines below
    # (Fin::IndividualPaymentPlansHelper#individual_plan_notes). In the columns menu
    # they are one block, "Notizen", shown or hidden part by part. Narrow at
    # the least, and the first to widen: the comment takes what room there is.
    c.column key: "issue", abbr: "is", label: "Vorgang", header_tooltip: "Helpdesk-Vorgang", merge: NOTES, grow: 3,
      width: "4rem", sort: ->(row) { row.active_plan&.issue.to_s }, default: true
    c.column key: "comment", abbr: "cm", label: "Kommentar", header_tooltip: "Nur für Personen mit Buchhaltungs-Rechten",
      merge: NOTES, grow: 3, width: "5rem",
      sort: ->(row) { row.active_plan&.comment.to_s.downcase }, default: true
    # Hidden until chosen from the menu: the person's id, the plan's figures,
    # the fee and what is still open.
    c.column key: "id", abbr: "id", label: "Person-id", header_label: "id", header_tooltip: "Person-id", numeric: true,
      width: "3.5rem",
      sort: ->(row) { row.id }
    c.column key: "begin", abbr: "bg", label: "Beginn", numeric: true, width: "3.75rem",
      sort: ->(row) { row.shown_plan&.first_month&.year_month_i }
    c.column key: "end", abbr: "en", label: "Ende", numeric: true, width: "3.75rem",
      sort: ->(row) { row.shown_plan&.last_month&.year_month_i }
    c.column key: "count", abbr: "ct", label: "Anzahl Raten", header_label: "Raten", header_tooltip: "Anzahl Raten",
      numeric: true, width: "3.25rem",
      sort: ->(row) { row.shown_plan&.count }
    # The fee itself stays in the menu: the check against it (the triangle in
    # front of the sum) is what the list is for.
    c.column key: "fee", abbr: "fe", label: "Beitrag", header_tooltip: "Beitrag der Person, den der Plan decken muss",
      numeric: true, width: "4.75rem",
      sort: ->(row) { row.fee_cents }, sort_first: "desc"
    c.column key: "open", abbr: "op", label: "offen", header_tooltip: "Beitrag minus bezahlt", numeric: true,
      width: "5rem",
      sort: ->(row) { row.open_cents }, sort_first: "desc"
  end
end
