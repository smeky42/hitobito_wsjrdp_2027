# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# A Moss expense (L2): the cells of the expenses table on a transaction's page
# (Fin::MossExpensesColumns) and the formatters of its detail
# (fin/moss_expenses/_detail, doc/fin/detail_partials.md). Every link of the
# detail leaves the turbo frame it stands in (`_top`).
module Fin::MossExpensesHelper
  def moss_expense_table_columns
    Fin::MossExpensesColumns::COLUMNS.map do |col|
      col.to_table_column(cell: ->(expense) { moss_expense_cell(expense, col.key) })
    end
  end

  def moss_expense_cell(expense, key)
    case key
    when "purchased_on" then fin_date(expense.purchased_on)
    when "bookings_count" then expense.bookings.size
    when "signed_expense_base_amount" then moss_amount_display(expense.signed_expense_base_amount, "EUR")
    else expense.public_send(key)
    end
  end

  # --- the detail -------------------------------------------------------------

  def fin_format_moss_expense_kind(expense) = moss_kind_chip(expense.moss_transaction.type)

  def fin_format_moss_expense_signed_expense_base_amount(expense)
    moss_amount_display(expense.signed_expense_base_amount, "EUR")
  end

  # The amount in the payment's own currency, only on a foreign-currency one.
  def fin_format_moss_expense_original_amount(expense)
    tx = expense.moss_transaction
    moss_amount_display(expense.signed_expense_transaction_amount, tx.currency_original) if tx.foreign_currency?
  end

  # The payment: "#<id>" as a double link with its name.
  def fin_format_moss_expense_moss_transaction(expense)
    tx = expense.moss_transaction
    link = can?(:show, tx) ? moss_double_link("##{tx.id}", moss_transaction_path(tx)) : "##{tx.id}"
    safe_join([link, tx.display_name.presence].compact, " ")
  end

  def fin_format_moss_expense_parent_comments(expense)
    text = expense.moss_transaction.comment
    moss_level_comment_lines([[moss_level_name(:transaction), text]]) if text.present?
  end

  def fin_format_moss_expense_comment(expense)
    auto_link_escaped_multiline(expense.comment) if expense.comment.present?
  end

  # The bookings of the expense, each linked to its page with its account,
  # cost center and amount.
  def fin_format_moss_expense_bookings(expense)
    lines = expense.bookings.map do |booking|
      content_tag(:div, safe_join([
        link_to("##{booking.id}", moss_booking_path(booking), data: {turbo_frame: "_top"}),
        moss_code_name_cell([booking.account_number], moss_account_names),
        moss_code_name_cell([booking.cost_center_number], moss_cost_center_names),
        moss_amount_display(booking.signed_base_amount, "EUR")
      ].compact_blank, content_tag(:span, " · ", class: "muted")))
    end
    safe_join(lines)
  end
end
