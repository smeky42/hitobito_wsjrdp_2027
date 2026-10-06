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
  # `source:` names the Moss level the value belongs to when it is not the
  # booking's own (see #moss_with_source).
  def moss_labeled_attr_if_present(obj, attr, source: nil)
    value = obj&.send(attr)
    return if value.blank?

    formatted = value.is_a?(Date) ? l(value) : wsjrdp_format_attr(obj, attr)
    form_like_labeled(captionize(attr, object_class(obj)), moss_with_source(formatted, source))
  end

  # Line 1 of the booking page's "Transaktion" field: "#746" as a double link
  # (here + new tab) for whoever may see the transaction, the bare "#746"
  # otherwise; then, unlinked, the transaction's Buchungstext and its amount --
  # the amount only where it differs from the booking's (a transaction split
  # across several bookings).
  def moss_booking_transaction_line(booking)
    tx = booking.moss_transaction
    label = "##{tx.id}"
    ref = if can?(:show, tx)
      safe_join([link_to(label, moss_transaction_path(tx)), wsjrdp_newtab_link(moss_transaction_path(tx))])
    else
      label
    end
    parts = [ref, tx.display_text.presence]
    if tx.signed_total_base_amount != booking.signed_base_amount
      parts << "(#{fin_money(tx.signed_total_base_amount, tx.currency.presence || "EUR")})"
    end
    safe_join(parts.compact, " ")
  end

  # The booking page shows values of the booking's transaction and expense next
  # to its own; such a value gets a help line naming its level (:transaction /
  # :expense), so it is not taken for a property of the booking itself.
  def moss_with_source(content, source)
    return content if source.nil?

    safe_join([content, wsjrdp_row_help("aus der #{moss_level_name(source)}")])
  end

  # The Buchungstext block of the booking page: MossBooking#text_lines plus the
  # booking's own line where text_lines drops it for only repeating the text
  # above (right for the wallet's compact cell) -- this page is the booking's,
  # so its own Buchungstext always shows.
  def moss_booking_page_text_lines(booking)
    lines = booking.text_lines
    text = booking.booking_posting_text.to_s.strip.presence
    return lines if text.nil? || lines.any? { |level, _name, _text| level == :booking }

    lines + [[:booking, nil, text]]
  end

  def format_moss_booking_accounting_entry_id(tx)
    link_to(tx.accounting_entry_id, url_for(tx.accounting_entry))
  end

  def format_moss_booking_amount(tx)
    tx.amount_eur_display
  end

  # Betrag / Original-Betrag on the booking page: always two decimals
  # ("-1.900,00 €", not "-1.900,— €"), as everywhere in the finance views.
  def format_moss_booking_amount_with_currency(tx)
    fin_money(tx.signed_base_amount, tx.currency.presence || "EUR")
  end

  def format_moss_booking_original_amount_with_currency(tx)
    fin_money(tx.signed_transaction_amount, tx.currency_original.presence || tx.currency.presence || "EUR")
  end
end
