# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The cells of the Reduktionen list (fin/fee_reductions, Fin::FeeReductionRow).
# Amounts are whole euros in practice, so they go without cents.
module Fin::FeeReductionsHelper
  def fee_reduction_table_columns
    notes = ->(row, keys) { fee_reduction_notes(row.person, keys) }
    Fin::FeeReductionsColumns::COLUMNS.map do |col|
      col.to_table_column(cell: ->(row) { fee_reduction_cell(col.key, row) },
        merged_cell: (notes if col.merge == Fin::FeeReductionsColumns::NOTES))
    end
  end

  private

  # The cells of the single columns; hint, issue and comment share one
  # (#fee_reduction_notes).
  def fee_reduction_cell(key, row) # rubocop:disable Metrics/CyclomaticComplexity
    person = row.person
    case key
    when "id" then row.id
    when "name" then fin_subject_link(person)
    when "role" then fee_reduction_role(person)
    when "regular_fee" then tag.span(fee_reduction_eur(row.regular_fee_cents), class: "muted")
    when "reduction" then fee_reduction_operand("−", person.active_total_fee_reduction * 100)
    when "reduced_fee" then fee_reduction_operand("=", person.total_fee_cents)
    when "status" then fee_reduction_status(person)
    when "activated_at" then fee_reduction_activated_at(row)
    end
  end

  def fee_reduction_eur(cents) = format_cents_de(cents.to_i, zero_cents: "")

  # The role as badges in their colours, with the graphical tooltip naming both
  # (WsjrdpRoleBadgeHelper#wsjrdp_role_pair).
  def fee_reduction_role(person)
    wsjrdp_role_pair(contingent: person.wsjrdp_role, jamboree: person.effective_wsj_role)
  end

  # An amount of the calculation, its operator at the left of the cell.
  def fee_reduction_operand(operator, cents)
    safe_join([tag.span(operator, class: "muted float-start"), fee_reduction_eur(cents)])
  end

  # The registration status in a word, coloured (STATUS_CLASSES); the full
  # label of Settings.status in the graphical tooltip.
  # The status in colour where it matters: confirmed green, a noted
  # deregistration orange, a deregistration red.
  STATUS_CLASSES = {"confirmed" => "fee-reduction-status-confirmed",
                    "deregistration_noted" => "fee-reduction-status-noted",
                    "deregistered" => "fee-reduction-status-deregistered"}.freeze

  STATUS_WORDS = {"registered" => "registriert", "printed" => "gedruckt", "upload" => "hochgeladen",
                  "in_review" => "in Prüfung", "reviewed" => "geprüft", "confirmed" => "bestätigt",
                  "deregistration_noted" => "Abmeldung", "deregistered" => "abgemeldet"}.freeze

  def fee_reduction_status(person)
    status = person.status.to_s
    word = tag.span(STATUS_WORDS.fetch(status, status), class: STATUS_CLASSES[status])
    wsjrdp_tip(word, lines: [["Status", Settings.status[status].presence || status]])
  end

  def fee_reduction_planned_icon(row)
    return unless row.planned?

    amount = fee_reduction_eur(row.person.planned_total_fee_reduction * 100)
    tag.span(icon(:clock), class: "text-warning", title: "Geplante, noch nicht aktivierte Reduktion: #{amount}")
  end

  # The day, the year in two digits; the tooltip the full date, the time and
  # who activated it. "noch nicht" for a plan that was never active.
  def fee_reduction_activated_at(row)
    return tag.span("noch nicht", class: "muted fw-light") unless row.activated_at

    at = row.activated_at
    lines = [["Aktiviert am", l(at.to_date, format: "%A, %d. %B %Y")], ["Uhrzeit", l(at, format: "%H:%M Uhr")]]
    lines << ["von", row.activated_by.to_s] if row.activated_by
    wsjrdp_tip(tag.span(l(at, format: "%d.%m.%y")), lines: lines)
  end

  # Hint, issue and comment in one cell, each only where its column is shown:
  # a first line with the hint at the left and the issue at the right -- left
  # out without either --, then the comment, italic and muted as the comments
  # of the entries, in at most three lines (CSS of the page). The tooltip names
  # every one that is set (#fee_reduction_notes_tip). The page is for the audit
  # tier, who may read the comment.
  def fee_reduction_notes(person, keys)
    hint = (person.active_total_fee_reduction_hint if keys.include?("hint"))
    issue = (person.active_total_fee_reduction_issue if keys.include?("issue"))
    comment = (person.active_total_fee_reduction_comment if keys.include?("comment"))
    parts = []
    if hint.present? || issue.present?
      parts << tag.div(safe_join([tag.span(hint), fee_reduction_issue(issue)].compact),
        class: "fee-reduction-notes-head d-flex justify-content-between gap-2")
    end
    parts << tag.div(comment, class: "fee-reduction-comment fw-light fst-italic muted") if comment.present?
    fee_reduction_notes_tip(person, "active", safe_join(parts)) if parts.any?
  end

  # The notes' tooltip: hint, issue and comment, each that is set, explicitly
  # and in full -- whatever the cell shows of them; the comment in italics, as
  # in the cell.
  def fee_reduction_notes_tip(person, prefix, trigger)
    lines = [%w[Hinweis hint], %w[Vorgang issue], %w[Kommentar comment]].filter_map do |label, attr|
      value = person.public_send(:"#{prefix}_total_fee_reduction_#{attr}")
      next if value.blank?

      [label, (attr == "comment") ? tag.span(value, class: "fst-italic") : value]
    end
    lines.any? ? wsjrdp_tip(trigger, lines: lines) : trigger
  end

  # A cell of the plan's sub-row (Fin::FeeReductionPlan): the clock, and the
  # planned values under the cells they would replace, muted and light.
  def fee_reduction_plan_cell(plan, col)
    person = plan.person
    content =
      case col[:key]
      when "planned" then fee_reduction_planned_icon(plan.row)
      when "activated_at" then "geplant"
      when "reduction" then fee_reduction_operand("−", person.planned_total_fee_reduction * 100)
      when "reduced_fee" then fee_reduction_operand("=", plan.fee_cents)
      else
        fee_reduction_plan_notes(person, col[:merged_keys]) if col[:merged_keys]
      end
    tag.div(content, class: "muted fw-light") if content.present?
  end

  # The plan's notes in ONE line: "hint · issue", cut with "…" (CSS of the
  # page); the tooltip names hint, issue and comment of the plan, each that is
  # set (#fee_reduction_notes_tip).
  def fee_reduction_plan_notes(person, keys)
    parts = []
    parts << person.planned_total_fee_reduction_hint if keys.include?("hint")
    parts << fee_reduction_issue(person.planned_total_fee_reduction_issue) if keys.include?("issue")
    parts = parts.compact_blank
    comment = (person.planned_total_fee_reduction_comment if keys.include?("comment"))
    return if parts.empty? && comment.blank?

    line = tag.div(safe_join(parts, " · ").presence || "Kommentar", class: "fee-reduction-plan-notes")
    fee_reduction_notes_tip(person, "planned", line)
  end

  def fee_reduction_issue(issue)
    auto_link_escaped_multiline(issue) if issue.present?
  end
end
