# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module PersonInstallmentsHelper
  # One per person: a list shows many sections on one page.
  def installments_actions_id(person) = "installments_actions_#{person.id}"

  def fee_page_privileged?(person) = can?(:log, person) || can?(:show_finance, person)

  def installments_notice(person)
    notice = flash[:installments_notice]
    notice["text"] if notice.is_a?(Hash) && notice["person_id"].to_s == person.id.to_s
  end

  def installments_payment_method_label(person)
    method = if person.wsjrdp_raw_installments_eur.present?
      person.wsjrdp_installments_payment_method
    else
      person.participation_fee.standard_payment_plan&.payment_method
    end
    Wsjrdp2027::ParticipationFee.payment_method_label(method || Wsjrdp2027::ParticipationFee::DEFAULT_PAYMENT_METHOD)
  end

  def installments_status_attr(person)
    labeled(Person.human_attribute_name(:wsjrdp_raw_installments_eur),
      safe_join([installments_chips(person.yme_list), " ",
        tag.span(safe_join([installments_payment_method_label(person),
          link_to(t("people.installments.status_link"), person_fee_path(person, anchor: payment_plan_anchor(person)))], " · "),
          class: "muted text-nowrap")]))
  end

  def installments_planned_sum_note(person, rule)
    fee_cents = person.total_fee_cents
    sum_cents = rule.installment_plan.sum_cents
    gap = sum_cents - fee_cents
    return if gap.zero?

    figures = "(Summe der Raten #{cents_in_prose(sum_cents)}, Beitrag #{cents_in_prose(fee_cents)})"
    if gap.positive?
      tag.div("Der geplante Ratenplan bringt #{cents_in_prose(gap)} mehr ein als der Beitrag #{figures}.",
        class: "small mt-1")
    else
      tag.div(safe_join([warning_triangle_icon,
        "Der geplante Ratenplan deckt den Beitrag nicht: es fehlen #{cents_in_prose(-gap)} #{figures}."]),
        class: "small mt-1 fw-semibold text-danger")
    end
  end

  def installments_preview_id(person) = "installments_preview_#{person.id}"

  def installments_preview_fees(person)
    fees = [{label: "Beitrag", cents: person.total_fee_cents}]
    planned = person.planned_total_fee_reduction
    fees << {label: "Nach geplanter Reduktion", cents: person.total_fee_cents_with_reduction(planned)} if planned.present?
    fees
  end

  def installments_rule_facts(rule)
    safe_join([Wsjrdp2027::ParticipationFee.payment_method_label(rule.custom_installments_payment_method),
      rule.custom_installments_issue.presence && auto_link_escaped_multiline(rule.custom_installments_issue)].compact,
      " · ")
  end

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
