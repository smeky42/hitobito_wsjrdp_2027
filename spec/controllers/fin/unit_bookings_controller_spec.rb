# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Abstimmung page "Unit-Buchungen": the bookings table -- the open bookings
# first, its Schnellauswahl lifting the pins -- and the bar of bulk actions
# (count against the Unit-Budget, set or take off a secondary cost center),
# each action previewing what it changes.
# Invented numbers, names and amounts.
describe Fin::UnitBookingsController do
  before_all(setup_fixtures: true) {}

  let_it_be(:accountant) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let_it_be(:reader) { Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person }

  def book(amount, primary:, secondary: nil, konto: "66630")
    DatevBooking.create!(buchungs_guid: SecureRandom.uuid,
      account_number: konto, account_kind: "EXPENSE",
      offsetting_account_number: "700000", offsetting_account_kind: "CREDITOR",
      cost_center_number: primary, secondary_cost_center_number: secondary,
      base_amount: amount, transaction_amount: amount, debit_credit: "C",
      base_currency: "EUR", booking_date: Date.new(2026, 5, 1),
      posting_text: "Test #{konto} #{primary}")
  end

  before_all do
    WsjrdpCostCenter.create!(number: "U1", name: "Unit U1", is_unit_cost_center: true)
    WsjrdpCostCenter.create!(number: "3810", name: "Unit Treffen Reisekosten")
    WsjrdpCostCenter.create!(number: "3800", name: "UL-Team-Wochenende")
    WsjrdpLedgerAccount.create!(number: "66500", name: "Verpflegung", is_unit_budget: true)
    WsjrdpLedgerAccount.create!(number: "66630", name: "Reisekosten ÖPNV", is_unit_budget: false)
    WsjrdpLedgerAccount.create!(number: "66680", name: "Kilometergeld", is_unit_budget: false)
  end

  let_it_be(:unit_budget, refind: true) { book(100, primary: "U1", konto: "66500") }
  let_it_be(:open_oepnv, refind: true) { book(30, primary: "U1") }
  let_it_be(:open_oepnv_2, refind: true) { book(10, primary: "U1") }
  let_it_be(:open_km, refind: true) { book(20, primary: "U1", konto: "66680") }
  let_it_be(:assigned, refind: true) { book(70, primary: "3800", secondary: "U1", konto: "66500") }
  let_it_be(:assigned_unit, refind: true) { book(15, primary: "U1", secondary: "3810") }
  # A refund paid from the bank account: the Gegenkonto alone keeps it out.
  let_it_be(:refund, refind: true) do
    DatevBooking.create!(buchungs_guid: SecureRandom.uuid,
      account_number: "18000", account_kind: "BANK",
      offsetting_account_number: "66680", offsetting_account_kind: "EXPENSE",
      cost_center_number: "U1", base_amount: 12, transaction_amount: 12, debit_credit: "C",
      base_currency: "EUR", booking_date: Date.new(2026, 5, 2), posting_text: "RK")
  end

  let(:open_ids) { [open_oepnv.id, open_oepnv_2.id, open_km.id, refund.id] }

  def row_ids = controller.send(:bookings).page.map(&:id)

  context "as the write tier" do
    before { sign_in(accountant) }

    describe "GET index" do
      it "lifts the Unit-Budget pin with 'egal'" do
        get :index, params: {ubu: "ub.any"}

        expect(row_ids).to match_array(open_ids + [unit_budget.id])
      end

      it "shows the bookings counting against the Unit-Budget with 'ja'" do
        get :index, params: {ubu: "ub.yes"}

        expect(row_ids).to eq([unit_budget.id])
      end

      it "shows the bookings with a secondary cost center, on a unit's either way" do
        get :index, params: {ubu: "kst.unit_any,cc2.set"}

        expect(row_ids).to contain_exactly(assigned.id, assigned_unit.id)
      end

      it "ignores a position the declaration does not offer" do
        get :index, params: {ubu: "kst.bogus"}

        expect(row_ids).to match_array(open_ids)
      end
    end

    describe "rendered" do
      render_views

      def doc = Nokogiri::HTML(response.body)

      def preview = Nokogiri::HTML.fragment(response.body)

      def preview_rows = preview.css(".bk-bulk-preview-list").first.css("tbody tr td:last-child").map { |td| td.text.squish }

      it "lists the open bookings and offers the bar, the cost center preset to the proposal, a unit's own " \
         "not offered", :aggregate_failures do
        get :index

        expect(row_ids).to match_array(open_ids)
        form = doc.at_css("form#ub-bulk")
        select = form.at_css("select[name='secondary_cost_center_number']")
        expect(select.at_css("option[selected]")["value"]).to eq("3810")
        expect(select.css("option").pluck("value")).to include("3800")
        expect(select.css("option").pluck("value")).not_to include("U1")
        expect(doc.css("input.bk-select-check").pluck("form")).to all(eq("ub-bulk"))
      end

      it "previews the bookings it marks with their answer so far, the central one apart, the marked ones counted" do
        open_km.update_columns(is_unit_budget: true)

        post :bulk_preview, params: {bulk_action: "unit_budget", ubu: "kst.all,cc2.any,ub.any",
                                     booking_ids: [open_oepnv.id, unit_budget.id, assigned.id, open_km.id]}

        expect(preview_rows).to contain_exactly("nein (automatisch, Konto 66630)", "ja (automatisch, Konto 66500)")
        expect(preview.at_css(".alert-warning").css("tbody tr").size).to eq(1)
        expect(preview.text).to include("1 sind schon als Unit-Budget markiert.")
      end

      it "previews the secondary cost center it sets, the bookings carrying it already apart" do
        post :bulk_preview, params: {bulk_action: "secondary_cost_center", secondary_cost_center_number: "3810",
                                     ubu: "cc2.any", booking_ids: [open_oepnv.id, assigned_unit.id]}

        expect(preview_rows).to eq(["— → 3810"])
        expect(preview.text).to include("1 haben schon 3810 Unit Treffen Reisekosten.")
      end

      it "previews only the bookings with a secondary cost center for clearing, and which one goes" do
        post :bulk_preview, params: {bulk_action: "clear", ubu: "cc2.any",
                                     booking_ids: [assigned_unit.id, open_oepnv.id]}

        expect(preview_rows.join).to include("3810")
        expect(preview.text).to include("1 ohne sekundäre Kostenstelle bleiben unverändert.")
      end
    end

    describe "Als Unit-Budget markieren" do
      it "marks the selected bookings on a unit's cost center and leaves a central one alone" do
        post :bulk, params: {bulk_action: "unit_budget", ubu: "kst.all,cc2.any,ub.any",
                             booking_ids: [open_oepnv.id, assigned_unit.id, assigned.id]}

        expect(flash[:notice]).to eq("2 Buchungen: als Unit-Budget markiert.")
        expect(open_oepnv.reload.is_unit_budget).to be(true)
        expect(assigned_unit.reload.is_unit_budget).to be(true)
        expect(assigned.reload.is_unit_budget).to be_nil
        expect(response).to redirect_to(reconciliation_unit_bookings_path(ubu: "kst.all,cc2.any,ub.any"))
      end
    end

    describe "Sekundäre Kostenstelle setzen" do
      it "sets it on every selected booking, replacing another one" do
        post :bulk, params: {bulk_action: "secondary_cost_center", secondary_cost_center_number: "3800",
                             ubu: "cc2.any", booking_ids: [open_oepnv.id, assigned_unit.id]}

        expect(flash[:notice]).to eq("2 Buchungen: sekundäre Kostenstelle 3800 UL-Team-Wochenende gesetzt.")
        expect([open_oepnv, assigned_unit].map { |b| b.reload.secondary_cost_center_number }).to eq(%w[3800 3800])
      end

      it "sets it on every booking of the current filter with select_all=1" do
        post :bulk, params: {bulk_action: "secondary_cost_center", select_all: "1",
                             secondary_cost_center_number: "3800", ubf: "!(!(!(k,in,'66630')))"}

        expect([open_oepnv, open_oepnv_2].map { |b| b.reload.secondary_cost_center_number }).to eq(%w[3800 3800])
        expect(open_km.reload.secondary_cost_center_number).to be_nil
        expect(response).to redirect_to(reconciliation_unit_bookings_path(ubf: "!(!(!(k,in,'66630')))"))
      end

      it "sets it on the bookings of the chosen quick-select atoms" do
        post :bulk, params: {bulk_action: "secondary_cost_center", select_all: "g66680,k66680",
                             secondary_cost_center_number: "3810"}

        expect([open_km, refund].map { |b| b.reload.secondary_cost_center_number }).to eq(%w[3810 3810])
        expect(open_oepnv.reload.secondary_cost_center_number).to be_nil
      end

      it "refuses a unit's cost center, changing nothing" do
        post :bulk, params: {bulk_action: "secondary_cost_center", booking_ids: [open_oepnv.id],
                             secondary_cost_center_number: "U1"}

        expect(flash[:alert]).to include("U1")
        expect(open_oepnv.reload.secondary_cost_center_number).to be_nil
      end
    end

    describe "Sekundäre Kostenstelle löschen" do
      it "takes it off the selected bookings that carry one" do
        post :bulk, params: {bulk_action: "clear", ubu: "kst.all,cc2.any",
                             booking_ids: [assigned.id, assigned_unit.id, open_oepnv.id]}

        expect(flash[:notice]).to eq("2 Buchungen: sekundäre Kostenstelle gelöscht.")
        expect([assigned, assigned_unit].map { |b| b.reload.secondary_cost_center_number }).to eq([nil, nil])
      end

      it "says so when none of the selected bookings carries one" do
        post :bulk, params: {bulk_action: "clear", booking_ids: [open_oepnv.id]}

        expect(flash[:alert]).to eq("Keine der ausgewählten Buchungen ist betroffen.")
      end
    end

    it "says so when nothing is selected" do
      post :bulk, params: {bulk_action: "secondary_cost_center", secondary_cost_center_number: "3810"}

      expect(flash[:alert]).to eq("Keine Buchungen ausgewählt.")
    end
  end

  context "as the read tier" do
    before { sign_in(reader) }

    describe "rendered" do
      render_views

      it "reads the page without checkboxes or bar" do
        get :index

        doc = Nokogiri::HTML(response.body)
        expect(doc.at_css(".bk-bulk-box")).to be_nil
        expect(doc.css("input.bk-select-check")).to be_empty
      end
    end

    it "may run no bulk action" do
      expect { post :bulk, params: {bulk_action: "unit_budget", booking_ids: [open_oepnv.id]} }
        .to raise_error(CanCan::AccessDenied)
      expect { post :bulk_preview, params: {select_all: "1"} }.to raise_error(CanCan::AccessDenied)
      expect(open_oepnv.reload.is_unit_budget).to be_nil
    end
  end
end
