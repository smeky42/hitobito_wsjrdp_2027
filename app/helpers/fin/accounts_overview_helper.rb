# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The figures around the account list (/fin/acc, Übersicht of Konten &
# Wallets) and the /fin card. They take the rows the list shows --
# [[account, balance_cents], …] from Fin::OverviewHelper#fin_accounts_with_balance
# -- and leave closed accounts out.
module Fin::AccountsOverviewHelper
  def fin_open_account_rows(rows)
    rows.reject { |account, _balance_cents| account.status == "closed" }
  end

  def fin_total_balance_cents(rows)
    fin_open_account_rows(rows).sum { |_account, balance_cents| balance_cents }
  end

  # format_cents_de for a right-aligned money column: whole euros keep the
  # house ",—", but the dash is drawn centred over a hidden "00"
  # (.fin-zero-cents), so the comma aligns with the comma of the other rows.
  # Pairs with tabular figures on the column.
  def fin_aligned_cents_de(cents)
    return nil if cents.nil?
    return format_cents_de(cents) unless (cents % 100).zero?

    formatted = format_cents_de(cents, zero_cents: ",00")
    whole, unit = formatted.split(",00", 2)
    safe_join([whole, ",", content_tag(:span, content_tag(:span, "—"), class: "fin-zero-cents"), unit])
  end

  # The monthly chart above the account list, as Chartkick series in EUR keyed
  # by "YYYY-MM": "Ein", "Aus" and "Saldo" (the month's in- and outflow and their
  # sum) as columns, and "Kontostand" -- the balance at the end of each month --
  # as a line on its own axis. All open accounts together: the camt rows by
  # value date, the wallet's Moss bookings by booking date
  # (MossTransaction#value_date). The balance starts from each account's
  # opening balance in the month of its opening date, so its last point is the
  # total balance of the open accounts. Months without rows count as 0;
  # transfers between own accounts appear in Ein and Aus and cancel out in Saldo.
  def fin_monthly_movements(rows)
    open_rows = fin_open_account_rows(rows)
    return [] if open_rows.empty?

    ids = open_rows.map { |account, _balance_cents| account.id }
    months = Hash.new { |hash, month| hash[month] = [0.to_d, 0.to_d] }
    fin_monthly_sums(WsjrdpCamtTransaction.where(fin_account_id: ids),
      "wsjrdp_camt_transactions.value_date", "wsjrdp_camt_transactions.signed_base_amount", months)
    fin_monthly_sums(MossBooking.joins(:moss_transaction).where(moss_transactions: {fin_account_id: ids}),
      "moss_transactions.booking_date", "moss_bookings.signed_base_amount", months)
    openings = Hash.new(0.to_d)
    open_rows.each do |account, _balance_cents|
      openings[account.opening_balance_date.strftime("%Y-%m")] += account.opening_balance_cents.to_d / 100
    end

    keys = fin_month_range(*(months.keys + openings.keys).minmax)
    flows = keys.to_h { |month| [month, months.fetch(month, [0.to_d, 0.to_d])] }
    balance = 0.to_d
    running = keys.to_h { |month| [month, (balance += openings[month] + flows[month].sum).to_f] }

    [
      {name: "Ein", data: flows.transform_values { |inflow, _outflow| inflow.to_f }},
      {name: "Aus", data: flows.transform_values { |_inflow, outflow| outflow.to_f }},
      {name: "Saldo", data: flows.transform_values { |pair| pair.sum.to_f }},
      {name: "Kontostand", data: running,
       dataset: {type: "line", yAxisID: "y1", pointRadius: 2, tension: 0}}
    ]
  end

  private

  # Adds the scope's in- and outflow per month ("YYYY-MM") into `months`.
  def fin_monthly_sums(scope, date_column, amount_column, months)
    month = "to_char(#{date_column}, 'YYYY-MM')"
    scope.where.not(date_column => nil).group(Arel.sql(month)).pluck(
      Arel.sql(month),
      Arel.sql("SUM(CASE WHEN #{amount_column} > 0 THEN #{amount_column} ELSE 0 END)"),
      Arel.sql("SUM(CASE WHEN #{amount_column} < 0 THEN #{amount_column} ELSE 0 END)")
    ).each do |key, inflow, outflow|
      months[key][0] += inflow
      months[key][1] += outflow
    end
  end

  # Every "YYYY-MM" from `first` to `last`.
  def fin_month_range(first, last)
    date = Date.strptime(first, "%Y-%m")
    stop = Date.strptime(last, "%Y-%m")
    keys = []
    while date <= stop
      keys << date.strftime("%Y-%m")
      date = date.next_month
    end
    keys
  end
end
