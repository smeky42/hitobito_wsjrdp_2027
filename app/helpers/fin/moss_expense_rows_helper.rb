# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The expense sub-rows of a Moss REIMBURSEMENT in the transactions list
# (fin/moss_transactions/index, through the shared widget's sub_rows): WHICH
# sub-rows a transaction brings, what each of their cells shows, and the cap
# beyond which the remaining expenses wait behind a rest row.
#
# A reimbursement pays out several expenses (MossExpense, level 2), each of
# which Moss may split across accounts (MossBooking, level 3). The group shows
# one row per expense, in expense_number order; a booking never gets a row of
# its own and never an amount -- it shows only through the Sachkonten,
# Kostenstellen and Buchungen cells of its expense's row. A reimbursement with
# ONE expense stays a single row (its head row already carries that expense's
# figures, name and text), and the other three kinds have no real middle level
# at all, so neither brings sub-rows.
#
# Every figure a sub-row shows is read off the eager-loaded expenses and their
# bookings ONCE, in #moss_expense_sub_rows -- the cell methods below touch
# neither an association nor the database, so a page of 50 transactions issues
# no query per row (Fin::MossTransactionsController#transaction_preloads).
module Fin::MossExpenseRowsHelper
  # How many expense rows a group shows inline. From the fifth expense on, the
  # remaining ones are rendered hidden behind the rest row -- four covers 91 %
  # of the reimbursements, and it keeps the tallest group (thirteen expenses)
  # exactly as tall as a group of five.
  MOSS_EXPENSE_ROW_CAP = 4

  # How many characters of an expense's words a row shows. Name and
  # Buchungstext are free text in Moss, and a long one wraps the row over
  # several lines, which pushes the group's other rows apart and makes the
  # amounts hard to follow. Beyond this length the words are cut with an
  # ellipsis and the FULL string moves into the cell's title, so hovering shows
  # what was cut.
  MOSS_EXPENSE_TEXT_MAX_LENGTH = 120

  # The dash between an expense's name and its Buchungstext. It is part of the
  # string that is measured and cut, so the cut falls where the reader sees it.
  MOSS_EXPENSE_TEXT_SEPARATOR = " – "

  # ONE sub-row of a reimbursement's row group. `kind` says which of the three
  # it is:
  #   :expense   one expense, `ordinal` its 1-based place, `hidden` beyond the cap
  #   :rest      the expenses beyond the cap, aggregated (`count` of them)
  #   :collapse  the link that folds those away again (no figures of its own)
  Row = Data.define(:kind, :expense, :ordinal, :hidden, :count, :amount, :currency,
    :account_numbers, :cost_center_numbers, :bookings_count) do
    def expense? = kind == :expense

    def rest? = kind == :rest

    def collapse? = kind == :collapse
  end

  # The sub-rows of a transaction: none unless it is a reimbursement with two
  # or more expenses, otherwise one row per expense plus -- beyond the cap --
  # the rest row and the collapse row that switch the hidden ones on and off.
  def moss_expense_sub_rows(transaction)
    return [] unless transaction.is_a?(MossReimbursement)

    expenses = transaction.expenses.to_a
    return [] if expenses.size < 2

    rows = expenses.each_with_index.map { |expense, i| moss_expense_expense_row(expense, i + 1) }
    return rows if expenses.size <= MOSS_EXPENSE_ROW_CAP

    rows + [moss_expense_rest_row(expenses.drop(MOSS_EXPENSE_ROW_CAP)), moss_expense_collapse_row]
  end

  # One expense with its own figures; hidden while it sits beyond the cap.
  def moss_expense_expense_row(expense, ordinal)
    moss_expense_row(:expense, expense: expense, ordinal: ordinal,
      hidden: ordinal > MOSS_EXPENSE_ROW_CAP,
      amount: expense.signed_expense_base_amount,
      currency: moss_expense_currency(expense),
      **moss_expense_booking_figures(expense.bookings.to_a))
  end

  # The expenses beyond the cap as one row: how many they are, their sum, the
  # codes of their bookings and how many bookings that is -- so the Betrag
  # column stays additive (head = four amounts + the rest).
  def moss_expense_rest_row(expenses)
    moss_expense_row(:rest, count: expenses.size,
      amount: expenses.sum { |expense| expense.signed_expense_base_amount || 0 },
      currency: moss_expense_currency(expenses.first),
      **moss_expense_booking_figures(expenses.flat_map { |expense| expense.bookings.to_a }))
  end

  # The link that folds the revealed expense rows away again. It stands for no
  # expense, so every cell but the description stays empty.
  def moss_expense_collapse_row = moss_expense_row(:collapse)

  # What a row says about the level below it: the distinct codes of its
  # bookings and their number (a booking never gets a row of its own).
  def moss_expense_booking_figures(bookings)
    {account_numbers: bookings.map(&:account_number).compact_blank.uniq,
     cost_center_numbers: bookings.map(&:cost_center_number).compact_blank.uniq,
     bookings_count: bookings.size}
  end

  # A sub-row, with the defaults of every field its kind does not fill.
  def moss_expense_row(kind, **attrs)
    Row.new(kind: kind, expense: nil, ordinal: nil, hidden: false, count: nil,
      amount: nil, currency: nil, account_numbers: [], cost_center_numbers: [],
      bookings_count: nil, **attrs)
  end

  # The currency the base amounts are in -- the payment's own, exactly as the
  # head row's amount shows it.
  def moss_expense_currency(expense)
    expense&.moss_transaction&.currency.presence || "EUR"
  end

  # The classes of one sub-row: what it is, and whether it starts out hidden.
  def moss_expense_row_class(sub)
    case sub.kind
    when :rest then "moss-expense-rest"
    when :collapse then "moss-expense-collapse d-none"
    else sub.hidden ? "moss-expense-row moss-expense-extra d-none" : "moss-expense-row"
    end
  end

  # ONE cell of a sub-row, by column key. A sub-row fills five of the table's
  # columns; every other one stays empty -- the cell is there, keeps the
  # column's width and shows nothing. Buchungsdatum and Art are among them: the
  # head row above says both for the whole group.
  def moss_expense_row_cell(sub, key)
    return moss_expense_description_cell(sub) if key == "description"

    moss_expense_figure_cell(sub, key)
  end

  # The figures of a sub-row: its amount and what its bookings say. The
  # collapse row has none -- it is a control, not one of the expenses.
  def moss_expense_figure_cell(sub, key)
    return "" if sub.collapse?

    case key
    when "signed_total_base_amount" then moss_expense_amount_cell(sub)
    when "account_numbers" then moss_code_name_cell(sub.account_numbers, moss_account_names)
    when "cost_centers" then moss_code_name_cell(sub.cost_center_numbers, moss_cost_center_names)
    when "bookings_count" then sub.bookings_count
    else ""
    end
  end

  # Betrag: the expense's own amount, in the head row's format but muted, so
  # the column keeps reading as the transactions' amounts while its group adds
  # up below it. Money coming back gets the "+" and the green of the wallet --
  # the sign is the cue, the colour only reinforces it, and green wins over
  # muted.
  def moss_expense_amount_cell(sub)
    display = moss_amount_display(sub.amount, sub.currency)
    return "" if display.blank?
    return content_tag(:span, display, class: "moss-expense-amount text-muted") unless
      sub.amount.positive?

    content_tag(:span, "+#{display}", class: "moss-expense-amount moss-amount-in")
  end

  # Beschreibung: for an expense its place in the group and its words, for the
  # rest / collapse row the link that reveals or hides the expenses beyond the
  # cap.
  def moss_expense_description_cell(sub)
    return moss_expense_toggle_link(sub) unless sub.expense?

    name, text, title = moss_expense_display_parts(sub.expense)
    content_tag(:span, class: "moss-expense-desc", title: title) do
      safe_join([content_tag(:span, sub.ordinal, class: "moss-expense-ordinal"),
        moss_expense_name_and_text(name, text)])
    end
  end

  # What the description cell shows and what it keeps for the hover: the name
  # and the Buchungstext as the row prints them, plus the untruncated string as
  # the title -- nil while nothing was cut, so a short row carries no title at
  # all.
  #
  # The cut is made on the COMBINED string (the two parts and their dash), so
  # the row is capped at MOSS_EXPENSE_TEXT_MAX_LENGTH however the words are
  # split between name and text. What survives the cut decides which part is
  # left: while the whole name plus the dash still fits, the rest is the
  # (shortened) text and stays in italics; otherwise the name itself was cut and
  # there is no text left to show.
  def moss_expense_display_parts(expense)
    name, text = moss_expense_name_and_text_parts(expense)
    full = [name, text].compact.join(MOSS_EXPENSE_TEXT_SEPARATOR)
    return [name, text, nil] if full.length <= MOSS_EXPENSE_TEXT_MAX_LENGTH

    short = truncate(full, length: MOSS_EXPENSE_TEXT_MAX_LENGTH, omission: "…", separator: " ")
    head = name ? "#{name}#{MOSS_EXPENSE_TEXT_SEPARATOR}" : ""
    return [name, short.delete_prefix(head), full] if short.start_with?(head) &&
      short.length > head.length

    [short, nil, full]
  end

  # Name and Buchungstext of one expense, each only when it is there and the
  # text only when it says something the name does not -- the same dedupe rule
  # as MossBooking#text_lines.
  def moss_expense_name_and_text_parts(expense)
    name = expense.display_name.presence
    text = expense.display_text.presence
    [name, (text unless text == name)]
  end

  # The two as the row prints them: the name, then the text in italics after a
  # dash, each only when it is there.
  def moss_expense_name_and_text(name, text)
    safe_join([name, (content_tag(:i, text) if text)].compact, MOSS_EXPENSE_TEXT_SEPARATOR)
  end

  # The rest row's "n weitere Ausgaben anzeigen" and the collapse row's
  # "einklappen".
  def moss_expense_toggle_link(sub)
    return moss_expense_toggle(:collapse, "▴", t("fin.moss.expense_rows.collapse")) unless sub.rest?

    moss_expense_toggle(:expand, "▸", t("fin.moss.expense_rows.show_more", count: sub.count))
  end

  # One of those two links. Both are plain anchors handled by the delegated
  # listener of shared/wsjrdp/_moss_expense_rows: the hidden rows are already
  # on the page, so nothing is requested -- and nothing is remembered either.
  def moss_expense_toggle(action, marker, label)
    link_to("#", class: "moss-expense-toggle", data: {moss_expense_toggle: action}) do
      caret = content_tag(:span, marker, class: "moss-expense-caret", "aria-hidden": "true")
      safe_join([caret, label], " ")
    end
  end
end
