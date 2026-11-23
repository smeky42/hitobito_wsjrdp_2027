# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Per-cell formatting for the Moss transactions listing (all four kinds) and the
# rendering of the column descriptions (Fin::MossTransactionsColumns) as the
# shared shared/wsjrdp/_expandable_table column configs (see
# fin/moss_transactions/index). Aggregate columns (Buchungen, Sachkonten,
# Kostenstellen, DATEV) read the eager-loaded expenses + bookings, so the rows
# object MUST preload them; account / cost-center NAMES come from a per-request
# lookup map.
module Fin::MossTransactionsHelper
  # The description column shows as many lines as the list view's CSS allows
  # (.moss-desc), so a wide column shows more of it; the full text is in the
  # row's detail. This cap only keeps the page small.
  DESCRIPTION_LENGTH = 600

  # Hidden booking date and kind columns move into the description as chips,
  # their sorts into its header (Fin::RowChipsHelper).
  def moss_transaction_table_columns(state)
    kind_chip = state.column_hidden?("kind")
    dates = fin_date_chip_modes(state, booking_label: "Buchungsdatum", value: nil)
    hidden = fin_hidden_date_keys(state, %w[booking_date]) + (kind_chip ? ["kind"] : [])
    Fin::MossTransactionsColumns::COLUMNS.map do |col|
      subs = (et_sub_sorts(Fin::MossTransactionsColumns::COLUMNS, hidden) if col.key == "description")
      col.to_table_column(cell: ->(tx) { moss_transaction_cell(tx, col.key, kind_chip: kind_chip, dates: dates) },
        sub_sorts: subs)
    end
  end

  def moss_transaction_cell(tx, key, kind_chip: false, dates: nil)
    case key
    # Zahlungsdatum is the one date cell that writes the em dash itself: two of
    # the four kinds carry no payout day at all, so a blank cell would read as a
    # rendering fault rather than as "there is none".
    when "payment_date"
      fin_date_or_dash(tx.payment_date)
    when "booking_date", "approval_date"
      fin_date(tx.public_send(key))
    when "kind"
      moss_kind_chip(tx.type)
    when "signed_total_base_amount"
      moss_transaction_amount_cell(tx)
    when "description"
      chips = (dates ? fin_date_chips(dates, booking_date: tx.booking_date) : []) << (moss_kind_chip(tx.type) if kind_chip)
      moss_transaction_description_cell(tx, chips: fin_row_chips(chips))
    when "party"
      moss_transaction_party(tx)
    when "cost_centers"
      moss_code_name_cell(moss_transaction_bookings(tx).map(&:cost_center_number), moss_cost_center_names)
    when "account_numbers"
      moss_code_name_cell(moss_transaction_bookings(tx).map(&:account_number), moss_account_names)
    when "supplier_account_number"
      moss_code_name_cell([tx.supplier_account_number], moss_account_names)
    when "bookings_count"
      moss_transaction_bookings(tx).size
    when "datev"
      moss_datev_links_cell(tx)
    else
      tx.public_send(key)
    end
  end

  # The description cell: the text, then `party_line` (the other side, where a
  # table shows it there), then the person side of every booking, then `chips`
  # (fin_row_chips: what hidden columns would show).
  def moss_transaction_description_cell(tx, party_line: nil, chips: nil)
    text = tx.description(length: DESCRIPTION_LENGTH)
    safe_join([(content_tag(:span, text, class: "moss-desc") if text.present?), party_line,
      moss_transaction_subject_links(tx), chips].compact)
  end

  # German label of a kind (STI type), e.g. "Kartenzahlung".
  def moss_kind_label(type)
    I18n.t("fin.moss.kinds.#{type}", default: type.to_s)
  end

  # The person side of the description cell: one linking block
  # (fin/moss_bookings/_subject_links) per booking that has something to show --
  # a linked person or contribution booking, or a person to offer. With several
  # bookings each block gets its booking's text as a label, OUTSIDE the block:
  # the link actions replace the block itself, the label stays.
  def moss_transaction_subject_links(tx)
    bookings = moss_transaction_bookings(tx)
    shown = bookings.filter_map do |booking|
      candidates = subject_link_candidates(booking)
      [booking, candidates] if moss_booking_subject_links?(booking, candidates)
    end
    return if shown.empty?

    safe_join(shown.map do |booking, candidates|
      label = (moss_transaction_booking_label(booking).presence if bookings.size > 1)
      content_tag(:div, class: "moss-subject-links mt-1") do
        safe_join([(content_tag(:div, label, class: "small text-muted") if label),
          render("fin/moss_bookings/subject_links", booking: booking, candidates: candidates)].compact)
      end
    end)
  end

  # A booking among several of one transaction, by its own text (else its
  # expense's), shortened.
  def moss_transaction_booking_label(booking)
    text = booking.booking_posting_text.presence || booking.moss_expense&.expense_posting_text
    truncate(text.to_s, length: 60, separator: " ")
  end

  # Every booking of a transaction through the eager-loaded expenses (one
  # preload chain for the aggregates AND the detail).
  def moss_transaction_bookings(tx)
    tx.expenses.flat_map(&:bookings)
  end

  # Betrag: the transaction total in the base currency (EUR); for a payment
  # made in another currency, the original amount goes on a second, muted line
  # (like the bookings table).
  def moss_transaction_amount_cell(tx)
    primary = moss_amount_display(tx.signed_total_base_amount, tx.currency.presence || "EUR")
    return primary unless tx.foreign_currency?

    foreign = moss_amount_display(tx.signed_total_transaction_amount, tx.currency_original)
    return primary if foreign.blank?
    safe_join([primary, content_tag(:div, foreign, class: "text-muted small")])
  end

  # Who is on the other side, per kind: the card holder, the payee of an
  # invoice / reimbursement (falling back to who paid it out), the sender of a
  # top-up.
  def moss_transaction_party(tx)
    case tx
    when MossCardTransaction then tx.card_holder_name
    when MossTopUp then tx.top_up_sender
    else tx.recipient_name.presence || tx.payout_user_name
    end
  end

  # Label of the party column / detail row, per kind.
  def moss_transaction_party_label(tx)
    case tx
    when MossCardTransaction then "Karteninhaber"
    when MossTopUp then "Absender"
    else "Empfänger"
    end
  end

  # Label of the display_name, per kind (the detail's name row).
  def moss_transaction_name_label(tx)
    case tx
    when MossCardTransaction then "Händler"
    when MossInvoice then "Belegnummer"
    when MossReimbursement then "Name (Moss)"
    else "Name"
    end
  end

  # Distinct codes, each followed by its name in muted font (name omitted if
  # unknown), one per line.
  def moss_code_name_cell(codes, names)
    entries = codes.compact_blank.uniq.sort.map do |code|
      name = names[code]
      name.blank? ? code : safe_join([code, content_tag(:span, name, class: "text-muted")], " ")
    end
    safe_join(entries, tag.br)
  end

  # number => name, loaded once per request. Ledger accounts and suppliers use
  # disjoint number ranges (700xxx creditors only in wsjrdp_personal_accounts),
  # so the two name sources simply union -- same approach as the bookings page.
  def moss_account_names
    @moss_account_names ||= WsjrdpLedgerAccount.pluck(:number, :name).to_h
      .merge(WsjrdpPersonalAccount.pluck(:number, :name).to_h)
  end

  def moss_cost_center_names
    @moss_cost_center_names ||= WsjrdpCostCenter.pluck(:number, :name).to_h
  end

  # DATEV link state of a transaction: the clearing leg (36100 -> creditor, on
  # the transaction) and the expense legs (one per booking).
  def moss_datev_links_cell(tx)
    bookings = moss_transaction_bookings(tx)
    linked = bookings.count(&:expense_datev_booking_id)
    clearing = tx.clearing_datev_booking_id.present?
    clearing_tag = content_tag(:span, safe_join([icon(clearing ? :check : :minus), " Ausgleich"]),
      class: clearing ? "text-success" : "text-muted",
      title: clearing ? "Ausgleichsbuchung verknüpft" : "Keine Ausgleichsbuchung verknüpft")
    expense_tag = content_tag(:span, "Aufwand #{linked}/#{bookings.size}",
      class: (bookings.any? && linked == bookings.size) ? "text-success" : "text-muted",
      title: "Buchungen mit verknüpfter Aufwandsbuchung")
    safe_join([clearing_tag, expense_tag], tag.br)
  end

  # A signed Moss amount in the money format of the Finanzen lists
  # (Fin::MoneyHelper): number and currency symbol, or the bare number where
  # no currency is passed. A foreign currency is possible here.
  def moss_amount_display(value, currency = nil) = fin_money(value, currency)

  # --- the kind's visual vocabulary -------------------------------------------
  #
  # Icon + colour class per kind come from Fin::MossKinds, the words from the
  # locale (fin.moss.kind_chips / .kind_hints) -- nothing German and no icon
  # name is written down here. Rendered by the Moss wallet list, the booking
  # detail header, the /fin/moss tiles and the wallet's filter presets; every
  # view that shows one MUST also render "shared/wsjrdp/moss_kind_styles",
  # which holds the colours.

  # The chip: the kind's icon and its short word in a small coloured pill, with
  # the kind's one-sentence explanation as the tooltip. Icon and word ALWAYS
  # together -- colour is never the only cue (WCAG 1.4.1), and an icon alone
  # would be a riddle in a monochrome print-out just as much as for a reader
  # who cannot distinguish the four hues.
  def moss_kind_chip(type)
    content_tag(:span, class: "moss-kind #{moss_kind_css_class(type)}", title: moss_kind_hint(type)) do
      safe_join([moss_kind_icon(type), moss_kind_chip_label(type)], " ")
    end
  end

  # The chip's short word ("Karte"), as opposed to the longer word the tabs and
  # tiles use (moss_kind_label -> "Kartenzahlung"); falls back to that one.
  def moss_kind_chip_label(type)
    I18n.t("fin.moss.kind_chips.#{type}", default: moss_kind_label(type))
  end

  # The kind's one-sentence explanation (the chip's title). Blank rather than a
  # "translation missing" text in a tooltip, so a missing sentence simply omits
  # the attribute.
  def moss_kind_hint(type)
    I18n.t("fin.moss.kind_hints.#{type}", default: "").presence
  end

  # Just the <i> element, for the places that already carry a label of their
  # own: the overview tiles, the kind tabs and the filter presets.
  def moss_kind_icon(type)
    content_tag(:i, "", class: "fas fa-#{Fin::MossKinds.icon(type)}", "aria-hidden": "true")
  end

  # The kind's colour class ("moss-kind-card_transaction"), also put on the
  # wallet's <tr> for the coloured rail and on a tile / preset link.
  def moss_kind_css_class(type)
    Fin::MossKinds.css_class(type)
  end

  # --- the kind tabs (Fin::MossTransactionsController::KIND_TABS) --------------

  # Path of a kind's own tab, e.g. moss_invoices_path for "MossInvoice".
  def moss_kind_tab_path(kind)
    public_send(:"moss_#{Fin::MossTransactionsController::KIND_TABS.fetch(kind)}_path")
  end

  # Label of a kind's tab ("Rechnungen"): the plural of moss_kind_label.
  def moss_kind_tab_label(kind)
    I18n.t("fin.tabs.#{Fin::MossTransactionsController::KIND_TABS.fetch(kind)}")
  end

  # The listing's title: the kind tab's label, or "Transaktionen" on the
  # general tab (current_kind is the controller's helper_method).
  def moss_transactions_title
    current_kind ? moss_kind_tab_label(current_kind) : I18n.t("fin.tabs.transactions")
  end

  # The PRG target of the listing's filter builder: the current tab's own
  # apply route, so the redirect lands on the same tab.
  def moss_transactions_apply_path
    return apply_moss_transactions_path unless current_kind

    public_send(:"apply_moss_#{Fin::MossTransactionsController::KIND_TABS.fetch(current_kind)}_path")
  end

  # --- the kind tabs' labels (Sheet::Fin::Moss#render_kind_tabs) ------------

  # The kind's icon in front of its tab label ("Rechnungen"), as one html_safe
  # string. The icon is deliberately NOT tinted and carries no kind class: a
  # bare <i> needs no kind stylesheet.
  def moss_kind_tab_label_with_icon(kind)
    safe_join([moss_kind_icon(kind), " ", moss_kind_tab_label(kind)])
  end

  # --- shared by the Moss details (transaction, expense, booking) -------------

  # A link that leaves the turbo frame a detail stands in (`_top`), followed by
  # its new-tab twin.
  def moss_double_link(label, url)
    safe_join([link_to(label, url, data: {turbo_frame: "_top"}), wsjrdp_newtab_link(url)])
  end

  def moss_fin_account_link(account) = account && moss_double_link(account.to_s, wsjrdp_fin_account_path(account))

  # Comments of the levels above, one line each: the level muted, then the
  # comment ([[level name, text], ...]).
  def moss_level_comment_lines(comments)
    safe_join(comments.map do |level, text|
      content_tag(:div, safe_join([content_tag(:span, "#{level}: ", class: "fw-light muted"),
        content_tag(:span, auto_link_escaped_multiline(text), class: "fw-light fst-italic")]))
    end)
  end

  # --- the transaction's detail (fin/moss_transactions/_detail) -------------
  #
  # The formatters of the finance detail kit (doc/fin/detail_partials.md), one
  # per field the detail lists.

  def fin_format_moss_transaction_type(tx) = moss_kind_chip(tx.type)

  # The Moss workflow states: the transaction's and, for an invoice, the
  # invoice's.
  def fin_format_moss_transaction_moss_status(tx)
    [tx.moss_transaction_state, tx.invoice_status].compact_blank.join(" · ")
  end

  def fin_format_moss_transaction_signed_total_base_amount(tx)
    moss_amount_display(tx.signed_total_base_amount, tx.currency.presence || "EUR")
  end

  # The amount in the payment's own currency, only on a foreign-currency one.
  def fin_format_moss_transaction_original_amount(tx)
    moss_amount_display(tx.signed_total_transaction_amount, tx.currency_original) if tx.foreign_currency?
  end

  def fin_format_moss_transaction_exchange_rate(tx)
    return nil unless tx.foreign_currency? && tx.exchange_rate

    number_with_precision(tx.exchange_rate, precision: 6, strip_insignificant_zeros: true, separator: ",", delimiter: ".")
  end

  # Name and party: the label says what the value is for the kind.
  def fin_format_moss_transaction_display_name(tx) = {label: moss_transaction_name_label(tx), value: tx.display_name}

  def fin_format_moss_transaction_display_text(tx) = tx.display_text

  def fin_format_moss_transaction_party(tx) = {label: moss_transaction_party_label(tx), value: moss_transaction_party(tx)}

  def fin_format_moss_transaction_supplier_account_number(tx)
    moss_code_name_cell([tx.supplier_account_number], moss_account_names)
  end

  # The payment's record in Moss -- none for a top-up (MossTopUp#moss_record_url).
  def fin_format_moss_transaction_moss_record(tx)
    url = tx.moss_record_url
    url && moss_double_link("In Moss öffnen", url)
  end

  def fin_format_moss_transaction_clearing_datev_booking(tx)
    id = tx.clearing_datev_booking_id
    id && link_to("Buchung ##{id}", booking_path(id), data: {turbo_frame: "_top"})
  end

  def fin_format_moss_transaction_fin_account(tx) = moss_fin_account_link(tx.fin_account)

  def fin_format_moss_transaction_comment(tx)
    auto_link_escaped_multiline(tx.comment) if tx.comment.present?
  end

  # What the edit page of a transaction or an expense lets a writer change:
  # the comment.
  def moss_comment_edit_options(editable)
    editable ? {comment: {editable: true, input: :textarea}} : {}
  end
end
