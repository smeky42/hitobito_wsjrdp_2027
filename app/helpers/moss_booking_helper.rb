# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module MossBookingHelper
  def moss_level_name(level) = MossBooking::LEVEL_NAMES.fetch(level)

  # One line of MossBooking#text_lines: the level tag muted, then the name,
  # then the Buchungstext in italics after an en dash.
  def moss_text_line(level, name, text)
    parts = [content_tag(:span, "#{moss_level_name(level)}: ", class: "fw-light muted")]
    parts << content_tag(:span, name) if name.present?
    parts << content_tag(:span, " – ", class: "muted") if name.present? && text.present?
    parts << content_tag(:span, auto_link_escaped_multiline(text), class: "fst-italic") if text.present?
    safe_join(parts)
  end

  # A labeled read-only row for `attr` of `obj`, or nothing when it is blank.
  # The three Moss levels carry many kind-specific dates (a card payment has
  # six, a reimbursement two); an empty row per absent one would bury the few
  # that matter. Dates that live in jsonb come back as Date objects from their
  # accessors, so they are localised here rather than by format_attr.
  def moss_labeled_attr_if_present(obj, attr)
    value = obj&.send(attr)
    return if value.blank?

    formatted = value.is_a?(Date) ? l(value) : wsjrdp_format_attr(obj, attr)
    form_like_labeled(captionize(attr, object_class(obj)), formatted)
  end

  def format_moss_booking_accounting_entry_id(tx)
    link_to(tx.accounting_entry_id, url_for(tx.accounting_entry))
  end

  def format_moss_booking_amount(tx)
    tx.amount_eur_display
  end
end
