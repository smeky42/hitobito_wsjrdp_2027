# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The Finanzen entry page (/fin): one CARD per area, each with its icon, one
# sentence on what the area is for, quick links to the area's tabs and two or
# three key figures. Only the icon and the locale key are written here -- the
# areas are the six Sheet::Fin::* sheets in navigation order, their titles and
# tabs are what those sheets already declare (`tab "fin.tabs.…", :path`), so a
# new tab shows up on /fin by itself (see doc/navigation.md), the purposes come
# from the locale (fin.areas.<key>.purpose) and the numbers from
# Fin::OverviewFigures.
#
# A tab's label may also be a SYMBOL, i.e. the name of a helper method whose
# (html_safe) result is the label -- that is how the Moss kind tabs carry their
# icon. Since the quick links below reuse renderer.label unchanged, such a tab
# brings its markup along to /fin as well; that is intended, and the reason the
# cards put no icon of their own in front of a tab link.
module Fin::OverviewHelper
  # The label key every "Übersicht" tab uses. A tab with this key duplicates the
  # area link, so it is left out of the quick links; nothing else marks an
  # overview tab (its position among the tabs is deliberately not trusted).
  OVERVIEW_TAB_KEY = "fin.tabs.overview"

  # The stored discriminator of the Moss wallet. Its value is still the
  # pre-unification class name, so it is an opaque marker -- the same test
  # WsjrdpFinAccount#transactions makes to pick the kind of statement row an
  # account has.
  MOSS_WALLET_TYPE = "MossBalanceMovement"

  # The six areas in the order of the left sub-navigation (fin/_left_nav):
  # area sheet => the key its sentence lives under (fin.areas.<key>.purpose)
  # and its FontAwesome 5 free SOLID icon. Everything else an area needs -- its
  # title, its tabs and their paths -- comes from the sheet, so this is the only
  # place a new area has to be named.
  AREAS = {
    Sheet::Fin::Accounts => {key: :accounts, icon: "university"},
    Sheet::Fin::Fees => {key: :fees, icon: "coins"},
    Sheet::Fin::Moss => {key: :moss, icon: "wallet"},
    Sheet::Fin::Accounting => {key: :accounting, icon: "book"},
    Sheet::Fin::Reconciliation => {key: :reconciliation, icon: "check-double"},
    Sheet::Fin::Controlling => {key: :controlling, icon: "chart-line"}
  }.freeze

  # One card. `tabs` are [label, path] pairs, `figures` [label, value, warn?]
  # triples -- the value is already a string, warn marks the ones that stand
  # for open work (Controlling has no figures at all).
  Area = Struct.new(:key, :title, :path, :icon, :purpose, :tabs, :figures, keyword_init: true)

  # The sheets of the Finanzen areas, in the order of the left sub-navigation.
  def fin_area_sheets = AREAS.keys

  # [Area, …] -- one per area, in navigation order. The area link is its
  # overview tab, or the first tab when the area has no overview (Konten &
  # Wallets); the quick links are every other tab the person may see
  # (Sheet::Tab::Renderer#show? honours the tab's `if:` condition).
  def fin_areas
    AREAS.map do |sheet, area|
      renderers = sheet.tabs.map { |tab| tab.renderer(self, []) }.select(&:show?)
      overview, others = renderers.partition { |renderer| renderer.label_key == OVERVIEW_TAB_KEY }
      Area.new(key: area[:key], icon: area[:icon], title: sheet.new(self).title,
        purpose: t("fin.areas.#{area[:key]}.purpose"),
        path: (overview.first || renderers.first).path,
        tabs: others.map { |renderer| [renderer.label, renderer.path] },
        figures: fin_area_figures(area[:key]))
    end
  end

  # [[account, balance_cents], …] -- the finance accounts in the order of the
  # Konten list (WsjrdpFinAccount.all), each with the balance that list shows.
  #
  # The balances are TWO grouped sums, one per kind of statement row: a bank
  # account's rows are camt transactions, the wallet's are Moss bookings, and
  # both keep the signed EUR amount in `signed_base_amount`, so the database
  # adds them up. The card therefore costs three queries whatever the number of
  # accounts, where WsjrdpFinAccount#closing_balance_cents (which stays as it
  # is, for the pages showing ONE account) would load every transaction and
  # every booking of every account into Ruby. The account's own balance is kept
  # in integer cents, hence the conversion at this edge -- the same one the
  # model makes.
  def fin_accounts_with_balance
    camt_sums = WsjrdpCamtTransaction.group(:fin_account_id).sum(:signed_base_amount)
    moss_sums = MossBooking.joins(:moss_transaction)
      .group("moss_transactions.fin_account_id").sum(:signed_base_amount)
    WsjrdpFinAccount.all.map do |account|
      sums = (account.transaction_type == MOSS_WALLET_TYPE) ? moss_sums : camt_sums
      [account, account.opening_balance_cents + (sums.fetch(account.id, 0) * 100).round]
    end
  end

  # The name an account goes by in the quick links: its short name, and the
  # full identification (WsjrdpFinAccount#to_s) only where none is set.
  def fin_account_label(account) = account.short_name.presence || account.to_s

  private

  # ONE Fin::OverviewFigures per request: it memoizes every aggregate, so the
  # number two cards share (Beiträge and Abstimmung both show the contribution
  # bookings without a DATEV booking) costs one query, not two.
  def fin_overview_figures
    @fin_overview_figures ||= Fin::OverviewFigures.new
  end

  def fin_area_figures(key)
    case key
    when :accounts then fin_accounts_figures
    when :fees then fin_fees_figures
    when :moss then fin_moss_figures
    when :accounting then fin_accounting_figures
    when :reconciliation then fin_reconciliation_figures
    else [] # Controlling is still empty; its card says so instead.
    end
  end

  # How much the area holds and how far the imported statements reach.
  def fin_accounts_figures
    figures = fin_overview_figures
    [fin_figure(fin_figure_label(:accounts), fin_figure_count(figures.accounts_count)),
      fin_figure(fin_figure_label(:camt_transactions), fin_figure_count(figures.camt_transactions_count)),
      fin_figure(fin_figure_label(:camt_last_value_date), fin_figure_date(figures.camt_last_value_date))]
  end

  def fin_fees_figures
    figures = fin_overview_figures
    [fin_figure(fin_figure_label(:accounting_entries), fin_figure_count(figures.accounting_entries_count)),
      fin_open_figure(fin_figure_label(:accounting_entries_unlinked), figures.accounting_entries_unlinked_count)]
  end

  # Transactions and their bookings are two levels of the same import, hence
  # one row for both.
  def fin_moss_figures
    figures = fin_overview_figures
    [fin_figure(fin_figure_label(:moss_transactions_bookings),
      fin_figure_pair(figures.moss_transactions_count, figures.moss_bookings_count)),
      fin_figure(fin_figure_label(:moss_last_payment_date), fin_figure_date(figures.moss_last_payment_date)),
      fin_open_figure(fin_figure_label(:moss_clearing_unlinked), figures.moss_clearing_unlinked_count)]
  end

  def fin_accounting_figures
    figures = fin_overview_figures
    bookings = fin_figure_count(figures.datev_bookings_count)
    [fin_figure(fin_figure_label(:datev_bookings_in_batches),
      "#{bookings} in #{fin_figure_count(figures.datev_batches_count)}"),
      fin_figure(fin_figure_label(:datev_last_booking_date), fin_figure_date(figures.datev_last_booking_date)),
      fin_figure(fin_figure_label(:cost_centers_personal_accounts),
        fin_figure_pair(figures.cost_centers_count, figures.personal_accounts_count))]
  end

  # Abstimmung has no figures of its own: it is the open work of the two areas
  # it reconciles, so both numbers are the ones their own cards already show.
  def fin_reconciliation_figures
    figures = fin_overview_figures
    [fin_open_figure(fin_figure_label(:reconciliation_entries_unlinked),
      figures.accounting_entries_unlinked_count),
      fin_open_figure(fin_figure_label(:reconciliation_moss_unlinked), figures.moss_expense_unlinked_count)]
  end

  # The row labels live in the locale (fin.overview.figures).
  def fin_figure_label(key) = t("fin.overview.figures.#{key}")

  # A plain figure row: a count, a date or a composed string.
  def fin_figure(label, value) = [label, value, false]

  # A figure row that stands for OPEN WORK: highlighted as long as there is
  # something left to do, plain at zero, so a finished area reads as quiet.
  def fin_open_figure(label, count) = [label, fin_figure_count(count), count.positive?]

  # A count in the notation the finance pages use throughout.
  def fin_figure_count(count) = number_with_delimiter(count, delimiter: ".")

  # Two counts of the same thing at different levels, in one row.
  def fin_figure_pair(first, second) = "#{fin_figure_count(first)} · #{fin_figure_count(second)}"

  # The "Stand" of an area; a table nobody has imported into yet has no date.
  def fin_figure_date(date) = fin_date_or_dash(date)
end
