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
# Under the "Konten" quick link the accounts themselves are listed with their
# balance, and every quick link carries the small new-tab companion icon.
# All rows this spec builds carry invented values.
describe Fin::OverviewController do
  render_views

  let(:person) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

  before { sign_in(person) }

  # The areas in the order of the left sub-navigation, by the key their texts
  # live under (fin.nav.<key>, fin.areas.<key>.purpose).
  def area_keys
    %w[accounts fees moss accounting reconciliation controlling]
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

  # The accounts under the "Konten" quick link, as [label, href, balance]
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

  it "links every area and, next to it, each of its tabs" do
    get :index
    expect(response).to have_http_status(:ok)
    expect(links).to include(
      [I18n.t("fin.nav.accounts"), wsjrdp_fin_accounts_path],
      [I18n.t("fin.tabs.accounts"), wsjrdp_fin_accounts_path],
      [I18n.t("fin.nav.fees"), fees_path],
      [I18n.t("fin.tabs.person_fees"), fin_person_fees_path],
      [I18n.t("fin.tabs.plans"), wsjrdp_payment_plans_path],
      [I18n.t("fin.nav.moss"), moss_path],
      [I18n.t("fin.tabs.transactions"), moss_transactions_path],
      [I18n.t("fin.tabs.card_transactions"), moss_card_transactions_path],
      [I18n.t("fin.tabs.invoices"), moss_invoices_path],
      [I18n.t("fin.tabs.reimbursements"), moss_reimbursements_path],
      [I18n.t("fin.tabs.top_ups"), moss_top_ups_path],
      [I18n.t("fin.nav.accounting"), bookkeeping_path],
      [I18n.t("fin.tabs.bookings"), bookings_path],
      [I18n.t("fin.tabs.ledger_accounts"), ledger_accounts_path],
      [I18n.t("fin.tabs.cost_centers"), cost_centers_path],
      [I18n.t("fin.tabs.suppliers"), personal_accounts_path],
      [I18n.t("fin.nav.reconciliation"), reconciliation_path],
      [I18n.t("fin.tabs.participant_fees"), reconciliation_participant_fees_path],
      [I18n.t("fin.nav.controlling"), controlling_path]
    )
  end

  it "leaves the Übersicht tab out of the quick links (it is the area link)" do
    get :index
    overview_label = I18n.t(Fin::OverviewHelper::OVERVIEW_TAB_KEY)
    expect(links.map(&:first)).not_to include(overview_label)
    # The area link itself is the overview tab's path -- exactly once per area.
    expect(links.count { |_label, href| href == fees_path }).to eq(1)
    expect(links.count { |_label, href| href == bookkeeping_path }).to eq(1)
    expect(links.count { |_label, href| href == moss_path }).to eq(1)
    expect(links.count { |_label, href| href == reconciliation_path }).to eq(1)
    expect(links.count { |_label, href| href == controlling_path }).to eq(1)
  end

  it "recognises the Übersicht tab by its label key, not by its position" do
    tabs = Sheet::Fin::Accounting.tabs
    overview = tabs.find { |tab| tab.label_key == Fin::OverviewHelper::OVERVIEW_TAB_KEY }
    expect(overview).to be_present
    expect(tabs.map(&:label_key)).to all(be_a(String))
    # Konten & Wallets has no overview tab; its area link is its first tab,
    # which therefore also stays among the quick links.
    expect(Sheet::Fin::Accounts.tabs.map(&:label_key))
      .not_to include(Fin::OverviewHelper::OVERVIEW_TAB_KEY)
  end

  it "shows one card per area, in the order of the left sub-navigation" do
    get :index

    expect(cards.map { |c| card_title(c) }).to eq(area_keys.map { |key| I18n.t("fin.nav.#{key}") })
    # Each card is marked with its area's icon (Fin::OverviewHelper::AREAS);
    # Haml merges the fa- class with .fas, so only the fa- half is read back.
    icons = cards.map { |c| c.at_css(".fin-area-icon i")["class"].split.grep(/\Afa-/) }
    expect(icons.flatten).to eq(%w[fa-university fa-coins fa-wallet fa-book fa-check-double
      fa-chart-line])
  end

  it "says on every card what its area is for" do
    get :index

    expect(cards.map(&:text)).to match(
      area_keys.map { |key| a_string_including(I18n.t("fin.areas.#{key}.purpose")) }
    )
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
      expense = MossExpense.create!(moss_transaction: transaction, moss_transaction_uuid: uuid,
        type: "MossTopUpExpense", expense_number: 1, signed_expense_base_amount: 40)
      MossBooking.create!(moss_transaction: transaction, moss_expense: expense,
        moss_transaction_uuid: uuid, booking_unique_item_number: "#{uuid}_1",
        signed_base_amount: 40)
    end

    # The balance is the one the Konten list shows: the opening balance plus
    # every statement row of the account.
    it "lists the accounts with their balance under the Konten quick link" do
      get :index

      expect(account_links).to include(
        ["Beispielkonto", wsjrdp_fin_account_path(bank), "75,25 €"],
        ["Beispiel-Wallet", wsjrdp_fin_account_path(wallet), "42,50 €"]
      )
    end

    it "opens every quick link and every account in a new tab as well" do
      get :index

      expect(quick_links).not_to be_empty
      expect(quick_links.map { |link| newtab_after(link)&.[]("title") })
        .to all(eq("In neuem Tab öffnen"))

      accounts = card("accounts").css(".fin-area-accounts li span > a")
        .reject { |a| a["target"] == "_blank" }
      expect(accounts).not_to be_empty
      expect(accounts.map { |link| newtab_after(link)&.[]("title") })
        .to all(eq("In neuem Tab öffnen"))
    end

    # The heading of a card stays a heading: no icon behind it.
    it "leaves the card headings without a new-tab icon" do
      get :index

      expect(cards.map { |c| newtab_after(c.css("a").first) }).to all(be_nil)
    end
  end

  describe "key figures" do
    # The cards count the WHOLE database, so every number is asserted relative
    # to what the tables already hold when the example starts.
    let!(:before_counts) do
      {accounts: WsjrdpFinAccount.count, entries: AccountingEntry.count,
       unlinked: AccountingEntry.where(datev_booking_id: nil).count}
    end

    let!(:account) do
      WsjrdpFinAccount.create!(short_name: "Vereinskonto", account_identification: "KTO-FIN",
        opening_balance_cents: 0, opening_balance_currency: "EUR",
        opening_balance_date: Date.new(2026, 1, 1))
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

    it "puts the counts of an area on its card" do
      get :index

      expect(figures("accounts")).to include(["Konten", one_more(:accounts), false])
      expect(figures("fees")).to include(["Beitragsbuchungen", one_more(:entries), false])
      # Two levels of the same import, in one row -- both empty here, so the
      # Stand of the Moss card is an em dash.
      expect(figures("moss")).to include(["Transaktionen · Buchungen", "0 · 0", false],
        ["Letzte Transaktion", "—", false])
    end

    # The Beiträge card carries the contribution bookings and nothing else; the
    # Ratenpläne live behind the quick link to their tab.
    it "shows two figures on the Beiträge card" do
      get :index

      expect(figures("fees").map(&:first)).to eq(["Beitragsbuchungen", "ohne DATEV-Buchung"])
    end

    it "highlights a number that stands for open work" do
      get :index

      expect(figures("fees")).to include(["ohne DATEV-Buchung", one_more(:unlinked), true])
      # Abstimmung has no figures of its own: it repeats the open work.
      expect(figures("reconciliation")).to eq(
        [["Beitragsbuchungen ohne DATEV-Buchung", one_more(:unlinked), true],
          ["Moss-Buchungen ohne DATEV-Buchung", "0", false]]
      )
    end

    # A card's "Stand" line has to survive a table nobody has imported into yet.
    it "writes an em dash where there is no date" do
      DatevBooking.delete_all
      WsjrdpCamtTransaction.delete_all

      get :index

      expect(figures("accounts")).to include(["Letzter Umsatz", "—", false])
      expect(figures("accounting")).to include(["Letzter Beleg", "—", false])
    end

    it "says on the Controlling card that it has no figures yet" do
      get :index

      expect(figures("controlling")).to be_empty
      expect(card("controlling").text).to include("Noch keine Kennzahlen.")
    end
  end
end
