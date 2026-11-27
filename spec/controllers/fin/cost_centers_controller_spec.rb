# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Kostenstellen page: the relation-backed Buchhaltung summary with its
# filter, its view and its footer totals, the cost center it pins out, and a
# cost center's detail with its budgets.
describe Fin::CostCentersController do
  before_all(setup_fixtures: true) {}

  let_it_be(:person) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let(:hidden) { described_class::HIDDEN_COST_CENTER_NUMBER }

  # The Konto is a BANK account, so signed_base_amount is +amount for "D" and
  # -amount for "C" (doc/fin/money_conventions.md).
  def create_booking(cost_center_number, amount, debit_credit = "D", **attrs)
    DatevBooking.create!(buchungs_guid: SecureRandom.uuid, account_number: "1200", account_kind: "BANK",
      offsetting_account_number: "66500", offsetting_account_kind: "EXPENSE", cost_center_number: cost_center_number,
      base_amount: amount, transaction_amount: amount, debit_credit: debit_credit, base_currency: "EUR",
      booking_date: Date.new(2026, 2, 1), **attrs)
  end

  # K100 aktiv, sum 30 over 2 bookings; K200 inaktiv, no Kurzbezeichnung, sum
  # 50 over 1; K300 Moss-unknown, no booking. Plus the pinned-out cost center,
  # with a booking the footer would show.
  before_all do
    [["K100", "Alpha", "active"], ["K200", nil, "deactivated"], ["K300", "Gamma kurz", nil],
      [described_class::HIDDEN_COST_CENTER_NUMBER, "PH", "active"]].each do |number, short_name, status|
      WsjrdpCostCenter.create!(number: number, name: "Kostenstelle #{number}", short_name: short_name,
        moss_status: status)
    end
    create_booking("K100", 100)
    create_booking("K100", 70, "C")
    create_booking("K200", 50)
    create_booking(described_class::HIDDEN_COST_CENTER_NUMBER, 500)
  end

  before { sign_in(person) }

  def listed = controller.cost_centers.page.map(&:number)

  def footer = [controller.shown_booking_count, controller.shown_booking_sum]

  def cost_center(number) = WsjrdpCostCenter.find_by(number: number)

  describe "GET index" do
    it "lists every Kostenstelle by number, the pinned one left out of the rows and the footer" do
      get :index

      expect(listed).to eq(%w[K100 K200 K300])
      expect(footer).to eq([3, 80])
    end

    it "narrows by the filter, never to the pinned one, and counts what is left" do
      get :index, params: {f: "!(!(!(ms,in,active)))"}

      expect(listed).to eq(%w[K100])
      expect(footer).to eq([2, 30])
    end

    it "sorts by the sum" do
      get :index, params: {s: "sum"}

      expect(listed).to eq(%w[K300 K100 K200])
    end

    it "sorts by the Kurzbezeichnung, the one without last" do
      get :index, params: {s: "kbz"}

      expect(listed).to eq(%w[K100 K300 K200])
    end

    it "remembers the filter on a bare revisit and clears it on a blank ?f=" do
      get :index, params: {f: "!(!(!(bc,nz)))"}
      expect(listed).to eq(%w[K100 K200])
      get :index
      expect(listed).to eq(%w[K100 K200])

      get :index, params: {f: ""}
      expect(listed).to eq(%w[K100 K200 K300])
    end

    it "remembers the view" do
      get :index, params: {v: "budget"}
      expect(controller.summary_table_state.view).to eq("budget")
      get :index

      expect(controller.summary_table_state.view).to eq("budget")
    end
  end

  describe "POST apply" do
    it "encodes the posted tree into the filter param and redirects (PRG)" do
      post :apply, params: {filter_json: [[["booking_count", "nonzero"]]].to_json}

      expect(response).to have_http_status(:see_other)
      expect(CGI.unescape(response.location)).to end_with("/fin/bookkeeping/cost_centers?f=!(!(!(bc,nz)))")
    end
  end

  describe "GET show" do
    it "shows the Kostenstelle and its bookings, by the view of the list" do
      get :show, params: {number: "K100", v: "any"}

      expect(assigns(:cost_center)).to eq(cost_center("K100"))
      expect(controller.send(:detail_view)).to eq("any")
      expect(controller.send(:cost_center_bookings, cost_center("K100")).total_count).to eq(2)
    end

    it "shows the pinned-out Kostenstelle too" do
      get :show, params: {number: hidden}

      expect(assigns(:cost_center)).to be_persisted
    end

    it "shows a number without master data as a stub record" do
      get :show, params: {number: "K999"}

      expect(assigns(:cost_center)).to be_new_record
    end

    it "answers a list row's frame with the embedded detail" do
      request.headers["Turbo-Frame"] = "bkframe-cost_center-K100"
      get :show, params: {number: "K100", expandable_table_level: "1"}

      expect(assigns(:ctx)).to be_embedded
    end

    describe "the Unit-Budget choice over the bookings" do
      let(:unit_budget_only) do
        query = Wsjrdp::Filtering::Query.parse([[["unit_budget", "in", "true"]]])
        {described_class::ITEM_BOOKINGS_POLICY.param_name(:filter) =>
           Wsjrdp::Filtering::UrlCodec.encode(query, schema: Fin::DatevBookingsFilterSchema.bound)}
      end

      def bookings_of(number) = controller.send(:cost_center_bookings, cost_center(number)).total_count

      it "narrows the bookings of a unit's cost center" do
        cost_center("K300").update!(is_unit_cost_center: true)
        create_booking("K200", 12, "C", secondary_cost_center_number: "K300")
        get :show, params: {number: "K300", v: "any", **unit_budget_only}

        expect(WsjrdpCostCenter.bookings_for("K300", "any").count).to eq(1)
        expect(bookings_of("K300")).to eq(0)
      end

      it "leaves a regular cost center's bookings alone" do
        get :show, params: {number: "K100", **unit_budget_only}

        expect(bookings_of("K100")).to eq(2)
      end
    end
  end

  describe "PATCH update" do
    it "stores budgets typed in German format, and the Unit-Kostenstelle flag" do
      patch :update, params: {number: "K100",
                              wsjrdp_cost_center: {budget_2025: "1.234,56", budget_2026: "2.000", budget_2027: "",
                                                   explicit_total_budget: "99,5", is_unit_cost_center: "true"}}

      expect(response).to redirect_to(cost_center_path("K100"))
      expect(cost_center("K100")).to have_attributes(budget_2025: BigDecimal("1234.56"),
        budget_2026: BigDecimal(2000), budget_2027: nil, explicit_total_budget: BigDecimal("99.5"),
        is_unit_cost_center: true)
    end

    # "1,234.56" is not German; read with String#to_d it would become 1.
    it "keeps a budget it cannot read and shows the edit page again" do
      cost_center("K100").update!(budget_2025: 1000)
      patch :update, params: {number: "K100", wsjrdp_cost_center: {budget_2025: "1,234.56"}}

      expect(response).to have_http_status(422)
      expect(cost_center("K100").budget_2025).to eq(BigDecimal(1000))
      expect(assigns(:cost_center).errors).to include(:budget_2025)
    end
  end
end
