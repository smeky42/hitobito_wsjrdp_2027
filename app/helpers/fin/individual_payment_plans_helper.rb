# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The cells of the Individuelle Ratenpläne list (fin/wsjrdp_payment_plans,
# Fin::IndividualPaymentPlanRow). Amounts are whole euros in practice, so they go
# without cents. The styles and the script of the month strip:
# fin/wsjrdp_payment_plans/_individual_plan_styles.
module Fin::IndividualPaymentPlansHelper
  # A month is a column 9px wide (a 7px bar and a 2px gap, the styles); the
  # year marks sit under the first month of a year. The strip's months are the
  # plan's (Fin::ListedPaymentPlan#strip_months).
  BAR_PITCH_PX = 9
  # The cell's padding left and right, which the strip's column adds to the
  # strip.
  STRIP_CELL_PADDING_PX = 8
  # The bar of the full fee (3.400 €, a YP's single payment) is as high as the
  # strip; the others on a square-root scale, so a monthly 200 € still shows.
  BAR_FULL_CENTS = 340_000
  BAR_HEIGHT_PX = 20

  PAYMENT_METHOD_ICONS = {"direct_debit" => "file-signature", "credit_transfer" => "landmark"}.freeze

  # The colour of "bezahlt" by Fin::PaymentProgress#state: green for the fee
  # paid, orange for more, red for less than is due, plain for the rest --
  # and for a person without an active plan, who is not judged.
  PAID_CLASSES = {paid: "ipl-paid-paid", overpaid: "ipl-paid-over", behind: "ipl-paid-behind", on_plan: nil,
                  none: nil}.freeze

  # The columns; the strip's column as wide as the longest strip of the whole
  # list (strip_length months), so it does not change with the filter.
  def individual_plan_table_columns(strip_length)
    notes = ->(row, keys) { individual_plan_notes(row.active_plan, keys) }
    Fin::IndividualPaymentPlansColumns::COLUMNS.map do |col|
      column = col.to_table_column(cell: ->(row) { individual_plan_cell(col.key, row) },
        merged_cell: (notes if col.merge == Fin::IndividualPaymentPlansColumns::NOTES))
      column[:width] = individual_plan_strip_width(strip_length) if col.key == "plan"
      column
    end
  end

  # The strip of `strip_length` months plus the cell's padding, in rem.
  def individual_plan_strip_width(strip_length)
    "#{((strip_length * BAR_PITCH_PX + STRIP_CELL_PADDING_PX) / 16.0).round(4)}rem"
  end

  # The link to the person's Beitrag page with its new-tab companion, muted:
  # the last column, never in the menu, not on a phone.
  def individual_plan_link_column
    {key: "link", label: "", width: "2.75rem", css_class: "ipcol-link", mobile: false,
     cell: ->(row) {
       path = person_fee_path(row.person)
       safe_join([link_to(icon(:"money-bill"), path, class: "text-muted", title: "Beitrags-Seite der Person"),
         wsjrdp_newtab_link(path)])
     }}
  end

  # A cell of the plan's sub-row (Fin::IndividualPaymentPlanDraft): the clock, and
  # the planned values under the cells they would replace, muted and light.
  def individual_plan_draft_cell(draft, col)
    plan = draft.plan
    content =
      case col[:key]
      when "planned" then individual_plan_planned_icon(plan)
      when "activated_at" then "geplant"
      when "payment_method" then individual_plan_payment_method(plan, light: true)
      when "plan" then individual_plan_strip(plan)
      when "begin" then individual_plan_month(plan.first_month)
      when "end" then individual_plan_month(plan.last_month)
      when "count" then plan.count
      when "total" then individual_plan_total(plan, draft.fee_cents)
      else
        individual_plan_draft_notes(plan, col[:merged_keys]) if col[:merged_keys]
      end
    tag.div(content, class: "muted fw-light") if content.present?
  end

  private

  # The cells of the single columns; issue and comment share one
  # (#individual_plan_notes). The plan's figures are those of the plan the row
  # shows (Fin::IndividualPaymentPlanRow#shown_plan), muted for a standard plan.
  def individual_plan_cell(key, row) # rubocop:disable Metrics/CyclomaticComplexity
    person = row.person
    plan = row.shown_plan
    case key
    when "id" then row.id
    when "name" then fin_subject_link(person)
    when "role" then wsjrdp_role_pair(contingent: person.wsjrdp_role, jamboree: person.effective_wsj_role)
    when "status" then fin_person_status(person)
    when "activated_at" then individual_plan_activated_at(row)
    when "payment_method" then individual_plan_payment_method(plan)
    when "plan" then individual_plan_strip(plan, role: person.wsjrdp_role)
    when "begin" then individual_plan_figure(plan, individual_plan_month(plan&.first_month))
    when "end" then individual_plan_figure(plan, individual_plan_month(plan&.last_month))
    when "count" then individual_plan_figure(plan, plan&.count)
    when "total" then individual_plan_total(plan, row.fee_cents)
    when "fee" then tag.span(individual_plan_eur(row.fee_cents), class: "muted")
    when "paid" then individual_plan_paid(row.progress)
    when "open" then individual_plan_eur(row.open_cents)
    end
  end

  def individual_plan_eur(cents) = format_cents_de(cents.to_i, zero_cents: "")

  # "03/26"; nil without a month.
  def individual_plan_month(year_month)
    format("%02d/%02d", year_month.month, year_month.year % 100) if year_month
  end

  # "Mär 2026", as the Ratenplan table of the Beitrag page writes the month.
  def individual_plan_month_name(year_month) = l(year_month.to_time_with_zone(day: 5), format: "%b %Y")

  def individual_plan_ym_key(year_month) = format("%04d-%02d", year_month.year, year_month.month)

  # A figure of the shown plan, muted where that is the standard plan.
  def individual_plan_figure(plan, value)
    return if value.blank?

    plan.standard? ? tag.span(value, class: "muted") : value
  end

  # The day, the year in two digits; the tooltip the full date and the time.
  # "noch nicht" for a plan that was never active.
  def individual_plan_activated_at(row)
    return tag.span("noch nicht", class: "muted fw-light") unless row.activated_at

    at = row.activated_at
    wsjrdp_tip(tag.span(l(at, format: "%d.%m.%y")),
      lines: [["Aktiviert am", l(at.to_date, format: "%A, %d. %B %Y")], ["Uhrzeit", l(at, format: "%H:%M Uhr")]])
  end

  def individual_plan_planned_icon(plan)
    tag.span(icon(:clock), class: "text-warning",
      title: "Geplanter, noch nicht aktivierter Ratenplan: #{individual_plan_eur(plan.total_cents)}")
  end

  # The payment method as an icon: the mandate, muted, for the direct debit
  # (the rule), the bank for the credit transfer (the exception); the tooltip
  # names it. Light in the line of a plan.
  def individual_plan_payment_method(plan, light: false)
    return if plan.nil?

    method = plan.payment_method.presence || Wsjrdp2027::ParticipationFee::DEFAULT_PAYMENT_METHOD
    css = ["fas", "fa-#{PAYMENT_METHOD_ICONS.fetch(method, "question")}", "ipl-#{method.tr("_", "-")}",
      ("ipl-light" if light)].compact
    wsjrdp_tip(tag.i(class: css, "aria-hidden": "true"),
      lines: [["Zahlungsart", Wsjrdp2027::ParticipationFee.payment_method_label(method)]])
  end

  # What came in, in the colour of its state (PAID_CLASSES); in the flag slot
  # beside it a red triangle where the person is behind, an hourglass where
  # an entry's value date lies after the end of the month; the tooltip names
  # the fee, what is due today (with or without the current month's
  # installment), what is missing or ahead, and those entries.
  def individual_plan_paid(progress)
    amount = tag.span(individual_plan_eur(progress.paid_cents), class: PAID_CLASSES[progress.state])
    flags = []
    if progress.state == :behind
      flags << tag.i(class: "fas fa-exclamation-triangle text-danger", "aria-hidden": "true")
    end
    flags << tag.i(class: "fas fa-hourglass-half ipl-late", "aria-hidden": "true") if progress.late_entries.any?
    wsjrdp_tip(individual_plan_flagged(amount, safe_join(flags)), lines: individual_plan_paid_lines(progress))
  end

  # An amount and, beside it, the slot of its flag (a triangle, an hourglass)
  # --
  # there in every row, empty mostly, so the amounts line up at its left and
  # the flags at the slot's.
  def individual_plan_flagged(amount, flag = nil)
    safe_join([amount, tag.span(flag, class: "ipl-flag")])
  end

  def individual_plan_paid_lines(progress)
    lines = [["Bezahlt", individual_plan_eur(progress.paid_cents)], ["Beitrag", individual_plan_eur(progress.fee_cents)]]
    lines << ["Fällig bis heute", individual_plan_due_text(progress)] unless progress.state == :none
    lines << [nil, individual_plan_state_text(progress)]
    if progress.late_entries.any?
      entries = progress.late_entries.map do |entry|
        "#{l(entry.value_date)}: #{individual_plan_eur(entry.amount_cents)} – #{entry.description}"
      end
      lines << ["Valuta nach Monatsende", safe_join(entries, tag.br)]
    end
    lines
  end

  # The amount due and, where the plan has an installment for the current
  # month, whether it is in it.
  def individual_plan_due_text(progress)
    due = individual_plan_eur(progress.due_cents)
    current = progress.current_installment
    return due if current.nil?

    included = progress.current_month_due? ? "inkl." : "ohne"
    "#{due} – #{included} Rate #{individual_plan_month_name(current.year_month)}"
  end

  def individual_plan_state_text(progress)
    case progress.state
    when :none then "Kein aktiver Ratenplan: kein Soll."
    when :paid then "Beitrag bezahlt."
    when :overpaid then "Überbezahlt um #{individual_plan_eur(progress.paid_cents - progress.fee_cents)}."
    when :behind then "In Verzug: es fehlen #{individual_plan_eur(progress.gap_cents)}."
    else "Im Plan."
    end
  end

  # The sum of the installments. Where it misses the fee a triangle follows
  # it: red for a plan that does not cover the fee (the sum in red as well),
  # yellow for one that brings in more -- the check of the person's Beitrag
  # page. The standard plan's sum is muted and unchecked.
  def individual_plan_total(plan, fee_cents)
    return if plan.nil?

    sum = individual_plan_eur(plan.total_cents)
    return individual_plan_flagged(tag.span(sum, class: "muted")) if plan.standard?

    gap = plan.gap_cents(fee_cents)
    return individual_plan_flagged(sum) if gap.zero?

    if gap.positive?
      css = "text-warning"
      text = "Der Ratenplan bringt #{individual_plan_eur(gap)} mehr ein als der Beitrag."
    else
      css = "text-danger"
      text = "Der Ratenplan deckt den Beitrag nicht: es fehlen #{individual_plan_eur(-gap)}."
      # The sum in red as well: the plan falls short.
      sum = tag.span(sum, class: css)
    end
    flag = tag.i(class: "fas fa-exclamation-triangle #{css}", "aria-hidden": "true")
    wsjrdp_tip(individual_plan_flagged(sum, flag), lines: [[nil, text]])
  end

  # The plan as a strip of its months (Fin::ListedPaymentPlan#strip_months): a
  # bar per month, its height by the amount (BAR_FULL_CENTS, square-root
  # scale), a hairline for a month without one; year marks under the first
  # month of each year -- not for a year of which a single month shows, the
  # mark would not fit. Hovering a month's column, the strip's full height,
  # names the month and its amount above the plan's table -- 0 € for a month
  # without one -- and marks the month's line (the tooltip,
  # #individual_plan_tip; the script of the styles partial). The standard
  # plan with hollow bars and a chip naming it.
  def individual_plan_strip(plan, role: nil)
    return if plan.nil?

    months = plan.strip_months
    bars = months.map { |year_month| individual_plan_bar(plan, year_month) }
    marks = months.each_with_index.filter_map do |year_month, index|
      next unless year_month.month == 1 && index + 1 < months.size

      tag.i(year_month.year % 100, style: "left: #{index * BAR_PITCH_PX}px")
    end
    # The chip sits inside the strip: it is placed against the strip's corner.
    chip = (tag.span("Standard #{role}", class: "ipl-standard-chip") if plan.standard?)
    strip = tag.span(safe_join(bars + [tag.span(safe_join(marks), class: "ipl-marks"), chip].compact),
      class: "ipl-strip")
    wsjrdp_tip(strip, lines: [[nil, individual_plan_tip(plan, role)]], aria_label: individual_plan_tip_title(plan, role))
  end

  # One month: a column of the strip's height -- the hover zone, which names
  # the month and its amount -- with the bar at its bottom.
  def individual_plan_bar(plan, year_month)
    cents = plan.cents_in(year_month)
    label = "#{individual_plan_month_name(year_month)}: #{individual_plan_eur(cents)}"
    css = ["ipl-bar", ("ipl-planned" if plan.planned?), ("ipl-standard" if plan.standard?),
      ("ipl-zero" if cents.zero?)].compact
    height = cents.zero? ? 1 : (Math.sqrt(cents / BAR_FULL_CENTS.to_f) * BAR_HEIGHT_PX).round.clamp(2, BAR_HEIGHT_PX)
    tag.span(tag.span(class: css, style: "height: #{height}px"), class: "ipl-month",
      data: {ym: individual_plan_ym_key(year_month), label: label})
  end

  def individual_plan_tip_title(plan, role)
    case plan.kind
    when :active then "Ratenplan"
    when :planned then "Geplanter Ratenplan"
    else "Standard-Ratenplan #{role}"
    end
  end

  # The strip's tooltip: the plan's kind and its sum, then the plan as the
  # Ratenplan table of the Beitrag page shows it (month, amount, balance due
  # by then). Hovering a bar puts its month and amount in place of the sum and
  # marks its line.
  def individual_plan_tip(plan, role)
    count = (plan.count == 1) ? "1 Rate" : "#{plan.count} Raten"
    head = tag.div(safe_join([tag.span(individual_plan_tip_title(plan, role), class: "ipl-tip-kind muted"),
      tag.b("Summe #{individual_plan_eur(plan.total_cents)} · #{count}", class: "ipl-tip-month")], " "),
      class: "ipl-tip-head")
    due = 0
    lines = plan.installments.map do |installment|
      due += installment.cents
      tag.tr(safe_join([tag.td(individual_plan_month_name(installment.year_month)),
        tag.td(individual_plan_eur(installment.cents), class: "text-end"),
        tag.td(individual_plan_eur(due), class: "text-end")]), data: {ym: individual_plan_ym_key(installment.year_month)})
    end
    table = tag.table(safe_join([
      tag.thead(tag.tr(safe_join([tag.th("Zeitpunkt"), tag.th("Betrag", class: "text-end"),
        tag.th("Soll Kontostand", class: "text-end")]))),
      tag.tbody(safe_join(lines))
    ]), class: "ipl-tip-table")
    foot = (tag.div("Gilt, solange kein individueller Ratenplan aktiv ist.", class: "ipl-tip-foot muted") if plan.standard?)
    safe_join([head, table, foot].compact)
  end

  # Issue and comment in one cell, each only where its column is shown: the
  # issue in the first line, then the comment, italic and muted, in at most
  # three lines (the styles). The tooltip names both in full.
  def individual_plan_notes(plan, keys)
    return if plan.nil?

    issue = (plan.issue if keys.include?("issue"))
    comment = (plan.comment if keys.include?("comment"))
    parts = []
    parts << tag.div(individual_plan_issue(issue), class: "ipl-notes-head") if issue.present?
    parts << tag.div(comment, class: "ipl-comment fw-light fst-italic muted") if comment.present?
    individual_plan_notes_tip(plan, safe_join(parts)) if parts.any?
  end

  # The plan's notes in ONE line: "issue · comment", cut with "…" (the
  # styles); the tooltip names both in full.
  def individual_plan_draft_notes(plan, keys)
    parts = []
    parts << individual_plan_issue(plan.issue) if keys.include?("issue")
    parts << plan.comment if keys.include?("comment")
    parts = parts.compact_blank
    return if parts.empty?

    individual_plan_notes_tip(plan, tag.div(safe_join(parts, " · "), class: "ipl-draft-notes"))
  end

  def individual_plan_notes_tip(plan, trigger)
    lines = []
    lines << ["Vorgang", plan.issue] if plan.issue.present?
    lines << ["Kommentar", tag.span(plan.comment, class: "fst-italic")] if plan.comment.present?
    lines.any? ? wsjrdp_tip(trigger, lines: lines) : trigger
  end

  def individual_plan_issue(issue)
    auto_link_escaped_multiline(issue) if issue.present?
  end
end
