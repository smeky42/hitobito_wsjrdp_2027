# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Sachkonten (ledger accounts) at /bookkeeping/ledger_accounts: the per-account
# booking sums with the generic CNF filter above them, one expandable detail row
# per account, plus a dedicated detail page per account number.
#
# The list is RELATION-backed (WsjrdpLedgerAccount.with_booking_summary), like
# the Kostenstellen and the Kreditoren one: that is what lets the filter compile
# its conditions into SQL, the headers sort on the aggregates and the footer
# count the FILTERED set. Which accounts it lists is #visible_ledger_accounts --
# an account number that only ever appears on bookings, with no master record of
# its own, is not a row of this list.
class Fin::LedgerAccountsController < Fin::FinController
  include Fin::BookkeepingSummaries

  before_action :authorize_action

  # DATEV Personenkonten (subsidiary accounts) -- creditors are the suppliers,
  # debitors the customers. They are NOT Sachkonten, so the Sachkonten overview
  # excludes them (creditors have their own Kreditoren page).
  PERSONAL_ACCOUNT_KINDS = %w[CREDITOR DEBITOR].freeze

  # The Sachkonten list and the bookings table inside an account's detail. The
  # list declares its own policy, filter included.
  #
  # No "Schnellauswahl" presets: which accounts of the chart are worth showing
  # at all is what #visible_ledger_accounts already decides, so the filter above
  # the list is entirely the user's.
  SUMMARY_POLICY = wsjrdp_expandable_table_policy prefix: "",
    columns: Fin::BookkeepingSummaryColumns::LEDGER_ACCOUNTS.codec,
    # No sort by default: the rows arrive in their natural order, by number.
    sort: {default: []},
    cols: {default: Fin::BookkeepingSummaryColumns::LEDGER_ACCOUNTS.default_keys},
    per_page: {default: Fin::BookkeepingSummaries::SUMMARY_DEFAULT_PER},
    filter: {policy: :remember, schema: Fin::LedgerAccountsFilterSchema},
    pane: {default: 1}
  ITEM_BOOKINGS_POLICY = wsjrdp_expandable_table_policy(**Fin::BookkeepingSummaries
    .item_bookings_policy_options(row_param: :number, nested: true))

  helper_method :ledger_accounts, :account_bookings, :ledger_account_records,
    :shown_booking_count, :shown_booking_sum

  def summary_table_state = wsjrdp_expandable_table_state(SUMMARY_POLICY)

  def item_bookings_table_state = wsjrdp_expandable_table_state(ITEM_BOOKINGS_POLICY)

  # The Sachkonten list: every account the filter leaves, ordered and paged by
  # the summary table's state.
  def ledger_accounts
    @ledger_accounts ||= Wsjrdp::ExpandableTableRows.new(summary_table_state,
      filtered_ledger_accounts,
      sort: Fin::BookkeepingSummaryColumns::LEDGER_ACCOUNTS.sort_expressions,
      tiebreaker: :number)
  end

  # How many BOOKINGS the shown accounts have between them (the footer's second
  # number; the first is the rows object's count). #to_i because a SUM over a
  # derived table comes back as a BigDecimal -- a count is an Integer.
  def shown_booking_count
    @shown_booking_count ||= filtered_ledger_accounts.sum(:booking_count).to_i
  end

  # What the shown accounts add up to (the footer's third number).
  def shown_booking_sum
    @shown_booking_sum ||= filtered_ledger_accounts.sum(:booking_sum)
  end

  def index
  end

  def show
    @account = WsjrdpLedgerAccount.find_by(number: params[:number]) ||
      WsjrdpLedgerAccount.new(number: params[:number])
    @ctx = detail_format_context
    render_item_detail
  end

  # Apply target of the filter builder (PRG, generic implementation in
  # Wsjrdp::TableStateful). The page resets to 1.
  def apply
    wsjrdp_apply_table_filter(summary_table_state, redirect_to: ledger_accounts_path)
  end

  private

  def authorize_action
    authorize!(:show, WsjrdpLedgerAccount)
  end

  def detail_format_context
    if request.headers["Turbo-Frame"].present?
      Fin::AttrFormatContext.embedded(
        Wsjrdp::TableContext.new(level: summary_table_state.level, lazy: true)
      )
    else
      Fin::AttrFormatContext.regular
    end
  end

  # THE filtered relation -- the only way from the state to the rows
  # (state.filter.scope), and what both footer totals aggregate over.
  def filtered_ledger_accounts
    @filtered_ledger_accounts ||=
      summary_table_state.filter.scope(visible_ledger_accounts)
  end

  # The accounts the Sachkonten overview shows, with their two-sided booking
  # totals. Hitobito-own visibility (column wsjrdp_ledger_accounts.visibility;
  # NOT the Moss status): shown when `visible`, or `auto` AND (Moss active OR the
  # account is booked -- which the summary's own booking_count answers). `hidden`
  # never shows. Personal accounts (creditors) live in their own overview.
  #
  # It is a decision of the LIST, not of the record: an account it leaves out
  # still has its detail page.
  def visible_ledger_accounts
    WsjrdpLedgerAccount.with_booking_summary
      .where.not(account_kind: PERSONAL_ACCOUNT_KINDS)
      .where("visibility = 'visible' OR (visibility = 'auto' AND " \
             "(moss_status = :active OR booking_count > 0))",
        active: WsjrdpLedgerAccount::STATUS_ACTIVE)
  end

  # Account detail lists show every booking that touches the account -- on
  # either side -- valued from the account's own perspective
  # (signed_leg_amount), so the embedded list and its sum agree with the
  # summary row.
  def account_bookings(number)
    item_bookings(DatevBooking.legs.where(leg_account_number: number),
      sum: :signed_leg_amount)
  end

  def ledger_account_records
    @ledger_account_records ||= WsjrdpLedgerAccount.all.index_by(&:number)
  end
end
