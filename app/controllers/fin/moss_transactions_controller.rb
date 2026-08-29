# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Transaktionen" -- the second Moss tab -- and the four KIND tabs after it
# (Kartenzahlungen, Rechnungen, Erstattungen, Einzahlungen). All five are this
# controller's index: an expandable, filterable table over the Moss
# transactions (card payments, invoices, reimbursements, top-ups), which a kind
# tab pins to its one kind through a route default (`kind`, config/routes.rb)
# -- the way hitobito's Anlässe / Kurse tabs share events#index. The row detail
# is the same detail shown at /fin/moss/transactions/:id. The filter is the
# generic CNF filter (doc/wsjrdp/generic_filter_builder.md) over
# Fin::MossTransactionsFilterSchema, like the Buchungen page.
# controller "fin/moss_transactions" -> Sheet::Fin::MossTransaction (parent
# Sheet::Fin::Moss for the tabs).
#
# The whole table state -- sort, columns, page size, page, the filter, the open
# rows and the filter pane -- is declared once below and resolved by
# Wsjrdp::TableStateful (doc/plans/2026-09_expandable-table-state.md); every tab
# REMEMBERS its own state in the session. "Zurücksetzen" (?f=) clears the
# remembered filter and nothing else; the wholesale ?r=1 reset has no button in
# the UI.
class Fin::MossTransactionsController < Fin::FinController
  include Wsjrdp::TableStateful

  before_action :authorize_action

  helper_method :transactions, :current_kind

  # STI type => route slug of the kind's tab, in tab order (= the order of the
  # overview's kind cards). config/routes.rb declares the routes from the same
  # map; the path helpers are moss_<slug>_path / apply_moss_<slug>_path, the
  # tab labels fin.tabs.<slug>.
  KIND_TABS = {
    "MossCardTransaction" => "card_transactions",
    "MossReimbursement" => "reimbursements",
    "MossInvoice" => "invoices",
    "MossTopUp" => "top_ups"
  }.freeze

  # What a kind tab shows by default and which columns it does not offer at all.
  # The column description stays the dataset's one (Fin::MossTransactionsColumns);
  # a kind tab only narrows it: the kind column is constant there, the mixed
  # "Händler / Empfänger" column gives way to the kind's own person column, and
  # columns that are always empty for the kind (an invoice number on a
  # reimbursement, cost centers on a top-up) leave the picker.
  KIND_COLUMNS = {
    "MossCardTransaction" => {
      default: %w[payment_date signed_total_base_amount description card_holder_name cost_centers account_numbers],
      exclude: %w[kind party recipient_name payout_user_name top_up_sender]
    },
    "MossReimbursement" => {
      default: %w[payment_date signed_total_base_amount description recipient_name bookings_count cost_centers
        account_numbers],
      exclude: %w[kind party card_holder_name top_up_sender invoice_number]
    },
    "MossInvoice" => {
      default: %w[payment_date signed_total_base_amount invoice_number description supplier_account_number
        cost_centers account_numbers],
      exclude: %w[kind party card_holder_name top_up_sender]
    },
    "MossTopUp" => {
      default: %w[payment_date signed_total_base_amount description],
      exclude: %w[kind party card_holder_name recipient_name payout_user_name invoice_number cost_centers
        account_numbers]
    }
  }.freeze

  # The filter is REMEMBERED although D6 leaves it in the URL by default -- the
  # same decision as the Buchungen list, and for the same reason: this is a
  # standalone tab reached from the Finanzen navigation, whose filter is built up
  # condition by condition and then worked with across many sort, column and page
  # changes; losing it on the way back through the tab is the more annoying
  # failure mode. It stays shareable because an explicit URL always beats the
  # store.
  #
  # ONE declaration for the five routes: everything that depends on the tab is a
  # lambda, evaluated on the controller when the state is resolved (current_kind
  # reads the route default). A kind tab pins its kind as a HIDDEN fixed slot --
  # the tab name already says it -- and takes the Art attribute out of the
  # filter picker; its columns come from KIND_COLUMNS; and its store key keeps
  # its memory apart from the other tabs'. The general tab gets the dataset's
  # own defaults, no fixed slot and no exclusions.
  #
  # The general tab also gets the kinds as a "Schnellauswahl": the same preset
  # GROUP the wallet statement shows (Fin::MossKinds.preset_group), so one click
  # narrows the list to the card payments and two pressed buttons WIDEN it to
  # both kinds through one `kind in (…)` slot. A KIND TAB declares none -- its
  # kind is already pinned as a fixed slot, and a button offering another kind
  # would promise a list the pin cannot give.
  TRANSACTIONS_POLICY = wsjrdp_expandable_table_policy prefix: "",
    columns: Fin::MossTransactionsColumns.codec,
    sort: {default: [["payment_date", "desc"]]},
    cols: {default: -> { kind_columns[:default] }, exclude: -> { kind_columns[:exclude] }},
    per_page: {default: 50},
    filter: {policy: :remember, schema: Fin::MossTransactionsFilterSchema,
             fixed: -> { current_kind ? [{slots: [[["kind", "in", current_kind]]], show: :hidden}] : [] },
             presets: -> { current_kind ? [] : [Fin::MossKinds.preset_group] },
             exclude: -> { current_kind ? %i[kind] : [] }},
    pane: {default: 1},
    store_key: -> { "#{controller_path}#index/#{current_kind}" if current_kind }

  # The resolved state of this page's transactions table.
  def transactions_table_state
    wsjrdp_expandable_table_state(TRANSACTIONS_POLICY)
  end

  # The kind (STI type) of the kind tab being shown, nil on the general
  # "Transaktionen" tab. Read from the PATH parameters on purpose: the kind is a
  # route default, and a stray ?kind= query param must not turn the general tab
  # into a kind tab (the tabs light up by path, and each tab has its own memory).
  def current_kind
    return @current_kind if defined?(@current_kind)

    kind = request.path_parameters[:kind]
    raise ActionController::RoutingError, "unknown Moss kind #{kind.inspect}" if kind && !KIND_TABS.key?(kind)

    @current_kind = kind
  end

  # The listing: the de-duplicated, filtered relation handed to
  # Wsjrdp::ExpandableTableRows for sorting, pagination and the sum. Expenses and
  # bookings are preloaded for the aggregate columns AND the expandable detail.
  def transactions
    @transactions ||= Wsjrdp::ExpandableTableRows.new(transactions_table_state,
      distinct_transactions,
      sort: Fin::MossTransactionsColumns.sort_expressions,
      sum: :signed_total_base_amount,
      preload: transaction_preloads,
      tiebreaker: "moss_transactions.id")
  end

  def index
    transactions # memoized; builds the filtered/sorted/paginated page
  end

  def show
    @transaction = MossTransaction.includes(:clearing_datev_booking, :fin_account).find(params[:id])
  end

  # PRG target of the CNF filter builder; lands on the tab it was posted from.
  def apply
    wsjrdp_apply_table_filter(transactions_table_state, redirect_to: tab_path)
  end

  private

  # The listing path of the current tab.
  def tab_path
    current_kind ? public_send(:"moss_#{KIND_TABS.fetch(current_kind)}_path") : moss_transactions_path
  end

  # The column defaults / exclusions of the current tab (KIND_COLUMNS), or the
  # dataset's own on the general tab.
  def kind_columns
    return KIND_COLUMNS.fetch(current_kind) if current_kind

    {default: Fin::MossTransactionsColumns.default_keys, exclude: []}
  end

  # The columns that read a transaction's expenses and bookings
  # (Fin::MossTransactionsHelper#moss_transaction_bookings).
  AGGREGATE_COLUMNS = %w[cost_centers account_numbers bookings_count datev].freeze

  # What the page reaches for per row: the inline detail shows every row's
  # wallet account, and the expenses with their bookings feed the aggregate
  # columns AND the expense sub-rows of a reimbursement
  # (Fin::MossExpenseRowsHelper). A tab on which a reimbursement can appear
  # therefore always preloads them -- the sub-rows read them whatever the
  # visible columns are; on the other kind tabs they are loaded only while an
  # aggregate column is visible, so a slimmed-down column set does not load
  # hundreds of bookings for nothing (Bullet flags both the missing and the
  # unused preload).
  def transaction_preloads
    preloads = [:fin_account]
    preloads << {expenses: :bookings} if expense_rows_possible? ||
      transactions_table_state.visible_column_keys.intersect?(AGGREGATE_COLUMNS)
    preloads
  end

  # Can a reimbursement -- the one kind that brings expense sub-rows -- be on
  # this tab? The general tab lists every kind, the Erstattungen tab that one.
  def expense_rows_possible?
    current_kind.nil? || current_kind == "MossReimbursement"
  end

  # The filtered scope LEFT JOINs the expenses and their bookings (so
  # expense- and booking-level filters can match), which would show a
  # transaction with several matching bookings more than once. The listing
  # therefore selects the matching transaction ids and re-queries
  # moss_transactions by id, so the sort and the paging see one row per
  # transaction. The joins themselves are NOT repeated here -- they belong to
  # the schema's base relation and are merged in by
  # Wsjrdp::Filtering::FilterSchema#compile.
  def distinct_transactions
    MossTransaction.where(id: transactions_table_state.filter.scope(MossTransaction.all)
      .reselect(MossTransaction.arel_table[:id]))
  end

  def authorize_action
    authorize!(:fin_admin, MossTransaction)
  end
end
