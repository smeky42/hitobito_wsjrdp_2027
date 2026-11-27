# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Controlling page "Budget". Invented numbers and amounts.
describe Fin::BudgetsController do
  before_all(setup_fixtures: true) {}

  let_it_be(:person) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

  def self.create_booking(number, amount, debit_credit: "C")
    DatevBooking.create!(buchungs_guid: SecureRandom.uuid,
      account_number: "1200", account_kind: "BANK",
      offsetting_account_number: "66500", offsetting_account_kind: "EXPENSE",
      cost_center_number: number, base_amount: amount, transaction_amount: amount,
      debit_credit: debit_credit, base_currency: "EUR", booking_date: Date.new(2025, 6, 1),
      posting_text: "Test")
  end

  before_all do
    WsjrdpCostCenter.create!(number: "K100", name: "Alpha", short_name: "Alpha", budget_2025: 1000)
    self.class.create_booking("K100", 1234)
  end

  before { sign_in(person) }

  def row_order = controller.send(:budget_rows).page.map { |row| row.number || row.sum_label }

  describe "sorting by a measure" do
    before_all do
      WsjrdpCostCenter.create!(number: "K200", name: "Beta", short_name: "Beta", budget_2025: 100)
      WsjrdpCostCenter.create!(number: "K300", name: "Gamma", short_name: "Gamma")
      self.class.create_booking("K200", 50)
      self.class.create_booking("K300", 9999)
    end

    it "orders by number while nothing is sorted, the sum row last" do
      get :index
      expect(row_order).to eq(["K100", "K200", "K300", "Alle Ausgaben"])
    end

    it "sorts by the share spent, a cost center without budget last" do
      get :index, params: {s: "25_pct~"}
      expect(row_order).to eq(["Alle Ausgaben", "K100", "K200", "K300"])
    end

    it "sorts by the share spent ascending, a cost center without budget still last" do
      get :index, params: {s: "25_pct"}
      expect(row_order).to eq(["K200", "K100", "Alle Ausgaben", "K300"])
    end

    it "sorts by IST, the sum row with the others" do
      get :index, params: {s: "ges_ist~"}
      expect(row_order).to eq(["Alle Ausgaben", "K300", "K100", "K200"])
    end

    it "sorts by budget" do
      get :index, params: {s: "ges_soll~"}
      expect(row_order).to eq(["Alle Ausgaben", "K100", "K200", "K300"])
    end
  end

  it "shows 2028 when picked in the column menu" do
    get :index, params: {c: "nr,25,26,27,28,ges"}
    expect(controller.send(:budget_rows).state.visible_column_keys)
      .to eq(%w[number year_2025 year_2026 year_2027 year_2028 total])
  end

  describe "the page" do
    render_views

    # The detail is the one thing the view decides about the rows.
    it "opens a cost center's detail from its row, and none from the sum row" do
      get :index

      doc = Nokogiri::HTML(response.body)
      aggregate_failures do
        expect(doc.at_css("turbo-frame#bkframe-budget_cost_center-K100")["src"]).to start_with(cost_center_path("K100"))
        expect(doc.at_css("tr.fin-budget-sum-row")["aria-controls"]).to be_nil
      end
    end
  end
end
