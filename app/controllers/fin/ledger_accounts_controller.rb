# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Sachkonten (ledger accounts) at /bookkeeping/ledger_accounts: the per-account
# booking sums, one expandable detail row per account, plus a dedicated detail
# page per account number.
class Fin::LedgerAccountsController < Fin::FinController
  include Fin::BookkeepingSummaries

  before_action :authorize_action

  # DATEV Personenkonten (subsidiary accounts) -- creditors are the suppliers,
  # debitors the customers. They are NOT Sachkonten, so the Sachkonten overview
  # excludes them (creditors have their own Kreditoren page).
  PERSONAL_ACCOUNT_TYPES = %w[CREDITOR DEBITOR].freeze

  helper_method :account_summaries, :account_types, :account_bookings_query,
    :ledger_account_records

  def index
  end

  def show
    @number = params[:number]
    render_item_detail
  end

  private

  def authorize_action
    authorize!(:fin_admin, WsjrdpLedgerAccount)
  end

  # Sachkonten balances via the general-ledger legs: a booking counts on both its
  # Konto and Gegenkonto side, each from its own perspective, so SUM is correct
  # even for accounts that appear as Gegenkonto (e.g. the income account, whose
  # bookings are almost all on the offsetting side). See doc/bookkeeping.md.
  def account_summaries
    @account_summaries ||= begin
      numbers = visible_ledger_account_numbers
      by_number = leg_summaries(numbers).index_by { |r| r[:number] }
      rows = numbers.map { |n| by_number[n] || {number: n, sum: 0, count: 0} }
      sort_summary_rows(rows, summary_row_extractors { |number| ledger_account_records[number]&.name })
    end
  end

  # Account numbers shown in the Sachkonten overview. Hitobito-own visibility
  # (column wsjrdp_ledger_accounts.visibility; NOT Moss status): shown when
  # `visible`, or `auto` AND (Moss active OR the account is booked). `hidden`
  # never shows. Personal accounts (creditors) live in their own overview.
  def visible_ledger_account_numbers
    booked = "SELECT account_number FROM datev_bookings " \
      "UNION SELECT offsetting_account_number FROM datev_bookings"
    WsjrdpLedgerAccount
      .where.not(account_type: PERSONAL_ACCOUNT_TYPES)
      .where(
        "visibility = 'visible' OR (visibility = 'auto' AND " \
        "(moss_status = 'active' OR number IN (#{booked})))"
      )
      .order(:number)
      .pluck(:number)
  end

  def account_types
    @account_types ||= WsjrdpLedgerAccount.pluck(:number, :account_type).to_h
  end

  # Account detail lists show every booking that touches the account -- on
  # either side -- valued from the account's own perspective (leg_amount), so
  # the embedded list and its sum agree with the summary row.
  def account_bookings_query(number)
    DatevBookingsQuery.new(params, base: DatevBooking.legs.where(leg_account: number),
      sum_column: :leg_amount, default_per: Fin::BookkeepingSummaries::CONDENSED_DEFAULT_PER)
  end

  def ledger_account_records
    @ledger_account_records ||= WsjrdpLedgerAccount.all.index_by(&:number)
  end
end
