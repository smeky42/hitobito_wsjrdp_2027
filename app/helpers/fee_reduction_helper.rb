# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The change history of the "Beitragshöhe" section (person/fee/_fee_reduction):
# the person versions that change the active total fee reduction, each shown
# with those changes only. Planned values and the comment never reach the log
# (they are skipped in PaperTrail), so this is what took effect, without the
# comment.
module FeeReductionHelper
  # The active attributes in the order the section lists them.
  FEE_REDUCTION_LOG_ATTRS = %w[
    wsjrdp_total_fee_reduction
    wsjrdp_total_fee_reduction_issue
    wsjrdp_total_fee_reduction_hint
  ].freeze

  # The place of the section's buttons, or of the plan's form in their place,
  # which the Turbo streams of Person::FeeReductionController update. One per
  # person: the Reduktionen list shows many sections on one page.
  def fee_reduction_actions_id(person) = "fee_reduction_actions_#{person.id}"

  # The notice of the last change, for the section of the person it was made
  # for (Person::FeeReductionController#leave_form).
  def fee_reduction_notice(person)
    notice = flash[:fee_reduction_notice]
    notice["text"] if notice.is_a?(Hash) && notice["person_id"].to_s == person.id.to_s
  end

  def fee_reduction_versions(person)
    PaperTrail::Version
      .where(item_type: Person.sti_name, item_id: person.id, event: %w[create update])
      # Old versions may change the comment alone; they have nothing to show.
      .where("object_changes ~ ?", "(?n)^wsjrdp_total_fee_reduction(_issue|_hint)?:")
      .reorder(created_at: :desc, id: :desc)
  end

  # How far the installments of the person's payment plan (Person#yme_list)
  # miss the fee: positive when they bring in more than fee_cents, negative
  # when less.
  def fee_reduction_installments_gap_cents(person, fee_cents)
    person.yme_list.sum(&:cents) - fee_cents
  end

  # The installments against the fee: a warning (yellow) when they bring in
  # more, an error (red) when they bring in less; nil when they match.
  def fee_reduction_installments_alert(person)
    fee_cents = person.total_fee_cents
    gap = fee_reduction_installments_gap_cents(person, fee_cents)
    return if gap.zero?

    sum = fee_reduction_prose_cents(fee_cents + gap)
    if gap.positive?
      tag.div(class: "alert alert-warning py-1 px-2 mt-2 mb-0") do
        "Der Ratenplan bringt #{fee_reduction_prose_cents(gap)} mehr ein als der Beitrag " \
          "(Summe der Raten #{sum}, Beitrag #{fee_reduction_prose_cents(fee_cents)})."
      end
    else
      tag.div(class: "alert alert-danger py-1 px-2 mt-2 mb-0 fw-semibold") do
        safe_join([fee_reduction_warning_icon,
          "Der Ratenplan deckt den Beitrag nicht: es fehlen #{fee_reduction_prose_cents(-gap)} " \
          "(Summe der Raten #{sum}, Beitrag #{fee_reduction_prose_cents(fee_cents)})."])
      end
    end
  end

  # The same comparison for a planned reduction, once activated: one line for
  # the planned reduction's panel; nil when the installments would match.
  def fee_reduction_planned_installments_note(person, planned_fee_cents)
    gap = fee_reduction_installments_gap_cents(person, planned_fee_cents)
    return if gap.zero?

    if gap.positive?
      tag.div("Nach Aktivierung bringt der Ratenplan #{fee_reduction_prose_cents(gap)} mehr ein als der Beitrag.",
        class: "small mt-1")
    else
      tag.div(safe_join([fee_reduction_warning_icon,
        "Nach Aktivierung deckt der Ratenplan den Beitrag nicht: es fehlen #{fee_reduction_prose_cents(-gap)}."]),
        class: "small mt-1 fw-semibold text-danger")
    end
  end

  # The warning triangle in front of a red message: the installments do not
  # bring in the fee.
  def fee_reduction_warning_icon
    tag.i(class: "fas fa-exclamation-triangle me-1", "aria-hidden": "true")
  end

  # An amount within a sentence: "1.700€", "123,45€".
  def fee_reduction_prose_cents(cents)
    format_cents_de(cents, space: "", zero_cents: "")
  end

  # "Wann · Wer" of a version, the author linked where the viewer may see them.
  def fee_reduction_version_header(version)
    decorated = PaperTrail::VersionDecorator.new(version)
    safe_join([decorated.created_at, decorated.author].compact_blank, " · ")
  end

  # One line per changed attribute.
  def fee_reduction_change_lines(version)
    changes = version.changeset
    lines = FEE_REDUCTION_LOG_ATTRS.filter_map do |attr|
      next unless changes.key?(attr)

      from, to = changes[attr]
      next if from.to_s == to.to_s

      fee_reduction_change_line(attr, from, to)
    end
    safe_join(lines, tag.br)
  end

  private

  def fee_reduction_change_line(attr, from, to)
    "#{Person.human_attribute_name(attr)}: #{fee_reduction_log_value(attr, from)} → " \
      "#{fee_reduction_log_value(attr, to)}"
  end

  def fee_reduction_log_value(attr, value)
    if attr == "wsjrdp_total_fee_reduction"
      format_eur_de(value || 0, space: "", zero_cents: "")
    elsif value.blank?
      "leer"
    else
      "„#{value}“"
    end
  end
end
