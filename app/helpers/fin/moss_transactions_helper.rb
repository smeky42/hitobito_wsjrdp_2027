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
  # The description column shows at most this many characters; the full text
  # is in the row's detail.
  DESCRIPTION_LENGTH = 100

  def moss_transaction_table_columns
    Fin::MossTransactionsColumns::COLUMNS.map do |col|
      col.to_table_column(cell: ->(tx) { moss_transaction_cell(tx, col.key) })
    end
  end

  def moss_transaction_cell(tx, key)
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
      tx.description(length: DESCRIPTION_LENGTH)
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

  # German label of a kind (STI type), e.g. "Kartenzahlung".
  def moss_kind_label(type)
    I18n.t("fin.moss.kinds.#{type}", default: type.to_s)
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

  # --- the HTML labels of the kind tabs (Sheet::Fin::Moss) --------------------
  #
  # A sheet tab may declare its label as a SYMBOL instead of an i18n key; the
  # core then calls the helper method of that name with the sheet entry as its
  # only argument and hands the result to link_to (Sheet::Tab::Renderer#label),
  # so an html_safe return value renders as HTML. That is the whole trick by
  # which the four kind tabs carry their icon without patching the core -- see
  # doc/navigation.md §5.
  #
  # One method per kind tab, GENERATED just below (spelled out here so that a
  # grep for the symbol in Sheet::Fin::Moss lands in this file):
  #
  #     moss_card_transactions_tab_label   moss_invoices_tab_label
  #     moss_reimbursements_tab_label      moss_top_ups_tab_label
  #
  # The names follow the tab slugs of Fin::MossTransactionsController::KIND_TABS
  # -- and thus each tab's own path helper (moss_invoices_tab_label next to
  # moss_invoices_path in the sheet). They are derived from the kind's
  # expense_type slug instead of being read out of KIND_TABS, because reading
  # that constant while THIS module is loaded would be circular: including the
  # helper is what a controller does on `class … < Fin::FinController`, i.e.
  # before its body defines KIND_TABS. Only the method NAME is derived; the
  # WORDS still come from KIND_TABS at call time via moss_kind_tab_label, so a
  # tab and its label can never drift apart (a drifting slug would be a loud
  # NoMethodError on the tab, not a silently wrong word).
  Fin::MossKinds::STYLE.each_key do |kind|
    define_method(:"moss_#{Fin::MossKinds.slug(kind).pluralize}_tab_label") do |_entry = nil|
      moss_kind_tab_label_with_icon(kind)
    end
  end

  # The kind's icon in front of its tab label ("Rechnungen"), as one html_safe
  # string. The icon is deliberately NOT tinted and carries no kind class: the
  # tabs are rendered on pages that do not know the kind stylesheet (/fin among
  # them, whose quick links reuse these very labels), and a bare <i> needs none.
  def moss_kind_tab_label_with_icon(kind)
    safe_join([moss_kind_icon(kind), " ", moss_kind_tab_label(kind)])
  end
end
