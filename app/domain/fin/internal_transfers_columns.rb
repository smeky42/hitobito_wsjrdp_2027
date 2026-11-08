# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Column definitions of the Umbuchungen list (/fin/acc/internal_transfers):
# one WsjrdpInternalTransfer per row. A transfer's date, amount and accounts
# come from its legs in two tables, so the list is array-backed (Row) and
# every column sorts by an extractor. No column gives way on its own; on a
# narrow screen the table scrolls with the date column staying at the left.
# With room to spare the columns widen to their targets (Verwendungszweck the
# fastest), then they grow -- Verwendungszweck six times as much as the
# accounts and the comment --, then the gaps (`t.gaps` in the view).
module Fin::InternalTransfersColumns
  # One row of the list: the transfer with what its cells and sorts read.
  class Row
    attr_reader :transfer, :date, :amount, :status, :from_accounts, :to_accounts, :from_purpose, :to_purpose

    def initialize(transfer)
      @transfer = transfer
      @date = transfer.date
      @amount = transfer.amount
      @status = transfer.status
      @from_accounts = transfer.from_accounts
      @to_accounts = transfer.to_accounts
      # What the outgoing and the incoming rows say: the bank's purpose or the Moss text.
      @from_purpose = transfer.from_legs.map(&:text).compact_blank.uniq.join(" · ")
      @to_purpose = transfer.to_legs.map(&:text).compact_blank.uniq.join(" · ")
    end

    def id = transfer.id

    def accounts_label(accounts) = accounts.map { |account| account.short_name.presence || account.to_s }.join(", ")
  end

  COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "itcol") do |c|
    c.column key: "date", abbr: "dt", label: "Datum", width: "6.5rem", sticky: true, tabular_nums: true,
      sort: ->(row) { row.date || Date.new(0) }, sort_first: "desc", default: true
    c.column key: "from", abbr: "fr", label: "Von", width: "9rem", target_width: "14rem", grow: 1, truncate: true,
      sort: ->(row) { row.accounts_label(row.from_accounts).downcase }, default: true
    c.column key: "purpose", abbr: "pp", label: "Verwendungszweck (Von)", width: "12rem", target_width: "24rem",
      target_grow: 3, grow: 6, truncate: true, sort: ->(row) { row.from_purpose.downcase }
    c.column key: "to", abbr: "to", label: "Nach", width: "9rem", target_width: "14rem", grow: 1, truncate: true,
      sort: ->(row) { row.accounts_label(row.to_accounts).downcase }, default: true
    c.column key: "status", abbr: "st", label: "Status", width: "7rem", header_align: "center",
      sort: ->(row) { (row.status == :open) ? 0 : 1 }, default: true
    c.column key: "amount", abbr: "am", label: "Betrag", numeric: true, width: "8.5rem",
      sort: ->(row) { row.amount }, sort_first: "desc", default: true
    c.column key: "comment", abbr: "cm", label: "Kommentar", width: "12rem", target_width: "18rem", grow: 1,
      truncate: true,
      sort: ->(row) { row.transfer.comment.to_s.downcase }
  end

  def self.sort_lambdas = COLUMNS.sort_expressions
end
