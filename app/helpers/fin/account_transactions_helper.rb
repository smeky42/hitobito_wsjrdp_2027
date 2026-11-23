# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The cells of the all-transactions page (Fin::AccountTransactionsColumns).
module Fin::AccountTransactionsHelper
  # A hidden party, account or kind column moves into the description: the
  # party as a line, the kind and the account as chips below it; so do the
  # dates (fin_date_chips). Their sorts move into the description's header.
  def account_transaction_table_columns(state)
    hidden = %w[party kind account].select { |key| state.column_hidden?(key) }
    dates = fin_date_chip_modes(state, booking_label: "Buchungstag")
    may_edit = can?(:update, WsjrdpCamtTransaction)
    subs = et_sub_sorts(Fin::AccountTransactionsColumns::COLUMNS, fin_hidden_date_keys(state) + hidden)
    Fin::AccountTransactionsColumns::COLUMNS.map do |col|
      next col.to_table_column(cell: ->(row) { account_transaction_cell(row, col.key) }) unless col.key == "description"

      col.to_table_column(sub_sorts: subs,
        cell: ->(row) { account_transaction_description(row, hidden: hidden, dates: dates, may_edit: may_edit) })
    end
  end

  # The description cell of the row's own table: a bank row's of the account's
  # statement (with its return status and link buttons), a Moss row's of the
  # Moss transactions list. Both read the record itself
  # (Fin::AccountTransactionsController#records).
  def account_transaction_description(row, hidden:, dates:, may_edit:)
    record = account_transaction_record(row)
    party = hidden.include?("party")
    chips = fin_row_chips(fin_date_chips(dates, booking_date: row.booking_date, value_date: row.value_date) +
      [(account_kind_chip(row.kind) if hidden.include?("kind")),
        (account_chip(row.account_name, row.camt? ? "university" : "wallet") if hidden.include?("account"))])
    if row.camt?
      return safe_join([render("fin/wsjrdp_camt_transactions/description", tx: record, may_edit: may_edit,
        party: party), chips].compact)
    end

    line = party ? render("fin/wsjrdp_camt_transactions/party_line", party: row.party, kind: row.party_kind,
      amount: row.signed_base_amount) : nil
    moss_transaction_description_cell(record, party_line: line, chips: chips)
  end

  def account_transaction_cell(row, key)
    case key
    when "booking_date", "value_date" then fin_date(row.public_send(key))
    when "account" then row.account_name
    when "kind" then account_kind_chip(row.kind)
    when "signed_base_amount" then fin_money(row.signed_base_amount, "EUR")
    when "party" then fin_party_cell(row.party, row.party_kind, row.signed_base_amount)
    when "comment" then (content_tag(:span, row.comment, class: "fw-light fst-italic") if row.comment.present?)
    else row.public_send(key)
    end
  end

  # The page of the row's own record: the bank transaction or the Moss one.
  def account_transaction_path(row)
    row.camt? ? wsjrdp_camt_transaction_path(row.id) : moss_transaction_path(row.id)
  end
end
