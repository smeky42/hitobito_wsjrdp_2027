# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Personenkonten (personal accounts) at /bookkeeping/personal_accounts --
# currently the Kreditoren (suppliers) view: per-supplier booking sums with the
# generic CNF filter above them, one expandable detail row per supplier, plus a
# dedicated detail page per account number.
#
# Unlike the two other Buchhaltung summaries this page is RELATION-backed
# (WsjrdpPersonalAccount.with_booking_summary), which is what lets the filter
# compile its conditions into SQL, the headers sort on the aggregates and the
# footer sum the FILTERED set.
class Fin::PersonalAccountsController < Fin::FinController
  include Fin::BookkeepingSummaries

  before_action :authorize_action

  # The "Schnellauswahl" above the filter: each preset is a list of user slots
  # that a click adds or removes (doc/wsjrdp/expandable_table.md, "Presets").
  # Both are ONE condition, and both are the `≠ 0` the editor offers first for
  # their attribute, so a preset also recognises what a user builds by hand:
  # "Nur mit Saldo ≠ 0" is `|Saldo| ≠ 0`, one atom over both signs, and equal
  # to `Saldo ≠ 0` because neither asks about the sign (the sign-pair rule of
  # Wsjrdp::Filtering::SlotEquality); "Nur mit Buchungen" is `Buchungen ≠ 0`,
  # which for a count (never negative) is the same predicate as `> 0`.
  PRESETS = [
    {key: "with_balance", label: "Nur mit Saldo ≠ 0",
     slots: [[["booking_balance_abs", "nonzero"]]]},
    {key: "with_bookings", label: "Nur mit Buchungen",
     slots: [[["booking_count", "nonzero"]]]}
  ].freeze

  # The Kreditoren list and the bookings table inside a supplier's detail. The
  # list declares its own policy, filter included.
  SUMMARY_POLICY = wsjrdp_expandable_table_policy prefix: "",
    columns: Fin::BookkeepingSummaryColumns::PERSONAL_ACCOUNTS.codec,
    # No sort by default: the rows arrive in their natural order, by number.
    sort: {default: []},
    cols: {default: Fin::BookkeepingSummaryColumns::PERSONAL_ACCOUNTS.default_keys},
    per_page: {default: Fin::BookkeepingSummaries::SUMMARY_DEFAULT_PER},
    filter: {policy: :remember, schema: Fin::PersonalAccountsFilterSchema, presets: PRESETS},
    pane: {default: 1}
  ITEM_BOOKINGS_POLICY = wsjrdp_expandable_table_policy(**Fin::BookkeepingSummaries
    .item_bookings_policy_options(row_param: :number, nested: true))

  helper_method :personal_accounts, :supplier_bookings, :shown_booking_count

  def summary_table_state = wsjrdp_expandable_table_state(SUMMARY_POLICY)

  def item_bookings_table_state = wsjrdp_expandable_table_state(ITEM_BOOKINGS_POLICY)

  # The Kreditoren list: every supplier the filter leaves, ordered and paged by
  # the summary table's state. Shows ALL known suppliers when nothing is
  # filtered -- those without any booking appear with 0/0.
  def personal_accounts
    @personal_accounts ||= Wsjrdp::ExpandableTableRows.new(summary_table_state, filtered_accounts,
      sort: Fin::BookkeepingSummaryColumns::PERSONAL_ACCOUNTS.sort_expressions,
      tiebreaker: :number)
  end

  # How many BOOKINGS the shown suppliers have between them (the footer's second
  # number; the first is the rows object's count). #to_i because a SUM over a
  # derived table comes back as a BigDecimal -- a count is an Integer.
  def shown_booking_count
    @shown_booking_count ||= filtered_accounts.sum(:booking_count).to_i
  end

  def index
  end

  # One Kreditor's detail, as its own page and as the pane the list lazy-loads.
  # A number without master data still shows its bookings, so an account the
  # DATEV export never described is a stub record carrying just its number.
  def show
    @account = WsjrdpPersonalAccount.find_by(number: params[:number]) ||
      WsjrdpPersonalAccount.new(number: params[:number])
    @ctx = detail_format_context
    render_item_detail
  end

  # Apply target of the filter builder (PRG, generic implementation in
  # Wsjrdp::TableStateful). The page resets to 1.
  def apply
    wsjrdp_apply_table_filter(summary_table_state, redirect_to: personal_accounts_path)
  end

  private

  def authorize_action
    authorize!(:fin_admin, WsjrdpPersonalAccount)
  end

  # THE filtered relation -- the only way from the state to the rows
  # (state.filter.scope), and what both footer totals aggregate over.
  def filtered_accounts
    @filtered_accounts ||=
      summary_table_state.filter.scope(WsjrdpPersonalAccount.with_booking_summary)
  end

  # Supplier detail lists show every booking that touches the account -- on
  # either side -- valued from the account's own perspective
  # (signed_leg_amount), so the embedded list and its sum agree with the
  # summary row.
  def supplier_bookings(number)
    item_bookings(DatevBooking.legs.where(leg_account_number: number),
      sum: :signed_leg_amount)
  end

  # WHERE the detail partial renders (Fin::AttrFormatContext): the account's own
  # page, or the pane a summary row lazy-loads into its turbo frame -- the same
  # frame request #render_item_detail recognises, at the nesting level the list
  # put into the frame's URL.
  def detail_format_context
    if request.headers["Turbo-Frame"].present?
      Fin::AttrFormatContext.embedded(
        Wsjrdp::TableContext.new(level: summary_table_state.level, lazy: true)
      )
    else
      Fin::AttrFormatContext.regular
    end
  end
end
