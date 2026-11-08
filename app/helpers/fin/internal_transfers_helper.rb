# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The pieces of the Umbuchungen pages (fin/internal_transfers): the list's
# cells, the detail's labels and the legs as links.
module Fin::InternalTransfersHelper
  RULE_LABELS = {
    moss_top_up: "Moss-Einzahlung",
    both_ibans: "IBANs beider Seiten",
    receiver_iban: "Empfänger-IBAN",
    sender_iban: "Absender-IBAN"
  }.freeze

  SOURCE_LABELS = {
    "suggestion" => "Vorschlag, bestätigt",
    "api" => "automatisch beim Import",
    "manual" => "von Hand angelegt"
  }.freeze

  def internal_transfer_rule_label(rule) = RULE_LABELS.fetch(rule&.to_sym, rule.to_s)

  def internal_transfer_status_badge(transfer_or_status)
    status = transfer_or_status.is_a?(Symbol) ? transfer_or_status : transfer_or_status.status
    if status == :complete
      content_tag(:span, safe_join([icon(:check), " vollständig"]), class: "badge text-bg-success")
    else
      content_tag(:span, "offen", class: "badge text-bg-warning")
    end
  end

  def internal_transfer_account_name(account)
    return "–" unless account

    account.short_name.presence || account.to_s
  end

  # The account as a link to its page.
  def internal_transfer_account_link(account)
    return "–" unless account

    link_to(internal_transfer_account_name(account), wsjrdp_fin_account_path(account))
  end

  # The page of a leg's row: the bank transaction or the Moss transaction.
  def internal_transfer_leg_path(leg)
    leg.moss? ? moss_transaction_path(leg.record) : wsjrdp_camt_transaction_path(leg.record)
  end

  # How long the money took: the days between the first outflow and the last inflow.
  def internal_transfer_gap_label(transfer)
    from = transfer.from_legs.filter_map(&:date).min
    to = transfer.to_legs.filter_map(&:date).max
    return nil unless from && to

    days = (to - from).to_i
    case days
    when 0 then "am selben Tag"
    when 1 then "1 Tag später"
    when -1 then "1 Tag früher"
    else (days.positive? ? "#{days} Tage später" : "#{-days} Tage früher")
    end
  end

  def internal_transfer_amount(amount)
    content_tag(:span, fin_money(amount), class: amount.negative? ? "text-danger" : "text-success")
  end

  # The title of a transfer: its accounts, "Von → Nach".
  def internal_transfer_title(transfer)
    from = transfer.from_accounts.map { |account| internal_transfer_account_name(account) }.join(", ")
    to = transfer.to_accounts.map { |account| internal_transfer_account_name(account) }.join(", ")
    "#{from.presence || "?"} → #{to.presence || "?"}"
  end

  # The h1 of a transfer's own page: "Umbuchung #31" light and muted, then
  # the amount and the accounts in short ("791,67 € · A → B").
  def internal_transfer_page_label(transfer) = "Umbuchung ##{transfer.id}"

  def internal_transfer_page_title(transfer)
    "#{fin_money(transfer.amount)} · #{internal_transfer_title(transfer)}"
  end

  def internal_transfer_source_label(meta)
    SOURCE_LABELS.fetch(meta["source"].to_s, meta["source"].to_s.presence || "–")
  end

  # The columns of the list (Fin::InternalTransfersColumns) with their cells.
  def internal_transfers_table_columns
    cells = {
      "date" => ->(row) { fin_date(row.date) },
      "from" => ->(row) { internal_transfer_accounts_cell(row.from_accounts) },
      "to" => ->(row) { internal_transfer_accounts_cell(row.to_accounts) },
      "status" => ->(row) { content_tag(:div, internal_transfer_status_badge(row.status), class: "text-center") },
      "amount" => ->(row) { fin_money(row.amount) },
      "purpose" => ->(row) { content_tag(:span, row.from_purpose, title: row.from_purpose.presence) },
      "comment" => ->(row) { row.transfer.comment }
    }
    Fin::InternalTransfersColumns::COLUMNS.map { |col| col.to_table_column(cell: cells.fetch(col.key)) }
  end

  # The columns of "Buchungen der Umbuchung" (Fin::InternalTransferLegsColumns)
  # with their cells.
  def internal_transfer_legs_table_columns
    cells = {
      "account" => ->(leg) { internal_transfer_account_link(leg.account) },
      "date" => ->(leg) { fin_date(leg.date) },
      "text" => ->(leg) { content_tag(:span, leg.text.truncate(90), title: leg.text.presence) },
      "amount" => ->(leg) { internal_transfer_amount(leg.amount) }
    }
    Fin::InternalTransferLegsColumns::COLUMNS.map { |col| col.to_table_column(cell: cells.fetch(col.key)) }
  end

  # The sum line under the legs: "Summe" in the first column, the balance --
  # with a tick once it is 0 -- under the amounts.
  def internal_transfer_legs_footer(transfer)
    lambda do |col|
      case col[:key]
      when "account" then content_tag(:span, "Summe", class: "fw-semibold")
      when "amount"
        tick = transfer.complete? ? content_tag(:span, icon(:check), class: "text-success ms-1", title: "Die Buchungen gleichen sich aus") : nil
        safe_join([content_tag(:span, fin_money(transfer.balance), class: "fw-semibold"), tick].compact)
      end
    end
  end

  private

  def internal_transfer_accounts_cell(accounts)
    return content_tag(:span, "–", class: "text-muted") if accounts.empty?

    safe_join(accounts.map { |account| internal_transfer_account_link(account) }, ", ")
  end
end
