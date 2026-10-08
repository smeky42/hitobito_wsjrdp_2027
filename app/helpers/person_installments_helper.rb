# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The "Ratenplan" section (person/fee/_installments) on the person's Beitrag
# page and in a row of the Individuelle Ratenpläne list: the plan in effect,
# a planned one, the place of the buttons or the plan's form, and the plans
# that were active (Wsjrdp2027::ParticipationFee#installments_history).
module PersonInstallmentsHelper
  # The place of the section's buttons, or of the plan's form in their place,
  # which the Turbo streams of Person::InstallmentsController update. One per
  # person: the list shows many sections on one page.
  def installments_actions_id(person) = "installments_actions_#{person.id}"

  # The privileged view of the Beitrag page -- the issues, the plans, the
  # history, the zero-amount entries: :log on the person, or the finance
  # audit tier (:show_finance), which sees the same in the finance lists.
  def fee_page_privileged?(person) = can?(:log, person) || can?(:show_finance, person)

  # The notice of the last change, for the section of the person it was made
  # for (Person::InstallmentsController#leave_form).
  def installments_notice(person)
    notice = flash[:installments_notice]
    notice["text"] if notice.is_a?(Hash) && notice["person_id"].to_s == person.id.to_s
  end

  # The installments of the plan in effect (Person#yme_list), each with the
  # balance it brings the account to.
  def installments_table_entries(person)
    total_eur = BigDecimal(0)
    person.yme_list.map do |item|
      total_eur += item.eur
      {date: I18n.l(item.to_time_with_zone(day: 5), format: "%b %Y"),
       amount: format_eur_de(item.eur),
       total: format_eur_de(total_eur)}
    end
  end

  # How the plan in effect is paid: the person's individual plan, else the
  # standard plan of the role.
  def installments_payment_method_label(person)
    method = if person.wsjrdp_raw_installments_eur.present?
      person.wsjrdp_installments_payment_method
    else
      person.participation_fee.standard_payment_plan&.payment_method
    end
    Wsjrdp2027::ParticipationFee.payment_method_label(method || Wsjrdp2027::ParticipationFee::DEFAULT_PAYMENT_METHOD)
  end

  # The plan in effect on the status page, in two lines: the plan written
  # out; how it is paid, with the link to the section on the Beitrag page.
  def installments_status_attr(person)
    labeled(Person.human_attribute_name(:wsjrdp_raw_installments_eur),
      safe_join([tag.div(installments_text(person.yme_list) || "keine Raten"),
        tag.div(safe_join([installments_payment_method_label(person),
          link_to(t("people.installments.status_link"), person_fee_path(person, anchor: payment_plan_anchor(person)))], " · "), class: "muted")]))
  end

  # A planned plan against the fee: one line for its panel, a warning when it
  # brings in more, an error when less; nil when it matches.
  def installments_planned_sum_note(person, rule)
    fee_cents = person.total_fee_cents
    sum_cents = rule.custom_installments_cents.to_a.sum(&:to_i)
    gap = sum_cents - fee_cents
    return if gap.zero?

    figures = "(Summe der Raten #{fee_reduction_prose_cents(sum_cents)}, Beitrag #{fee_reduction_prose_cents(fee_cents)})"
    if gap.positive?
      tag.div("Der geplante Ratenplan bringt #{fee_reduction_prose_cents(gap)} mehr ein als der Beitrag #{figures}.",
        class: "small mt-1")
    else
      tag.div(safe_join([fee_reduction_warning_icon,
        "Der geplante Ratenplan deckt den Beitrag nicht: es fehlen #{fee_reduction_prose_cents(-gap)} #{figures}."]),
        class: "small mt-1 fw-semibold text-danger")
    end
  end

  # "Zahlungsart · Vorgang" of a fee rule's plan, the issue linked.
  def installments_rule_facts(rule)
    safe_join([Wsjrdp2027::ParticipationFee.payment_method_label(rule.custom_installments_payment_method),
      rule.custom_installments_issue.presence && auto_link_escaped_multiline(rule.custom_installments_issue)].compact,
      " · ")
  end

  # "Aktiviert am ... von ...", and "abgelöst am ... von ..." for a plan
  # replaced since; the authors where they were recorded.
  def installments_history_header(rule)
    lines = [installments_history_event("Aktiviert", rule.activated_at, rule.activated_by)]
    lines << installments_history_event("abgelöst", rule.deleted_at, rule.deleted_by) if rule.deleted_at
    safe_join(lines, " · ")
  end

  private

  def installments_history_event(label, time, author)
    text = "#{label} #{l(time, format: "%d.%m.%Y %H:%M")}"
    author ? safe_join([text, " von ", link_to_if(can?(:show, author), author.to_s, person_path(author))]) : text
  end
end
