# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The all-transactions page (/fin/acc/all), the first tab under the accounts
# tab: the bank and Moss transactions of every own account in one table
# (Fin::AccountTransaction). A row opens the record's own detail.
class Fin::AccountTransactionsController < Fin::FinController
  include Wsjrdp::TableStateful

  before_action :authorize_action

  helper_method :transactions, :account_transaction_record

  # Remembered like the other lists reached from the navigation; the kinds
  # (bank, then the Moss kinds) as one segment, every kind chosen by default.
  POLICY = wsjrdp_expandable_table_policy prefix: "",
    columns: Fin::AccountTransactionsColumns.codec,
    sort: {hidden: [["booking_date", "desc"]]},
    cols: {default: Fin::AccountTransactionsColumns.default_keys, never: %w[value_date]},
    per_page: {default: 50},
    filter: {policy: :remember, schema: Fin::AccountTransactionsFilterSchema,
             fixed_groups: -> { [kind_group] }},
    lifts: {policy: :remember},
    pane: {default: 1}

  def index
    transactions # memoized; builds the filtered/sorted/paginated page
  end

  # PRG target of the CNF filter builder.
  def apply
    wsjrdp_apply_table_filter(table_state, redirect_to: fin_account_transactions_path)
  end

  def table_state = wsjrdp_expandable_table_state(POLICY)

  def transactions
    @transactions ||= Wsjrdp::ExpandableTableRows.new(table_state,
      table_state.filter.scope(Fin::AccountTransaction.all),
      sort: Fin::AccountTransactionsColumns.sort_expressions, sum: :signed_base_amount,
      tiebreaker: "wsjrdp_camt_transactions.row_key")
  end

  # The bank or Moss transaction behind a row of the page, loaded the way its
  # own table loads it, for the description cell.
  def account_transaction_record(row) = records.fetch(row.source).fetch(row.id)

  private

  # The page's records by source and id; none while the description is hidden.
  def records
    @records ||= begin
      rows = table_state.visible_column_keys.include?("description") ? transactions.page.to_a : []
      ids = rows.group_by(&:source).transform_values { |r| r.map(&:id) }
      {"camt" => WsjrdpCamtTransaction.select(Fin::CamtTransactionsColumns::SELECT_SQL)
        .where(id: ids["camt"].to_a).preload(Fin::CamtTransactionsColumns::ROW_PRELOADS).index_by(&:id),
       "moss" => MossTransaction.where(id: ids["moss"].to_a)
         .preload(expenses: {bookings: Fin::MossTransactionsTable::BOOKING_LINK_PRELOADS}).index_by(&:id)}
    end
  end

  def kind_group = Fin::AccountKinds.fixed_group

  def authorize_action
    authorize!(:show, WsjrdpCamtTransaction)
    authorize!(:show, MossTransaction)
  end
end
