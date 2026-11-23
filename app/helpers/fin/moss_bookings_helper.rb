# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Per-cell formatting for the Moss bookings list (fin/moss_bookings/index)
# and the rendering of Fin::MossBookingsColumns as the
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
# stays HAML, in fin/moss_bookings/_description, where it can be
# read next to the camt statement's copy of it.
module Fin::MossBookingsHelper
  # The Moss invoice status that needs no tag: everything else is worth showing.
  INVOICE_STATUS_NORMAL = "Completed"
  # Likewise for the Moss transaction state.
  TRANSACTION_STATE_NORMAL = "ACCEPTED"
  # The base currency; a payment in it needs no currency tag.
  BASE_CURRENCY = "EUR"

  # The bookings table's column configs: the description
  # (Fin::MossBookingsColumns) plus this helper's cells.
  def moss_bookings_table_columns
    Fin::MossBookingsColumns::COLUMNS.map do |col|
      col.to_table_column(cell: ->(booking) { moss_bookings_cell(booking, col.key) })
    end
  end

  def moss_bookings_cell(booking, key)
    case key
    when "booking_date" then fin_date(booking.moss_transaction.booking_date)
    when "kind" then moss_kind_chip(booking.moss_transaction.type)
    when "signed_base_amount" then moss_bookings_amount_cell(booking)
    when "description" then render("fin/moss_bookings/description", booking: booking)
    when "cost_center_number"
      moss_code_name_cell([booking.cost_center_number], moss_cost_center_names)
    when "account_number" then moss_code_name_cell([booking.account_number], moss_account_names)
    when "supplier_account_number"
      moss_code_name_cell([booking.moss_transaction.supplier_account_number], moss_account_names)
    when "party" then moss_transaction_party(booking.moss_transaction)
    when "payment_date" then fin_date_or_dash(booking.moss_transaction.payment_date)
    when "datev" then moss_bookings_datev_cell(booking)
    when "sphere_number" then booking.sphere_number
    else booking.moss_transaction.public_send(key)
    end
  end

  # DATEV: is the booking's expense leg linked to its DATEV booking?
  def moss_bookings_datev_cell(booking)
    linked = booking.expense_datev_booking_id.present?
    content_tag(:span, safe_join([icon(linked ? :check : :minus), linked ? " verknüpft" : " offen"]),
      class: linked ? "text-success" : "text-muted",
      title: linked ? "Aufwandsbuchung verknüpft" : "Keine Aufwandsbuchung verknüpft")
  end

  # Betrag: the split's signed EUR share. Money coming IN (a top-up, the rare
  # card credit note) gets a "+" and the green of an incoming amount -- the sign
  # is the cue, the colour only reinforces it. A negative amount keeps its own
  # "-" and the default colour.
  def moss_bookings_amount_cell(booking)
    display = fin_money(booking.signed_base_amount, BASE_CURRENCY)
    return display unless booking.signed_base_amount&.positive?

    content_tag(:span, "+#{display}", class: "moss-amount-in")
  end

  # Line 1 of the description: the payment's name in medium weight, then the
  # kind's party after a "·", then the status tags.
  def moss_bookings_headline(booking)
    transaction = booking.moss_transaction
    name = content_tag(:span, transaction.display_name, class: "mw-name")
    party = moss_bookings_party(transaction)
    safe_join([safe_join([name, party].compact_blank, " · "), moss_bookings_tag_marks(booking)])
  end

  # WHO is on the other side of the payment, per kind: the card holder and their
  # team, the supplier of an invoice, the person a reimbursement was paid to,
  # the sender of a top-up. Blank parts are omitted, and a kind without a party
  # yields nil (the headline then shows the name alone).
  def moss_bookings_party(transaction)
    case transaction
    when MossCardTransaction
      [transaction.card_holder_name, transaction.card_holder_team_name].compact_blank.join(" · ")
    when MossInvoice then moss_bookings_supplier(transaction)
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
  def moss_bookings_supplier(transaction)
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
  def moss_bookings_tags(booking)
    transaction = booking.moss_transaction
    [moss_bookings_currency_tag(transaction),
      moss_bookings_credit_note_tag(booking),
      moss_bookings_invoice_status_tag(transaction),
      moss_bookings_transaction_state_tag(transaction)].compact_blank
  end

  # #moss_bookings_tags rendered: one bordered %span.moss-tag each, nothing when
  # the row has no tag.
  def moss_bookings_tag_marks(booking)
    safe_join(moss_bookings_tags(booking).map { |text| content_tag(:span, text, class: "moss-tag") })
  end

  # "1.234,00 PLN · Kurs 4,2500" -- the amount Moss actually moved, in the
  # currency it was moved in, and the rate the EUR figure was derived with. The
  # rate part is omitted when the export carried none.
  def moss_bookings_currency_tag(transaction)
    currency = transaction.currency_original
    return nil if currency.blank? || currency == BASE_CURRENCY

    amount = [moss_bookings_number(transaction.signed_total_transaction_amount, 2), currency]
      .compact_blank.join(" ")
    rate = moss_bookings_number(transaction.exchange_rate, 4)
    rate.present? ? "#{amount} · Kurs #{rate}" : amount.presence
  end

  # Money that came back on a card: a card payment is an outflow, so a positive
  # split is a refund and worth naming.
  def moss_bookings_credit_note_tag(booking)
    return nil unless booking.moss_transaction.is_a?(MossCardTransaction)

    "Gutschrift" if booking.signed_base_amount&.positive?
  end

  def moss_bookings_invoice_status_tag(transaction)
    return nil unless transaction.is_a?(MossInvoice)

    status = transaction.invoice_status
    status if status.present? && status != INVOICE_STATUS_NORMAL
  end

  def moss_bookings_transaction_state_tag(transaction)
    state = transaction.moss_transaction_state
    state if state.present? && state != TRANSACTION_STATE_NORMAL
  end

  # Line 2 and below of the description: the Buchungstext of the row's three
  # levels. A top-up has none worth showing -- what it says is where the money
  # came from, which is the fixed account chain (Geldtransit -> Moss).
  def moss_bookings_text_lines(booking)
    if booking.moss_transaction.is_a?(MossTopUp)
      return content_tag(:div, t("fin.moss.top_up_line"))
    end

    lines = booking.text_lines
      .filter_map { |level, name, text| moss_bookings_text_line(level, name, text) }
    safe_join(lines.map { |line| content_tag(:div, line) })
  end

  # ONE line of MossBooking#text_lines, list-style: the TRANSACTION level
  # shows its text only, in italics and without the "Transaktion:" prefix --
  # its name is already line 1, so the prefix would repeat a label in every
  # single row. The expense and booking levels keep the shared rendering
  # (moss_text_line), which the booking detail page relies on: that page shows
  # the same lines WITHOUT a line 1 and needs every prefix, so moss_text_line
  # itself stays untouched.
  def moss_bookings_text_line(level, name, text)
    return moss_text_line(level, name, text) unless level == :transaction
    return nil if text.blank?

    content_tag(:span, auto_link_escaped_multiline(text), class: "fst-italic")
  end

  # German-style number with a fixed number of decimals, nil for nil (so a
  # missing rate simply drops out of its tag).
  def moss_bookings_number(value, precision)
    return nil if value.nil?

    number_with_precision(value, precision: precision, delimiter: ".", separator: ",")
  end

  # --- the booking's detail (fin/moss_bookings/_detail) ------------------------
  #
  # The formatters of the finance detail kit (doc/fin/detail_partials.md), one
  # per field the detail lists. Values of the booking's transaction carry a help
  # line naming that level, so they are not taken for the booking's own. Every
  # link leaves the turbo frame the detail stands in (`_top`).

  # The transaction values the detail shows, each only where the export has it.
  MOSS_BOOKING_TRANSACTION_ATTRS =
    %i[merchant_name top_up_sender invoice_status booking_date submitted_date approval_date].freeze

  MOSS_BOOKING_TRANSACTION_ATTRS.each do |attr|
    define_method(:"fin_format_moss_booking_#{attr}") { |booking| moss_booking_transaction_value(booking, attr) }
  end

  def moss_booking_transaction_value(booking, attr)
    tx = booking.moss_transaction
    value = tx.public_send(attr)
    return nil if value.blank?

    {label: MossTransaction.human_attribute_name(attr),
     value: value.is_a?(Date) ? fin_date(value) : wsjrdp_format_attr(tx, attr),
     help: "aus der #{moss_level_name(:transaction)}"}
  end

  # Betrag / Original-Betrag: always two decimals, as everywhere in the finance
  # views; the original only on a foreign-currency payment.
  def fin_format_moss_booking_amount_with_currency(booking) = format_moss_booking_amount_with_currency(booking)

  def fin_format_moss_booking_original_amount_with_currency(booking)
    format_moss_booking_original_amount_with_currency(booking) if booking.foreign_currency?
  end

  def fin_format_moss_booking_kind(booking) = moss_kind_chip(booking.moss_transaction.type)

  # The payment: "#<id>" as a double link with its Buchungstext, below it the
  # payment in Moss -- except for a top-up, for which Moss has no record page.
  def fin_format_moss_booking_moss_transaction(booking)
    url = booking.moss_transaction.moss_record_url
    moss = content_tag(:div, moss_double_link("in Moss öffnen", url)) if url
    safe_join([content_tag(:div, moss_booking_transaction_line(booking)), moss].compact)
  end

  # The expense of a reimbursement: its name, purchase date and, when Moss
  # booked it against more than one account, the split.
  def fin_format_moss_booking_moss_expense(booking)
    expense = booking.moss_expense
    return nil if expense.display_name.blank? && expense.purchased_on.blank?

    parts = [content_tag(:span, expense.display_name)]
    parts << content_tag(:span, " • Kaufdatum #{fin_date(expense.purchased_on)}", class: "muted") if expense.purchased_on
    parts << content_tag(:span, " • aufgeteilt auf #{expense.bookings.size} Buchungen", class: "muted") if expense.split?
    safe_join(parts)
  end

  # The wallet the payment went through (the transaction's account).
  def fin_format_moss_booking_fin_account(booking) = moss_fin_account_link(booking.fin_account)

  def fin_format_moss_booking_account_number(booking)
    moss_code_name_cell([booking.account_number], moss_account_names)
  end

  def fin_format_moss_booking_cost_center_number(booking)
    moss_code_name_cell([booking.cost_center_number], moss_cost_center_names)
  end

  # One line per level, top down: the transaction's, the expense's, the
  # booking's own -- each the level's name, then its Buchungstext.
  def fin_format_moss_booking_text_lines(booking)
    safe_join(moss_booking_page_text_lines(booking).map { |level, name, text| content_tag(:div, moss_text_line(level, name, text)) })
  end

  # The comments of the transaction and the expense; only the booking's own is
  # editable.
  def fin_format_moss_booking_parent_comments(booking) = moss_level_comment_lines(booking.parent_comments)

  def fin_format_moss_booking_comment(booking)
    auto_link_escaped_multiline(booking.comment) if booking.comment.present?
  end

  def fin_format_moss_booking_contribution_subject(booking) = fin_subject_link(booking.contribution_subject)

  # The Beitragsbuchungen this booking settles -- one Moss booking may be split
  # across several people.
  def fin_format_moss_booking_accounting_entries(booking)
    lines = booking.accounting_entries.map do |entry|
      content_tag(:div, safe_join([fin_entry_link(entry), content_tag(:span, " • ", class: "muted"),
        content_tag(:span, "Person: ", class: "fw-light muted"), fin_subject_link(entry.subject)]))
    end
    lines.empty? ? content_tag(:span, "keine", class: "muted") : safe_join(lines)
  end

  # What the edit page lets a writer change: the comment and the person.
  def fin_moss_booking_edit_options(editable)
    return {} unless editable

    moss_comment_edit_options(true)
      .merge(contribution_subject: {editable: true, input: :helper, options: :fin_moss_booking_subject_input})
  end

  # The person search of hitobito's own forms (the name with its suggestions,
  # the chosen person's id in a hidden field), under it the person the booking
  # has now. As Fin::CamtTransactionsHelper#fin_camt_transaction_subject_input.
  def fin_moss_booking_subject_input(f, _row)
    booking = f.object
    id = "moss_booking_#{booking.id}_contribution_subject"
    typed = params.dig(f.object_name, :contribution_subject)
    field = f.hidden_field(:contribution_subject_id, id: "#{id}_id") +
      f.text_field(:contribution_subject, id: id, value: typed || booking.contribution_subject&.to_s,
        class: "form-control form-control-sm", placeholder: t("global.search.placeholder_person"),
        data: {provide: "entity", id_field: "#{id}_id", no_results_message: t("global.no_list_entries"),
               url: query_people_path})
    current = if booking.contribution_subject_id_changed?
      Person.find_by(id: booking.contribution_subject_id_in_database)
    else
      booking.contribution_subject
    end
    return field if current.blank?

    safe_join([field, wsjrdp_row_help(safe_join(["Bisheriger Wert: ", fin_subject_link(current)]))])
  end
end
