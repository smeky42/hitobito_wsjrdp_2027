# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Finanzen entry page shows one card per area. Its links -- the area link
# and the tab quick links -- are derived from the Sheet::Fin::* sheets
# (Fin::OverviewHelper#fin_areas), so a tab declared on a sheet appears here
# without any change to the page; its numbers come from Fin::OverviewFigures.
# Under "Konten" (a link to every account's transactions) the accounts
# themselves are listed with their balance, and every quick link carries the small new-tab
# companion icon. The Konten & Wallets card shows the total balance.
# All rows this spec builds carry invented values.
describe Fin::OverviewController do
  render_views

  before_all(setup_fixtures: true) {}

  let_it_be(:person) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

  before { sign_in(person) }

  # The areas in the order of the left sub-navigation, by the key their texts
  # live under (fin.nav.<key>, fin.areas.<key>.purpose). The write tier sees
  # the Verwaltung for its Zahlungscodes tab.
  def area_keys
    %w[accounts payments fees moss accounting reconciliation controlling admin]
  end

  # [label, href] of every link inside #main.
  def links
    Nokogiri::HTML(response.body).css("#main a").map { |a| [a.text.strip, a["href"]] }
  end

  # The area cards, in document order.
  def cards
    Nokogiri::HTML(response.body).css(".fin-area")
  end

  # A card's heading, which is its area link -- the first link on the card.
  def card_title(card)
    card.css("a").first.text.strip
  end

  # One card by its area key.
  def card(key)
    cards.find { |c| card_title(c) == I18n.t("fin.nav.#{key}") }
  end

  # The small companion link that opens the preceding link in a new tab
  # (Fin::LabeledRowsHelper#wsjrdp_newtab_link), or nil where there is none.
  def newtab_after(link)
    sibling = link.next_element
    (sibling&.name == "a" && sibling["target"] == "_blank") ? sibling : nil
  end

  # The quick links of every card -- the tab links, without their new-tab
  # companions and without the account links nested under one of them.
  def quick_links
    cards.css("ul.fin-area-links > li > a").reject { |a| a["target"] == "_blank" }
  end

  # The accounts under the "Konten" heading, as [label, href, balance]
  # triples in document order.
  def account_links
    card("accounts").css(".fin-area-accounts li").map do |li|
      link = li.at_css("a")
      [link.text.strip, link["href"], li.at_css(".fin-area-account-balance").text.strip]
    end
  end

  # The figure rows of a card as [label, value, highlighted?] triples.
  def figures(key)
    card(key).css(".fin-figure").map do |row|
      value = row.at_css(".fin-figure-value")
      [row.at_css(".fin-figure-label").text.strip, value.text.strip,
        value["class"].split.include?("fin-figure-warn")]
    end
  end

  it "shows one card per area in navigation order, linking the area and each tab but the Übersicht" do
    get :index

    expect(cards.map { |c| card_title(c) }).to eq(area_keys.map { |key| I18n.t("fin.nav.#{key}") })
    expect(cards.map(&:text)).to match(
      area_keys.map { |key| a_string_including(I18n.t("fin.areas.#{key}.purpose")) }
    )
    expect(links).to include(
      [I18n.t("fin.nav.accounts"), wsjrdp_fin_accounts_path],
      [I18n.t("fin.nav.payments"), fin_payments_path],
      [I18n.t("fin.tabs.payment_orders"), payment_orders_path],
      [I18n.t("fin.tabs.direct_debits"), direct_debits_path],
      [I18n.t("fin.tabs.payment_returns"), payment_returns_path],
      [I18n.t("fin.nav.fees"), fees_path],
      [I18n.t("fin.tabs.person_fees"), fin_person_fees_path],
      [I18n.t("fin.tabs.plans"), wsjrdp_payment_plans_path],
      [I18n.t("fin.nav.moss"), moss_path],
      [I18n.t("fin.tabs.transactions"), moss_transactions_path],
      [I18n.t("fin.nav.accounting"), bookkeeping_path],
      [I18n.t("fin.tabs.bookings"), bookings_path],
      [I18n.t("fin.tabs.ledger_accounts"), ledger_accounts_path],
      [I18n.t("fin.tabs.cost_centers"), cost_centers_path],
      [I18n.t("fin.tabs.suppliers"), personal_accounts_path],
      [I18n.t("fin.nav.reconciliation"), reconciliation_path],
      [I18n.t("fin.tabs.participant_fees"), reconciliation_participant_fees_path],
      [I18n.t("fin.nav.controlling"), controlling_path]
    )
    # The Moss kinds are sub-tabs of Transaktionen (Sheet::Fin::Moss), not
    # tabs of the sheet, so /fin leaves them out.
    expect(links.map(&:last)).not_to include(moss_card_transactions_path, moss_reimbursements_path,
      moss_invoices_path, moss_top_ups_path)
    # The area link is the overview tab's path, exactly once per area.
    expect(links.map(&:first)).not_to include(I18n.t(Fin::OverviewHelper::OVERVIEW_TAB_KEY))
    [wsjrdp_fin_accounts_path, fees_path, bookkeeping_path, moss_path, reconciliation_path, controlling_path]
      .each { |path| expect(links.count { |_label, href| href == path }).to eq(1) }
  end

  it "recognises the Übersicht tab by its label key, not by its position" do
    tabs = Sheet::Fin::Accounting.tabs
    overview = tabs.find { |tab| tab.label_key == Fin::OverviewHelper::OVERVIEW_TAB_KEY }
    expect(overview).to be_present
    expect(tabs.map(&:label_key)).to all(be_a(String))
    # Konten & Wallets has an Übersicht tab as well: it is the area link, not
    # a quick link.
    expect(Sheet::Fin::Accounts.tabs.map(&:label_key))
      .to include(Fin::OverviewHelper::OVERVIEW_TAB_KEY)
  end

  describe "quick links" do
    # A bank account and the wallet, so both kinds of statement row are summed:
    # a bank account's balance comes from its camt transactions, the wallet's
    # from its Moss bookings. All names, numbers and dates are invented.
    let!(:bank) do
      WsjrdpFinAccount.create!(short_name: "Beispielkonto", account_identification: "BANK-OV",
        opening_balance_cents: 0, opening_balance_currency: "EUR",
        opening_balance_date: Date.new(2026, 1, 1))
    end

    let!(:wallet) do
      WsjrdpFinAccount.create!(short_name: "Beispiel-Wallet", account_identification: "WALLET-OV",
        transaction_type: "MossBalanceMovement", opening_balance_cents: 250,
        opening_balance_currency: "EUR", opening_balance_date: Date.new(2026, 1, 1))
    end

    def camt_transaction(reference, amount)
      WsjrdpCamtTransaction.create!(fin_account: bank, camt_type: "CAMT053",
        account_identification: bank.account_identification, account_servicer_reference: reference,
        credit_debit_indication: amount.negative? ? "DBIT" : "CRDT",
        signed_base_amount: amount, base_currency: "EUR", value_date: Date.new(2026, 4, 2),
        description: "Beispielbuchung #{reference}")
    end

    let!(:camt_in) { camt_transaction("REF-OV-1", 100.50) }
    let!(:camt_out) { camt_transaction("REF-OV-2", -25.25) }

    # One top-up with its (shell) expense and the booking that is the wallet's
    # statement row.
    let!(:moss_booking) do
      uuid = SecureRandom.uuid
      transaction = MossTransaction.create!(type: "MossTopUp", moss_transaction_uuid: uuid,
        fin_account: wallet, signed_total_base_amount: 40, currency: "EUR",
        payment_date: Date.new(2026, 3, 6))
      expense = MossExpense.create!(moss_transaction: transaction, moss_expense_uuid: uuid,
        type: "MossTopUpExpense", expense_number: 1, signed_expense_base_amount: 40)
      MossBooking.create!(moss_transaction: transaction, moss_expense: expense,
        sub_row_number: 1, signed_base_amount: 40)
    end

    # The balance is the one the Konten list shows: the opening balance plus
    # every statement row of the account. "Konten" leads to every account's
    # transactions, the accounts below it to their own pages; the card's single
    # figure is the total of the balances it lists.
    it "lists the accounts with their balance and total, every quick link with a new-tab companion" do
      get :index

      expect(account_links).to include(
        ["Beispielkonto", wsjrdp_fin_account_path(bank), "75,25 €"],
        ["Beispiel-Wallet", wsjrdp_fin_account_path(wallet), "42,50 €"]
      )
      expect(card("accounts").at_css("ul.fin-area-links > li > a")["href"]).to eq(fin_account_transactions_path)
      euros = ->(text) { BigDecimal(text.delete(". €").tr(",", ".").sub("—", "0")) }
      total = account_links.sum { |_label, _href, balance| euros.call(balance) }
      label, value, warn = figures("accounts").sole
      expect([label, euros.call(value), warn]).to eq(["Gesamtsaldo", total, false])

      accounts = card("accounts").css(".fin-area-accounts li span > a").reject { |a| a["target"] == "_blank" }
      expect(quick_links + accounts).to all(satisfy { |link| newtab_after(link) })
      expect(cards.map { |c| newtab_after(c.css("a").first) }).to all(be_nil)
    end
  end

  describe "key figures" do
    # The cards count the WHOLE database, so every number is asserted relative
    # to what the tables already hold when the example starts.
    let!(:before_counts) do
      {entries: AccountingEntry.count,
       unlinked: AccountingEntry.where(datev_booking_id: nil).count}
    end

    # A contribution booking without its DATEV booking: the open work both the
    # Beiträge and the Abstimmung card show.
    let!(:unlinked_entry) do
      AccountingEntry.create!(subject: person, author: person, amount_eur: 50,
        description: "Beitragsrate", value_date: Date.new(2026, 3, 1),
        booking_date: Date.new(2026, 3, 1))
    end

    # What a card shows once this example added one row to that table.
    def one_more(key)
      ActiveSupport::NumberHelper.number_to_delimited(before_counts.fetch(key) + 1, delimiter: ".")
    end

    # The Beiträge card carries the contribution bookings and nothing else;
    # Abstimmung repeats the open work; a "Stand" line survives a table nobody
    # has imported into yet.
    it "puts the counts of an area on its card, the open work highlighted" do
      DatevBooking.delete_all

      get :index

      expect(figures("fees")).to eq([["Beitragsbuchungen", one_more(:entries), false],
        ["ohne DATEV-Buchung", one_more(:unlinked), true]])
      expect(figures("moss")).to include(["Transaktionen · Buchungen", "0 · 0", false],
        ["Letzte Buchung", "—", false])
      expect(figures("reconciliation")).to eq(
        [["Beitragsbuchungen ohne DATEV-Buchung", one_more(:unlinked), true],
          ["Moss-Buchungen ohne DATEV-Buchung", "0", false]]
      )
      expect(figures("accounting")).to include(["Letzter Beleg", "—", false])
      expect(figures("controlling")).to be_empty
    end
  end
end
