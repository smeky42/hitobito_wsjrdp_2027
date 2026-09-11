# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Per-cell formatting for the Moss WALLET statement (fin/wsjrdp_fin_accounts's
# _moss_wallet partial) and the rendering of Fin::MossWalletColumns as the
# shared widget's column configs.
#
# A row is a MossBooking; nearly everything it shows comes from its payment
# (Fin::MossKinds / Fin::MossTransactionsHelper supply the kind's chip, icon and
# colour). Every method here takes a booking or a transaction and returns a
# String / an Array / safe HTML -- no instance state, so each one can be called
# on its own with a row built in a spec.
#
# What this helper does NOT render is the part of the description cell that
# links a booking to a person's Beitragsbuchung (the comments, the linked
# entries, the "Verknüpfe mit ..." buttons). That block is unchanged markup and
# stays HAML, in fin/wsjrdp_fin_accounts/_wallet_description, where it can be
# read next to the camt statement's copy of it.
module Fin::MossWalletHelper
  # The Moss invoice status that needs no tag: everything else is worth showing.
  INVOICE_STATUS_NORMAL = "Completed"
  # Likewise for the Moss transaction state.
  TRANSACTION_STATE_NORMAL = "ACCEPTED"
  # The base currency; a payment in it needs no currency tag.
  BASE_CURRENCY = "EUR"

  # The wallet table's column configs: the description
  # (Fin::MossWalletColumns) plus this helper's cells.
  def moss_wallet_table_columns
    Fin::MossWalletColumns::COLUMNS.map do |col|
      col.to_table_column(cell: ->(booking) { moss_wallet_cell(booking, col.key) })
    end
  end

  def moss_wallet_cell(booking, key)
    case key
    when "booking_date" then fin_date(booking.moss_transaction.booking_date)
    when "kind" then moss_kind_chip(booking.moss_transaction.type)
    when "signed_base_amount" then moss_wallet_amount_cell(booking)
    when "description" then render("fin/wsjrdp_fin_accounts/wallet_description", booking: booking)
    end
  end

  # Betrag: the split's signed EUR share. Money coming IN (a top-up, the rare
  # card credit note) gets a "+" and the green of an incoming amount -- the sign
  # is the cue, the colour only reinforces it. A negative amount keeps its own
  # "-" and the default colour.
  def moss_wallet_amount_cell(booking)
    display = fin_money(booking.signed_base_amount, BASE_CURRENCY)
    return display unless booking.signed_base_amount&.positive?

    content_tag(:span, "+#{display}", class: "moss-amount-in")
  end

  # Line 1 of the description: the payment's name in medium weight, then the
  # kind's party after a "·", then the status tags.
  def moss_wallet_headline(booking)
    transaction = booking.moss_transaction
    name = content_tag(:span, transaction.display_name, class: "mw-name")
    party = moss_wallet_party(transaction)
    safe_join([safe_join([name, party].compact_blank, " · "), moss_wallet_tag_marks(booking)])
  end

  # WHO is on the other side of the payment, per kind: the card holder and their
  # team, the supplier of an invoice, the person a reimbursement was paid to,
  # the sender of a top-up. Blank parts are omitted, and a kind without a party
  # yields nil (the headline then shows the name alone).
  def moss_wallet_party(transaction)
    case transaction
    when MossCardTransaction
      [transaction.card_holder_name, transaction.card_holder_team_name].compact_blank.join(" · ")
    when MossInvoice then moss_wallet_supplier(transaction)
    when MossReimbursement then transaction.recipient_name
    when MossTopUp then transaction.top_up_sender
    end.presence
  end

  # The supplier of an invoice: the creditor's name from the standing data plus
  # its account number ("Name · Kreditor 700027"). Without a standing-data row
  # the number alone still says who was paid. The name comes from the page's
  # one account-name map (Fin::MossTransactionsHelper#moss_account_names), not
  # from the polymorphic supplier_account association: that would be one query
  # per invoice row, and preloading it for every kind would load standing data
  # the other kinds never read.
  def moss_wallet_supplier(transaction)
    number = transaction.supplier_account_number
    creditor = "Kreditor #{number}" if number.present?
    [moss_account_names[number], creditor].compact_blank.join(" · ")
  end

  # The row's status tags as plain STRINGS, in display order -- what the row
  # needs to say beyond its kind:
  #   * a payment made in a foreign currency: its original amount and the rate;
  #   * "Gutschrift": a card row whose money came back;
  #   * an invoice status other than "Completed", a Moss state other than
  #     "ACCEPTED" -- raw, because they are Moss's words and any mapping would
  #     have to be guessed. With today's data neither ever renders; they exist
  #     so a future export cannot slip an unusual row past unmarked.
  def moss_wallet_tags(booking)
    transaction = booking.moss_transaction
    [moss_wallet_currency_tag(transaction),
      moss_wallet_credit_note_tag(booking),
      moss_wallet_invoice_status_tag(transaction),
      moss_wallet_transaction_state_tag(transaction)].compact_blank
  end

  # #moss_wallet_tags rendered: one bordered %span.moss-tag each, nothing when
  # the row has no tag.
  def moss_wallet_tag_marks(booking)
    safe_join(moss_wallet_tags(booking).map { |text| content_tag(:span, text, class: "moss-tag") })
  end

  # "1.234,00 PLN · Kurs 4,2500" -- the amount Moss actually moved, in the
  # currency it was moved in, and the rate the EUR figure was derived with. The
  # rate part is omitted when the export carried none.
  def moss_wallet_currency_tag(transaction)
    currency = transaction.currency_original
    return nil if currency.blank? || currency == BASE_CURRENCY

    amount = [moss_wallet_number(transaction.signed_total_transaction_amount, 2), currency]
      .compact_blank.join(" ")
    rate = moss_wallet_number(transaction.exchange_rate, 4)
    rate.present? ? "#{amount} · Kurs #{rate}" : amount.presence
  end

  # Money that came back on a card: a card payment is an outflow, so a positive
  # split is a refund and worth naming.
  def moss_wallet_credit_note_tag(booking)
    return nil unless booking.moss_transaction.is_a?(MossCardTransaction)

    "Gutschrift" if booking.signed_base_amount&.positive?
  end

  def moss_wallet_invoice_status_tag(transaction)
    return nil unless transaction.is_a?(MossInvoice)

    status = transaction.invoice_status
    status if status.present? && status != INVOICE_STATUS_NORMAL
  end

  def moss_wallet_transaction_state_tag(transaction)
    state = transaction.moss_transaction_state
    state if state.present? && state != TRANSACTION_STATE_NORMAL
  end

  # Line 2 and below of the description: the Buchungstext of the row's three
  # levels. A top-up has none worth showing -- what it says is where the money
  # came from, which is the fixed account chain (Geldtransit -> Moss).
  def moss_wallet_text_lines(booking)
    if booking.moss_transaction.is_a?(MossTopUp)
      return content_tag(:div, t("fin.moss.top_up_line"))
    end

    lines = booking.text_lines
      .filter_map { |level, name, text| moss_wallet_text_line(level, name, text) }
    safe_join(lines.map { |line| content_tag(:div, line) })
  end

  # ONE line of MossBooking#text_lines, wallet-style: the TRANSACTION level
  # shows its text only, in italics and without the "Transaktion:" prefix --
  # its name is already line 1, so the prefix would repeat a label in every
  # single row. The expense and booking levels keep the shared rendering
  # (moss_text_line), which the booking detail page relies on: that page shows
  # the same lines WITHOUT a line 1 and needs every prefix, so moss_text_line
  # itself stays untouched.
  def moss_wallet_text_line(level, name, text)
    return moss_text_line(level, name, text) unless level == :transaction
    return nil if text.blank?

    content_tag(:span, auto_link_escaped_multiline(text), class: "fst-italic")
  end

  # German-style number with a fixed number of decimals, nil for nil (so a
  # missing rate simply drops out of its tag).
  def moss_wallet_number(value, precision)
    return nil if value.nil?

    number_with_precision(value, precision: precision, delimiter: ".", separator: ",")
  end
end
