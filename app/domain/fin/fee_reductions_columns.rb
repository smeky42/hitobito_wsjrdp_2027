# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Column definitions for the Reduktionen tab of the Beiträge area
# (/fin/fee_reductions): one Fin::FeeReductionRow per person with an active or a
# planned total fee reduction. The rows are an array (the regular fee comes from
# the payment role, the activation from the person log), so every column sorts
# by an extractor.
module Fin::FeeReductionsColumns
  # The merge key of hint, comment and issue -- also the name of their block in
  # the columns menu.
  NOTES = "Notizen"

  PLANNED_ICON = '<i class="fas fa-clock" title="Geplante Reduktion"></i>'.html_safe
  PLANNED_LABEL = '<i class="fas fa-clock"></i> Geplant'.html_safe

  # Widths: the longest content or the header with its sort arrow, whichever
  # is wider, plus the cell padding, so that every row stays on one line. With
  # room to spare the person and the notes widen first (`grow:`), then the gaps.
  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "frcol") do |c|
    # A clock in the line of a plan (the row's sub-row): the clock as the
    # header, "Geplant" with the clock in the columns menu; not sortable.
    c.column key: "planned", abbr: "pl", label: PLANNED_LABEL, header_label: PLANNED_ICON, width: "1.25rem",
      default: true
    # Right-aligned, so the date sits next to the person; "noch nicht" (nil)
    # sorts last in either direction.
    c.column key: "activated_at", abbr: "at", label: "Aktiviert", numeric: true, width: "5.25rem",
      sort: ->(row) { row.activated_at }, sort_first: "desc", default: true
    c.column key: "id", abbr: "id", label: "Person-id", header_label: "id", header_tooltip: "Person-id", numeric: true,
      width: "3.5rem",
      sort: ->(row) { row.id }
    c.column key: "name", abbr: "nm", label: "Person", width: "10.25rem", grow: 2,
      sort: ->(row) { row.person.short_full_name_with_nickname.to_s.downcase }, default: true
    # One role: the common one, both where the contingent's role and the role
    # on the Jamboree differ (contingent first); the tooltip names both.
    c.column key: "role", abbr: "ro", label: "Rolle", width: "6.25rem",
      sort: ->(row) { [row.person.wsjrdp_role.to_s, row.person.effective_wsj_role.to_s] }, default: true
    # The registration status (people.status), in a word; the full label is the
    # cell's tooltip.
    c.column key: "status", abbr: "st", label: "Status", width: "5.5rem",
      sort: ->(row) { Settings.status.keys.map(&:to_s).index(row.person.status.to_s) || -1 }, default: true
    # The fee as a calculation under the bracket "Beitrag": regulär − Reduktion
    # = reduziert, the operators at the left of their cells.
    c.column key: "regular_fee", abbr: "rf", label: "Beitrag regulär", header_label: "regulär",
      group: "Beitrag", numeric: true, width: "4.75rem",
      sort: ->(row) { row.regular_fee_cents }, sort_first: "desc", default: true
    c.column key: "reduction", abbr: "red", label: "Reduktion", group: "Beitrag", numeric: true, width: "5.5rem",
      sort: ->(row) { row.person.active_total_fee_reduction }, sort_first: "desc", default: true
    c.column key: "reduced_fee", abbr: "fee", label: "Beitrag reduziert", header_label: "reduziert",
      group: "Beitrag", numeric: true, width: "5.25rem",
      sort: ->(row) { row.person.total_fee_cents }, sort_first: "desc", default: true
    # Hint, comment and issue: a header each (each sorts), ONE cell -- the hint
    # left and the issue right in its first line, the comment in up to three
    # lines below (Fin::FeeReductionsHelper#fee_reduction_notes). In the
    # columns menu they are one block, "Notizen", shown or hidden part by part.
    c.column key: "hint", abbr: "hi", label: "Hinweis", header_tooltip: "Kurzhinweis, wird im Vertrag angezeigt",
      merge: NOTES, grow: 1, width: "6.25rem",
      sort: ->(row) { row.person.active_total_fee_reduction_hint.to_s.downcase }, default: true
    c.column key: "comment", abbr: "cm", label: "Kommentar", header_tooltip: "Nur für Personen mit Buchhaltungs-Rechten",
      merge: NOTES, grow: 1, width: "6rem",
      sort: ->(row) { row.person.active_total_fee_reduction_comment.to_s.downcase }, default: true
    c.column key: "issue", abbr: "is", label: "Vorgang", header_tooltip: "Helpdesk-Vorgang", merge: NOTES, grow: 1,
      width: "6rem", sort: ->(row) { row.person.active_total_fee_reduction_issue.to_s }, default: true
  end
end
