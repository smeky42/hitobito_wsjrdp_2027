# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The formatters of a Beitragsbuchung's detail (fin/accounting_entries/_detail,
# doc/fin/detail_partials.md): one per field that shows more than its stored
# value; dates, times and the amount fall to the kit's type rules.
module Fin::AccountingEntriesHelper
  # The page's title after "Buchung #id": amount, what it is and its value
  # date -- "-401,50 € · Rücklastschrift MS03 · 05.11.2026".
  def fin_accounting_entry_summary(entry)
    [fin_money(entry.amount_cents.to_i / 100.0), fin_accounting_entry_kind(entry), fin_date(entry.value_date)]
      .compact_blank.join(" · ")
  end

  # What the entry is, in a few words: a return with its reason, a status
  # change, a debit, else the start of its description.
  def fin_accounting_entry_kind(entry)
    if entry.return_reason.present? then "Rücklastschrift #{entry.return_reason}"
    elsif entry.new_sepa_status.present? && entry.amount_cents.to_i.zero?
      "Finanzstatus #{entry.new_sepa_status_display}"
    elsif entry.direct_debit_pre_notification_id then "SEPA-Einzug"
    else
      truncate(entry.description.to_s.squish, length: 40)
    end
  end

  # The entry itself: a link in a table row's pane, nothing on its own page.
  def fin_format_accounting_entry_id(entry, ctx)
    return {hide: true} if ctx.regular?

    link_to_if(can?(:show, entry), "##{entry.id}", accounting_entry_path(entry))
  end

  # Only where the debit announced another amount than was booked.
  def fin_format_accounting_entry_pre_notified_amount_cents(entry)
    cents = entry.pre_notified_amount_cents
    return {hide: true} if cents.nil? || cents == entry.amount_cents

    fin_money(cents / 100.0)
  end

  # The person, linked only where the viewer may open the person (assoc_link).
  def fin_format_accounting_entry_subject(entry)
    entry.subject.is_a?(Person) ? assoc_link(entry.subject) : entry.subject_type
  end

  def fin_format_accounting_entry_source(entry)
    if entry.direct_debit_pre_notification_id then "SEPA-Einzug"
    elsif entry.camt_transaction_id then "Kontoauszug"
    elsif entry.moss_booking_id then "Moss"
    end
  end

  def fin_format_accounting_entry_new_sepa_status(entry) = entry.new_sepa_status_display

  # The bank transaction, linked, with its value date, amount and the start of
  # its purpose -- "#560 05.11.2026 · -401,50 € · Retoure SEPA Lastschrift …".
  def fin_format_accounting_entry_camt_transaction_id(entry)
    id = entry.camt_transaction_id
    return nil unless id

    tx = entry.camt_transaction
    summary = tx && [fin_date(tx.value_date), fin_money(tx.signed_base_amount),
      truncate(tx.description.to_s.squish, length: 120)].compact_blank.join(" · ")
    fin_accounting_entry_link("##{id}", wsjrdp_camt_transaction_path(id), summary)
  end

  # The DATEV booking the entry is reconciled with: linked, with its date,
  # amount and posting text, and how the link came about as the help line.
  def fin_format_accounting_entry_datev_booking_id(entry)
    booking = entry.datev_booking
    return nil unless booking

    summary = [fin_date(booking.booking_date), booking_base_amount_with_sh(booking),
      truncate(booking.posting_text.to_s.squish, length: 80)].compact_blank.join(" · ")
    meta = entry.datev_booking_link_meta.to_h
    score = meta["score"].present? && "Score #{(meta["score"].to_f * 100).round} %"
    help = [link_provenance(meta), (score if meta["automatic_manual"] == "automatic")].compact_blank.join(" · ")
    {value: fin_accounting_entry_link("##{booking.id}", booking_path(booking), summary), help: help.presence}
  end

  # The Sammler (payment information) the entry's debit went out in.
  def fin_format_accounting_entry_direct_debit_payment_info_id(entry)
    info = entry.direct_debit_payment_info
    return nil unless info

    fin_accounting_entry_link("##{info.id}", direct_debit_payment_info_path(info),
      info.requested_collection_date && "fällig #{fin_date(info.requested_collection_date)}")
  end

  # Cancellation: the entry this one cancels, or the one that cancels it.
  def fin_format_accounting_entry_reverses_id(entry)
    id = entry.reverses_id
    id && fin_accounting_entry_link("##{id}", accounting_entry_path(id))
  end

  def fin_format_accounting_entry_reversed_by_id(entry)
    id = entry.reversed_by_id
    id && fin_accounting_entry_link("##{id}", accounting_entry_path(id))
  end

  # Who created the entry, linked where the viewer may open the person.
  def fin_format_accounting_entry_author(entry)
    author = entry.author
    author.is_a?(Person) ? assoc_link(author) : author&.to_s
  end

  # A field of the edit page that only reads, as the reading page shows it --
  # value and help line --, or nothing where the reading page shows nothing.
  def fin_accounting_entry_readonly_row(entry, attr, ctx, label = nil)
    detail = fin_format_attr(entry, attr, ctx)
    return nil if detail.hide || detail.blank_value?

    content = safe_join([detail.value, (wsjrdp_row_help(detail.help) if detail.help.present?)].compact)
    form_like_labeled(label || AccountingEntry.human_attribute_name(attr), content)
  end

  def fin_format_accounting_entry_direct_debit_pre_notification_id(entry)
    id = entry.direct_debit_pre_notification_id
    id && fin_accounting_entry_link("##{id}", wsjrdp_direct_debit_pre_notification_path(id))
  end

  def fin_format_accounting_entry_moss_booking_id(entry)
    id = entry.moss_booking_id
    id && fin_accounting_entry_link("##{id}", moss_booking_path(id))
  end

  # The payment order: the entry's own, or -- for a return -- its debit's.
  def fin_format_accounting_entry_payment_order(entry)
    id = payment_order_id_of_entry(entry)
    id && fin_accounting_entry_link("##{id}", payment_order_path(id))
  end

  # Addresses as mailto links, each with the icon that copies it -- right
  # after the address, held to it by a no-break space (U+00A0), so the
  # icon never wraps away from its address (.fin-copy-tight drops the margin
  # the detail gives a copy icon otherwise).
  def fin_mail_addresses(addresses)
    links = Array(addresses).compact_blank.map do |addr|
      copy = link_to(icon(:copy, filled: false), "#", class: "fin-copy fin-copy-tight text-muted",
        title: t("global.button.copy"), "aria-label": t("global.button.copy"),
        data: {copy_to_clipboard: addr})
      safe_join([mail_to(addr), "\u00A0", copy])
    end
    links.any? ? safe_join(links, ", ") : nil
  end

  # Fields of the edit page under the reading page's labels (`labels` maps the
  # attribute to its label, as _detail declares it): the input where the viewer
  # may change the field, else its value as the reading page shows it.
  def fin_accounting_entry_edit_fields(form, ctx, labels, **options)
    safe_join(labels.map do |attr, label|
      if permitted_attr?(attr)
        input_or_render_attrs(form, attr, label: label, **options)
      else
        form_like_labeled(label, fin_format_attr(form.object, attr, ctx).value)
      end
    end)
  end

  # The comment, only when there is one (the kit hides a blank value): escaped,
  # line breaks kept, URLs and mail addresses linked -- and, for a viewer who
  # holds :log on the entry, the FIN-/HELP- ticket keys as well, as the DATEV
  # booking's Notizen do (Fin::BookingsHelper#fin_format_datev_booking_user_comment).
  def fin_format_accounting_entry_comment(entry)
    text = entry.comment
    return nil if text.blank?
    return auto_link_escaped_multiline(text) if can?(:log, entry)

    auto_link(html_escape_multiline(text), sanitize: false, html: {target: "_blank"}).html_safe
  end

  # Said only when it holds: a booking outside the fee reconciliation.
  def fin_format_accounting_entry_excluded_from_fee_reconciliation(entry)
    entry.excluded_from_fee_reconciliation? ? "ja" : {hide: true}
  end

  private

  # A linked record: the link, the icon that opens it in a new tab, and an
  # optional muted summary.
  def fin_accounting_entry_link(label, url, summary = nil)
    parts = [link_to(label, url), wsjrdp_newtab_link(url)]
    parts << content_tag(:span, summary, class: "text-muted ms-2") if summary.present?
    safe_join(parts)
  end
end
