# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The model half of the Zahlungsverkehr details (doc/fin/payments.md): one
# formatter per field that shows more than its stored value, found by the name
# rule of Fin::AttrFormatHelper (fin_format_<model>_<attr>, doc/fin/
# detail_partials.md) -- the order (fin/payment_orders/_detail), the Sammler
# (fin/direct_debit_payment_infos/_detail), the debit (fin/direct_debits/
# _detail) and the return (fin/payment_returns/_detail). The labels live in
# de.activerecord.attributes.<model>; a field without a formatter takes the
# finance type rules (dates, *_cents as money). The records are the rows of
# Fin::PaymentQueries, so their figures (return_count, ...) are attributes.
module Fin::PaymentDetailsHelper
  # --- the order (WsjrdpPaymentInitiation) ------------------------------------

  def fin_format_wsjrdp_payment_initiation_kind(order) = payment_kind_cell(order.kind)

  def fin_format_wsjrdp_payment_initiation_fin_account(order) = payment_account_cell(order)

  def fin_format_wsjrdp_payment_initiation_status(order) = payment_status_with_raw(order.status)

  def fin_format_wsjrdp_payment_initiation_created_at(order) = payment_time(fin_date_time(order.created_at))

  def fin_format_wsjrdp_payment_initiation_message_identification(order) = payment_mono(order.message_identification)

  def fin_format_wsjrdp_payment_initiation_returns(order) = payment_returns_cell(order.return_count, order.return_sum_cents)

  def fin_format_wsjrdp_payment_initiation_bank(order) = payment_order_credit_cell(order)

  # --- the Sammler (WsjrdpDirectDebitPaymentInfo) ------------------------------

  def fin_format_wsjrdp_direct_debit_payment_info_payment_initiation(info)
    payment_order_link(info.payment_initiation_id)
  end

  def fin_format_wsjrdp_direct_debit_payment_info_payment_information_identification(info)
    payment_mono(info.payment_information_identification)
  end

  def fin_format_wsjrdp_direct_debit_payment_info_requested_collection_date(info)
    payment_time(fin_date(info.requested_collection_date))
  end

  def fin_format_wsjrdp_direct_debit_payment_info_creditor_id(info) = payment_mono(info.creditor_id)

  def fin_format_wsjrdp_direct_debit_payment_info_returns(info)
    payment_returns_cell(info.return_count, info.return_sum_cents)
  end

  def fin_format_wsjrdp_direct_debit_payment_info_bank(info) = payment_info_credit_cell(info)

  # --- the debit (WsjrdpDirectDebitPreNotification) ----------------------------

  def fin_format_wsjrdp_direct_debit_pre_notification_subject(debit) = payment_person(debit.subject)

  def fin_format_wsjrdp_direct_debit_pre_notification_payment_initiation(debit)
    payment_order_link(debit.payment_initiation_id)
  end

  # The Sammler the debit names, else the one its order, sequence type and
  # collection date pick (Fin::PaymentQueries.payment_info_debit_condition).
  def fin_format_wsjrdp_direct_debit_pre_notification_direct_debit_payment_info(debit)
    id = debit.direct_debit_payment_info_id || WsjrdpDirectDebitPaymentInfo.where(
      payment_initiation_id: debit.payment_initiation_id, debit_sequence_type: debit.debit_sequence_type,
      requested_collection_date: debit.collection_date
    ).pick(:id)
    id && link_to(t("fin.payments.payment_info_label", id: id), direct_debit_payment_info_path(id),
      data: {turbo_frame: "_top"})
  end

  def fin_format_wsjrdp_direct_debit_pre_notification_payment_role(debit) = payment_role_cell(debit.payment_role)

  # The collection date and the sequence type in one field ("05.03.2026 ·
  # RCUR"); the types are explained in the label's tooltip.
  def fin_format_wsjrdp_direct_debit_pre_notification_collection(debit)
    parts = [payment_time(fin_date(debit.collection_date)), debit.debit_sequence_type.presence].compact
    {value: parts.any? ? safe_join(parts, " · ") : nil, tooltip: t("fin.payments.sequence_types_hint")}
  end

  # The collection entry (Beitragsbuchung), by its label, and under it a
  # warning where it books another amount than the debit collects; "nicht
  # gesetzt" before one is linked.
  def fin_format_wsjrdp_direct_debit_pre_notification_accounting_entry(debit)
    entry = debit.entry_id && AccountingEntry.find_by(id: debit.entry_id)
    return {value: nil, blank: :unset} unless entry

    link = link_to(entry.link_name, accounting_entry_path(entry), data: {turbo_frame: "_top"})
    return link if entry.amount_cents == debit.amount_cents

    warning = content_tag(:div, safe_join([icon(:"exclamation-triangle"),
      t("fin.payments.entry_amount_differs", entry: payment_cents(entry.amount_cents),
        debit: payment_cents(debit.amount_cents))], " "), class: "payment-pre-notified-differs small")
    safe_join([link, warning])
  end

  def fin_format_wsjrdp_direct_debit_pre_notification_payment_status(debit)
    payment_status_with_raw(debit.payment_status)
  end

  # The amount, and beside it -- or below, where the line has no room -- the
  # announced one (Fin::PaymentsHelper#payment_pre_notified_note).
  def fin_format_wsjrdp_direct_debit_pre_notification_amount_cents(debit)
    amount = payment_cents(debit.amount_cents)
    return amount if debit.pre_notified_amount_cents.nil?

    content_tag(:span, safe_join([content_tag(:span, amount), payment_pre_notified_note(debit)]),
      class: "payment-amount-with-note")
  end

  def fin_format_wsjrdp_direct_debit_pre_notification_returns(debit) = payment_debit_return_cell(debit)

  def fin_format_wsjrdp_direct_debit_pre_notification_description(debit) = payment_mono(debit.description)

  def fin_format_wsjrdp_direct_debit_pre_notification_endtoend_id(debit) = payment_mono(debit.endtoend_id)

  def fin_format_wsjrdp_direct_debit_pre_notification_mandate_id(debit) = payment_mono(debit.mandate_id)

  # The mandate in one line: its reference and, muted, the date it was given.
  def fin_format_wsjrdp_direct_debit_pre_notification_mandate(debit)
    date = payment_time(fin_date(debit.mandate_date))
    parts = [payment_mono(debit.mandate_id),
      (safe_join([content_tag(:span, t("fin.payments.mandate_of"), class: "text-muted"), date], " ") if date)]
    parts.compact.any? ? safe_join(parts.compact, " ") : nil
  end

  # The short labels of the mandate fields on the debit's pages -- the
  # pre-notification's own page keeps its long ones.
  def payment_debit_mandate_labels
    {mandate_id: {label: t("fin.payments.labels.mandate_id")},
     mandate_date: {label: t("fin.payments.labels.mandate_date")},
     creditor_id: {label: t("fin.payments.labels.creditor_id")}}
  end

  # The help lines of the debit's page: the comment's on the reading and the
  # edit page, the skip's on the edit page only (`editing` true); none in a
  # list row (nil).
  def payment_debit_help(editing)
    return {} if editing.nil?

    help = {comment: {help: t("fin.payments.debit_help.comment")}}
    editing ? help.merge(try_skip: {help: t("fin.payments.debit_help.try_skip")}) : help
  end

  def fin_format_wsjrdp_direct_debit_pre_notification_creditor_id(debit) = payment_mono(debit.creditor_id)

  def fin_format_wsjrdp_direct_debit_pre_notification_mandate_date(debit) = payment_time(fin_date(debit.mandate_date))

  def fin_format_wsjrdp_direct_debit_pre_notification_created_at(debit) = payment_time(fin_date_time(debit.created_at))

  def fin_format_wsjrdp_direct_debit_pre_notification_updated_at(debit) = payment_time(fin_date_time(debit.updated_at))

  def fin_format_wsjrdp_direct_debit_pre_notification_email_to(debit) = payment_mail_list(debit.email_to)

  def fin_format_wsjrdp_direct_debit_pre_notification_email_cc(debit) = payment_mail_list(debit.email_cc)

  def fin_format_wsjrdp_direct_debit_pre_notification_email_bcc(debit) = payment_mail_list(debit.email_bcc)

  def fin_format_wsjrdp_direct_debit_pre_notification_email_reply_to(debit) = payment_mail_list(debit.email_reply_to)

  def fin_format_wsjrdp_direct_debit_pre_notification_email_from(debit) = payment_mail_list(debit.email_from)

  # The debit's other page (Fin::DebitPages): under its person seen from the
  # Zahlungsverkehr area -- none for a debit without one --, in the area seen
  # from under the person.
  def fin_format_wsjrdp_direct_debit_pre_notification_other_page(debit)
    if debit_page_place == :person
      link_to(t("fin.payments.debit_page_area"), direct_debit_path(debit), data: {turbo_frame: "_top"})
    elsif debit.subject_type == "Person" && debit.subject_id
      link_to(t("fin.payments.debit_page_person"), wsjrdp_direct_debit_pre_notification_path(debit),
        data: {turbo_frame: "_top"})
    end
  end

  # The field options of the debit's edit page for `attrs`: an input for each
  # that may change (`fields`, Fin::DebitEditing) -- the amount as the kit's
  # money input, under the label "Betrag" --, nothing for the others.
  def payment_debit_edit_options(fields, *attrs)
    attrs.each_with_object({}) do |attr, options|
      input = fields[attr]
      next unless input

      options[attr] = case input
      when :amount then {editable: true, label: t("fin.payments.amount")}
      when :select, :wide_select then {editable: true, input: input, options: payment_debit_select_options(attr)}
      else {editable: true, input: input}
      end
    end
  end

  # The choices of a select on the debit's edit page: the statuses, as
  # [label, value].
  def payment_debit_select_options(attr)
    raise ArgumentError, "no select options for #{attr}" unless attr == :payment_status

    Fin::DebitEditing.statuses.map { |value, label| [label, value] }
  end

  # --- the return (a WsjrdpCamtTransaction with a return reason) --------------

  def fin_format_wsjrdp_camt_transaction_subject(ret) = payment_person(ret.subject)

  def fin_format_wsjrdp_camt_transaction_return_date(ret) = payment_time(fin_date(ret.booking_date || ret.value_date))

  def fin_format_wsjrdp_camt_transaction_amount_cents(ret)
    content_tag(:span, payment_cents(ret.amount_cents), class: ("text-danger" if ret.amount_cents.to_i.negative?))
  end

  def fin_format_wsjrdp_camt_transaction_return_reason(ret) = payment_return_reasons(ret.return_reason, long: true)

  def fin_format_wsjrdp_camt_transaction_return_status(ret)
    badge = Fin::PaymentsHelper::RETURN_STATUS_BADGES[ret.return_status]
    badge ? content_tag(:span, ret.return_status_display, class: "badge fw-normal #{badge}") : ret.return_status_display
  end

  def fin_format_wsjrdp_camt_transaction_debit(ret)
    return payment_return_unassigned unless ret.notice_id

    payment_return_debit_link(ret, t("fin.payments.debit_label", id: ret.notice_id))
  end

  def fin_format_wsjrdp_camt_transaction_payment_info(ret)
    return {value: nil, blank: :hide} unless ret.info_id

    link_to(t("fin.payments.payment_info_label", id: ret.info_id), direct_debit_payment_info_path(ret.info_id),
      data: {turbo_frame: "_top"})
  end

  def fin_format_wsjrdp_camt_transaction_payment_order(ret) = payment_order_link(ret.order_id)

  def fin_format_wsjrdp_camt_transaction_endtoend_id(ret) = payment_mono(ret.endtoend_id)

  def fin_format_wsjrdp_camt_transaction_mandate_id(ret) = payment_mono(ret.mandate_id)

  def fin_format_wsjrdp_camt_transaction_description(ret) = payment_mono(ret.description)

  def fin_format_wsjrdp_camt_transaction_entry(ret)
    unless ret.return_entry_id
      return content_tag(:span, safe_join([icon(:"exclamation-triangle"), t("fin.payments.no_return_entry")], " "),
        class: "text-warning")
    end

    link_to(t("fin.payments.entry_link", id: ret.return_entry_id), accounting_entry_path(ret.return_entry_id),
      data: {turbo_frame: "_top"})
  end

  def fin_format_wsjrdp_camt_transaction_camt_transaction(ret)
    link_to(t("fin.payments.camt_link", id: ret.id), wsjrdp_camt_transaction_path(ret), data: {turbo_frame: "_top"})
  end

  # --- shared -----------------------------------------------------------------

  # A reference, purpose or id in a fixed-width font, so equal-looking
  # characters (0/O, l/1) and the parts of a reference read apart; nil for a
  # blank one (the field falls away).
  def payment_mono(value) = value.presence && content_tag(:span, value, class: "font-monospace")

  # A date or time with digits of one width (fin/payments/_styles), so dates
  # stacked in a detail line up.
  def payment_time(text) = text.presence && content_tag(:span, text, class: "payment-tabular")

  # A person as "YP 2052 Erika Mustermann": the contingent role and the id,
  # muted and light, in front of the name (linked where the viewer may open
  # the person, Fin::LinkedEntryHelper#fin_subject_link).
  def payment_person(subject)
    return fin_subject_link(subject) unless subject.is_a?(::Person)

    prefix = content_tag(:span, "#{subject.short_payment_role} #{subject.id}", class: "text-muted fw-light")
    safe_join([prefix, fin_subject_link(subject)], " ")
  end

  # A status in words; for the finance tier and up -- who write
  # pre-notifications and work with the stored values -- the stored value
  # behind it, muted and light ("XML erzeugt xml_generated").
  def payment_status_with_raw(status)
    label = payment_status_label(status)
    return label if status.blank? || !can?(:update, WsjrdpDirectDebitPreNotification)

    safe_join([label, content_tag(:span, status, class: "text-muted fw-light ms-2")])
  end

  # The addresses of a mail field -- an array column (email_to, email_cc,
  # ...) or a text one (email_from), an entry possibly "a@x.de, Name
  # <b@y.de>" -- as a comma-separated list, each a mailto link to its
  # address.
  def payment_mail_list(addresses)
    list = Array.wrap(addresses).flat_map { |entry| entry.to_s.split(/[,;]/) }.map(&:strip).compact_blank
    return nil if list.empty?

    safe_join(list.map { |entry| mail_to(entry[/<([^>]+)>/, 1] || entry, entry) }, ", ")
  end
end
