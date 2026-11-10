# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Helpers for CAMT bank transactions.
#
# A detail sits inside a turbo frame, on its own page and in a table
# row alike, so every link here leaves it (`_top`).
module Fin::CamtTransactionsHelper
  # The fields the detail lets change
  # (Fin::WsjrdpCamtTransactionsController#permitted_attrs), each with its
  # input; none where it carries no form.
  def fin_camt_transaction_edit_options(editable)
    return {} unless editable

    {
      comment: {editable: true, input: :textarea},
      subject: {editable: true, input: :helper, options: :fin_camt_transaction_subject_input},
      return_status: {editable: true, input: :wide_select, options: Fin::ReturnEditing.status_options}
    }
  end

  # The person search of hitobito's own forms (StandardFormBuilder#person_field:
  # the name with its suggestions, the chosen person's id in a hidden field) and
  # under it the person the transaction has now. The ids carry the transaction's
  # id: the search finds its fields by id, and a table shows several details on
  # one page. After a failed save the field keeps the name that was typed, and
  # the person below it stays the stored one.
  def fin_camt_transaction_subject_input(f, _row)
    tx = f.object
    id = "camt_transaction_#{tx.id}_subject"
    typed = params.dig(f.object_name, :subject)
    field = f.hidden_field(:subject_id, id: "#{id}_id") +
      f.text_field(:subject, id: id, value: typed || tx.subject&.to_s, class: "form-control form-control-sm",
        placeholder: t("global.search.placeholder_person"),
        data: {provide: "entity", id_field: "#{id}_id", no_results_message: t("global.no_list_entries"),
               url: query_people_path})
    current = tx.subject_id_changed? ? Person.find_by(id: tx.subject_id_in_database) : tx.subject
    return field if current.blank?

    link = link_to_if(assoc_link?(current), current.to_s, current, data: {turbo_frame: "_top"})
    safe_join([field, wsjrdp_row_help(safe_join(["Bisheriger Wert: ", link]))])
  end

  # The account with its statement, for whoever may open it.
  def fin_format_wsjrdp_camt_transaction_fin_account(tx)
    account = tx.fin_account
    return nil if account.nil?

    link_to_if(assoc_link?(account), account.to_s, wsjrdp_fin_account_path(account), data: {turbo_frame: "_top"})
  end

  # Signed, the way the account's statement shows it.
  def fin_format_wsjrdp_camt_transaction_amount_eur(tx) = tx.amount_eur_display

  # The Beitragsbuchungen booked for the transaction, each with its person.
  # Both halves are links only for whoever may see the entry's person -- see
  # Fin::LinkedEntryHelper for the rule.
  def fin_format_wsjrdp_camt_transaction_accounting_entries(tx)
    entries = tx.accounting_entries
    lines = entries.map do |entry|
      content_tag(:div, safe_join([fin_entry_link(entry), content_tag(:span, " • ", class: "muted"),
        content_tag(:span, "Person: ", class: "fw-light muted"), fin_subject_link(entry.subject)]))
    end
    {label: (entries.size == 1) ? "Buchung" : "Buchungen", value: safe_join(lines)}
  end

  # The kind of return with its page in the Zahlungsverkehr area, and below it
  # what the kind means.
  def fin_format_wsjrdp_camt_transaction_return_kind_link(tx)
    return nil if tx.return_kind.blank?

    link = link_to(t("fin.payments.return_label", id: tx.id), payment_return_path(tx), class: "small",
      data: {turbo_frame: "_top"})
    hint = content_tag(:div, t("fin.payments.return_kind_hints.#{tx.return_kind}"), class: "small text-muted")
    {label: WsjrdpCamtTransaction.human_attribute_name(:return_kind),
     value: safe_join([t("fin.payments.return_kinds.#{tx.return_kind}"), " ", link, hint])}
  end

  # The return that brought this transaction back (Fin::ReturnOriginals);
  # nothing without one.
  def fin_format_wsjrdp_camt_transaction_reversed_by(tx)
    came_back = tx.reversed_by
    return nil if came_back&.return_kind.blank?

    text = [t("fin.payments.return_label", id: came_back.id), t("fin.payments.return_kinds.#{came_back.return_kind}"),
      fin_date(came_back.booking_date || came_back.value_date)].join(" · ")
    {label: t("fin.payments.came_back"),
     value: link_to(text, payment_return_path(came_back), data: {turbo_frame: "_top"})}
  end

  # The bank details of both parties, each with the icon that copies it
  # (Fin::FinAccountsHelper#fin_account_copyable).
  def fin_format_wsjrdp_camt_transaction_cdtr_iban(tx) = fin_account_copyable(tx.cdtr_iban, tx.cdtr_iban)

  def fin_format_wsjrdp_camt_transaction_cdtr_bic(tx) = fin_account_copyable(tx.cdtr_bic, tx.cdtr_bic)

  def fin_format_wsjrdp_camt_transaction_dbtr_iban(tx) = fin_account_copyable(tx.dbtr_iban, tx.dbtr_iban)

  def fin_format_wsjrdp_camt_transaction_dbtr_bic(tx) = fin_account_copyable(tx.dbtr_bic, tx.dbtr_bic)
end
