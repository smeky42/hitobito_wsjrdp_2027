# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Column registry + per-cell formatting for the Moss card transactions listing.
# Rendering itself is the shared shared/_expandable_table widget (see
# fin/moss_card_transactions/index). Aggregate columns (Buchungen, Sachkonten,
# Kostenstellen) read the eager-loaded `bookings`, so the query MUST preload them;
# account / cost-center NAMES come from a per-request lookup map (join with
# wsjrdp_ledger_accounts / wsjrdp_personal_accounts / wsjrdp_cost_centers).
module MossCardTransactionsHelper
  MctColumn = Struct.new(:key, :label, :numeric, :width, keyword_init: true) do
    def sortable?
      MossCardTransactionsQuery::SORTABLE.key?(key)
    end
  end

  # Declaration order = the table column order when no `cols` param is set (see
  # ExpandableTableHelper#et_column_states). The default-visible columns come
  # first, in the configured order; every other column follows (hidden by
  # default, available via the column picker).
  ALL_MCT_COLUMNS = [
    MctColumn.new(key: "booking_date", label: "Datum", width: "8rem"),
    MctColumn.new(key: "total_amount", label: "Betrag", numeric: true, width: "9rem"),
    MctColumn.new(key: "parent_booking_text", label: "Buchungstext", width: "20rem"),
    MctColumn.new(key: "cost_centers", label: "Kostenstellen", width: "14rem"),
    MctColumn.new(key: "account_numbers", label: "Sachkonten", width: "16rem"),
    MctColumn.new(key: "merchant_name", label: "Händler", width: "14rem"),
    MctColumn.new(key: "cardholder", label: "Karteninhaber", width: "11rem"),
    MctColumn.new(key: "bookings_count", label: "Zahl Buchungen", numeric: true, width: "7rem"),
    MctColumn.new(key: "payment_date", label: "Zahlungsdatum", width: "8rem"),
    MctColumn.new(key: "settlement_date", label: "Abrechnungsdatum", width: "8rem"),
    MctColumn.new(key: "transaction_state", label: "Status", width: "7rem"),
    MctColumn.new(key: "invoice_number", label: "Rechnungsnr.", width: "9rem"),
    MctColumn.new(key: "has_receipt", label: "Beleg", width: "5rem")
  ].freeze

  # Shown initially, in this order; every other column is available via the picker.
  DEFAULT_COLUMN_KEYS = %w[
    booking_date total_amount parent_booking_text cost_centers account_numbers
  ].freeze

  def card_transaction_table_columns(_query)
    ALL_MCT_COLUMNS.map do |col|
      {
        key: col.key,
        abbr: MossCardTransactionsQuery::COLUMN_ABBREVIATIONS[col.key] || col.key,
        label: col.label,
        numeric: col.numeric,
        width: col.width,
        css_class: "mctcol-#{col.key}",
        sort_key: (col.sortable? ? col.key : nil),
        cell: ->(tx) { card_transaction_cell(tx, col.key) }
      }
    end
  end

  def card_transaction_cell(tx, key)
    case key
    when "booking_date", "payment_date", "settlement_date"
      tx.public_send(key)&.strftime("%d.%m.%Y")
    when "total_amount"
      card_transaction_amount_cell(tx)
    when "bookings_count"
      tx.bookings.size
    when "account_numbers"
      mct_code_name_cell(tx.bookings.map(&:account_number), mct_account_names)
    when "cost_centers"
      mct_code_name_cell(tx.bookings.map(&:cost_center_number), mct_cost_center_names)
    when "has_receipt"
      tx.invoice_file_name.present? ? icon(:check) : ""
    else
      tx.public_send(key)
    end
  end

  # Betrag: total in the booking currency; when the ORIGINAL currency differs, the
  # foreign-currency total goes on a second, muted line (like the bookings table).
  def card_transaction_amount_cell(tx)
    primary = moss_amount_display(tx.total_amount, tx.currency)
    return primary unless mct_foreign_currency?(tx)

    foreign = moss_amount_display(tx.total_original_amount, tx.original_currency)
    return primary if foreign.blank?
    safe_join([primary, content_tag(:div, foreign, class: "text-muted small")])
  end

  def mct_foreign_currency?(tx)
    tx.original_currency.present? && tx.original_currency != tx.currency
  end

  # Distinct codes of a transaction's bookings, each followed by its name in muted
  # font (name omitted if unknown), one per line.
  def mct_code_name_cell(codes, names)
    entries = codes.compact.uniq.sort.map do |code|
      name = names[code]
      name.blank? ? code : safe_join([code, content_tag(:span, name, class: "text-muted")], " ")
    end
    safe_join(entries, tag.br)
  end

  # number => name, loaded once per request. Ledger accounts and suppliers use
  # disjoint number ranges (700xxx creditors only in wsjrdp_personal_accounts), so the two
  # name sources simply union -- same approach as the bookings page.
  def mct_account_names
    @mct_account_names ||= WsjrdpLedgerAccount.pluck(:number, :name).to_h
      .merge(WsjrdpPersonalAccount.pluck(:number, :name).to_h)
  end

  def mct_cost_center_names
    @mct_cost_center_names ||= WsjrdpCostCenter.pluck(:number, :name).to_h
  end

  # Signed amount + currency code (never the "€" symbol; foreign currency possible).
  def moss_amount_display(value, currency = nil)
    return nil if value.nil?
    formatted = number_with_precision(value, precision: 2, delimiter: ".", separator: ",")
    currency.present? ? "#{formatted} #{currency}" : formatted
  end

  # Number of receipt files referenced by a transaction (Invoice File Name is
  # pipe-separated; see doc/moss_data_model.md 5.2.3).
  def card_transaction_receipt_names(tx)
    tx.invoice_file_name.to_s.split("|").map(&:strip).compact_blank
  end
end
