# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Abstimmung page "Unit-Buchungen": the figures, the open bookings with their
# quick-select and the bulk assignment, the lazily loaded assigned bookings.
# Invented numbers, names and amounts.
describe Fin::UnitBookingsController do
  render_views

  let(:accountant) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let(:reader) { Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person }

  def book(amount, primary:, secondary: nil, konto: "66630")
    DatevBooking.create!(buchungs_guid: SecureRandom.uuid,
      account_number: konto, account_kind: "EXPENSE",
      offsetting_account_number: "700000", offsetting_account_kind: "CREDITOR",
      cost_center_number: primary, secondary_cost_center_number: secondary,
      base_amount: amount, transaction_amount: amount, debit_credit: "C",
      base_currency: "EUR", booking_date: Date.new(2026, 5, 1),
      posting_text: "Test #{konto} #{primary}")
  end

  before do
    WsjrdpCostCenter.create!(number: "U1", name: "Unit U1", is_unit_cost_center: true)
    WsjrdpCostCenter.create!(number: "3810", name: "Unit Treffen Reisekosten")
    WsjrdpCostCenter.create!(number: "3800", name: "UL-Team-Wochenende")
    WsjrdpLedgerAccount.create!(number: "66500", name: "Verpflegung", is_unit_budget: true)
    WsjrdpLedgerAccount.create!(number: "66630", name: "Reisekosten ÖPNV", is_unit_budget: false)
    WsjrdpLedgerAccount.create!(number: "66680", name: "Kilometergeld", is_unit_budget: false)
  end

  let!(:unit_budget) { book(100, primary: "U1", konto: "66500") }
  let!(:open_oepnv) { book(30, primary: "U1") }
  let!(:open_oepnv_2) { book(10, primary: "U1") }
  let!(:open_km) { book(20, primary: "U1", konto: "66680") }
  let!(:assigned) { book(70, primary: "3800", secondary: "U1", konto: "66500") }
  let!(:assigned_unit) { book(15, primary: "U1", secondary: "3810") }
  # A refund paid from the bank account: the Gegenkonto alone keeps it out.
  let!(:refund) do
    DatevBooking.create!(buchungs_guid: SecureRandom.uuid,
      account_number: "18000", account_kind: "BANK",
      offsetting_account_number: "66680", offsetting_account_kind: "EXPENSE",
      cost_center_number: "U1", base_amount: 12, transaction_amount: 12, debit_credit: "C",
      base_currency: "EUR", booking_date: Date.new(2026, 5, 2), posting_text: "RK")
  end

  def doc = Nokogiri::HTML(response.body)

  # The ids of the open table's rows, from the lazy detail frames.
  def open_row_ids = response.body.scan(/bkframe-ub-(\d+)/).flatten.map(&:to_i).uniq

  def tiles = doc.css("#main .border.rounded.p-3").map { |tile| tile.css("div").first(2).map { |d| d.text.strip } }

  context "as the write tier" do
    before { sign_in(accountant) }

    it "states the figures and lists the open bookings with their proposal" do
      get :index

      expect(response).to be_successful
      expect(tiles).to eq([["7", "für Units sichtbar"], ["1", "zählen zum Unit-Budget"],
        ["2", "mit sekundärer Kostenstelle"], ["4", "offen"]])
      expect(open_row_ids).to contain_exactly(open_oepnv.id, open_oepnv_2.id, open_km.id, refund.id)
      proposals = doc.css("td[data-colkey='proposal']").map { |td| td.text.strip }
      expect(proposals).to all(eq("3810 Unit Treffen Reisekosten"))
      # The Unit-Budget column ("nein" on every row) is offered, not shown.
      # (The assigned section's frame is lazy: the page carries only its placeholder.)
      expect(doc.css("thead th[data-colkey]").pluck("data-colkey"))
        .to eq(%w[booking_date signed_base_amount posting_text cost_center_number account_number proposal])
    end

    it "offers the assign form, preset to 3810, the quick-select by deciding account and the switch" do
      get :index

      select = doc.at_css("select[name='secondary_cost_center_number']")
      expect(select.at_css("option[selected]")["value"]).to eq("3810")
      expect(select.css("option").pluck("value")).to include("3800")
      expect(select.css("option").pluck("value")).not_to include("U1")
      buttons = doc.css(".ub-select").map { |b| b.text.strip }
      expect(buttons).to eq(["Keine", "Alle (4)", "Konto 66630 Reisekosten ÖPNV", "nur (2)",
        "Gegenkto 66680 Kilometergeld", "nur (1)", "Konto 66680 Kilometergeld", "nur (1)"])
      form = doc.at_css("form#ub-assign-form")
      expect(form["data-k66630-count"]).to eq("2")
      expect(form["data-all-count"]).to eq("4")
      expect(form["data-turbo-frame"]).to eq("_top")
      expect(form["data-hint-many"]).to eq("Setzt %{target} als sekundäre Kostenstelle bei %{count} ausgewählten Buchungen")
      expect(form.at_css("button[type=submit]")["disabled"]).to be_present
      expect(form.at_css(".ub-selection-hint")).to be_present
      expect(doc.css("#main .exp-toolbar-below-filter .text-muted.small").map(&:text).join).not_to include("Summe (gefiltert)")
      expect(doc.css("input.bk-select-check").pluck("data-atom"))
        .to contain_exactly("k66630", "k66630", "k66680", "g66680")
      expect(doc.at_css(".bk-only-selected-toggle")["data-form"]).to eq("ub-assign-form")
    end

    it "assigns the posted bookings and comes back with the count" do
      post :assign, params: {booking_ids: [open_oepnv.id, unit_budget.id], secondary_cost_center_number: "3810"}

      expect(response).to redirect_to(reconciliation_unit_bookings_path)
      expect(flash[:notice]).to eq("1 Buchungen: sekundäre Kostenstelle 3810 Unit Treffen Reisekosten gesetzt.")
      expect(open_oepnv.reload.secondary_cost_center_number).to eq("3810")
      expect(unit_budget.reload.secondary_cost_center_number).to be_nil
    end

    it "assigns every open booking of the current filter with select_all=1, keeping both views" do
      post :assign, params: {select_all: "1", secondary_cost_center_number: "3800",
                             ubf: "!(!(!(k,in,'66630')))", uaf: "!(!(!(cc2,in,'3810')))"}

      expect(flash[:notice]).to start_with("2 Buchungen")
      expect([open_oepnv, open_oepnv_2].map { |b| b.reload.secondary_cost_center_number }).to eq(%w[3800 3800])
      expect(open_km.reload.secondary_cost_center_number).to be_nil
      expect(refund.reload.secondary_cost_center_number).to be_nil
      expect(response).to redirect_to(reconciliation_unit_bookings_path(ubf: "!(!(!(k,in,'66630')))",
        uaf: "!(!(!(cc2,in,'3810')))"))
    end

    it "narrows the open list by cost center, which the filter offers" do
      WsjrdpCostCenter.create!(number: "U2", name: "Unit U2", is_unit_cost_center: true)
      other = book(5, primary: "U2")
      get :index, params: {ubf: "!(!(!(cc,in,'U2')))"}

      expect(open_row_ids).to eq([other.id])
      expect(doc.at_css("form#ub-assign-form")["data-all-count"]).to eq("1")
    end

    it "assigns the bookings of the chosen atoms with select_all=<atoms>" do
      post :assign, params: {select_all: "g66680,k66680", secondary_cost_center_number: "3810"}

      expect(open_km.reload.secondary_cost_center_number).to eq("3810")
      expect(refund.reload.secondary_cost_center_number).to eq("3810")
      expect(open_oepnv.reload.secondary_cost_center_number).to be_nil
    end

    # The selection and nothing else: the posted ids, the chosen atoms, or
    # every assigned booking with select_all=1 -- never the open ones.
    it "takes the secondary cost center off the selected assigned bookings" do
      post :clear, params: {booking_ids: [assigned.id, open_oepnv.id]}

      expect(response).to redirect_to(reconciliation_unit_bookings_path)
      expect(flash[:notice]).to eq("1 Buchungen: sekundäre Kostenstelle gelöscht.")
      expect(assigned.reload.secondary_cost_center_number).to be_nil
      expect(assigned_unit.reload.secondary_cost_center_number).to eq("3810")

      post :clear, params: {select_all: "3810"}
      expect(assigned_unit.reload.secondary_cost_center_number).to be_nil
    end

    it "clears every assigned booking of the frame's filter with select_all=1, carrying both views" do
      post :clear, params: {select_all: "1", ubf: "!(!(!(k,in,'66630')))", uaf: "!(!(!(cc2,in,'3810')))"}

      expect(response).to redirect_to(reconciliation_unit_bookings_path(ubf: "!(!(!(k,in,'66630')))",
        uaf: "!(!(!(cc2,in,'3810')))"))
      expect(flash[:notice]).to eq("1 Buchungen: sekundäre Kostenstelle gelöscht.")
      expect(assigned_unit.reload.secondary_cost_center_number).to be_nil
      expect(assigned.reload.secondary_cost_center_number).to eq("U1")
      expect(open_oepnv.reload.secondary_cost_center_number).to be_nil

      post :clear, params: {select_all: "1"}
      expect(DatevBooking.where.not(secondary_cost_center_number: nil).count).to eq(0)
    end

    it "refuses a unit's cost center and an unknown one, changing nothing" do
      post :assign, params: {booking_ids: [open_oepnv.id], secondary_cost_center_number: "U1"}
      expect(flash[:alert]).to include("U1")

      post :assign, params: {booking_ids: [open_oepnv.id], secondary_cost_center_number: "0000"}
      expect(flash[:alert]).to include("0000")
      expect(open_oepnv.reload.secondary_cost_center_number).to be_nil
    end

    it "says so when nothing is selected" do
      post :assign, params: {secondary_cost_center_number: "3810"}
      expect(flash[:alert]).to eq("Keine Buchungen ausgewählt.")
    end

    it "serves the assigned bookings as the frame the collapsed section loads" do
      request.headers["Turbo-Frame"] = "unit_bookings_assigned"
      get :assigned

      expect(response).to be_successful
      expect(response.body).not_to include("<html")
      expect(doc.at_css("turbo-frame#unit_bookings_assigned")).to be_present
      expect(response.body.scan(/bkframe-ua-(\d+)/).flatten.map(&:to_i).uniq)
        .to contain_exactly(assigned.id, assigned_unit.id)
      form = doc.at_css("form#ua-clear-form")
      expect(form["action"]).to eq(clear_reconciliation_unit_bookings_path)
      expect(form["data-hint-many"]).to eq("Löscht die sekundäre Kostenstelle bei %{count} ausgewählten Buchungen")
      expect(form.at_css("button[type=submit]")["disabled"]).to be_present
      expect(form.at_css(".ub-selection-hint")).to be_present
      expect(doc.css("turbo-frame#unit_bookings_assigned thead th[data-colkey]").pluck("data-colkey"))
        .to eq(%w[booking_date signed_base_amount posting_text cost_center_number secondary_cost_center_number
          account_number])
      expect(doc.at_css("turbo-frame#unit_bookings_assigned .flt-line")).to be_present
      expect(doc.at_css("turbo-frame#unit_bookings_assigned .pane-toggle")).to be_present
      expect(doc.css("turbo-frame#unit_bookings_assigned .text-muted.small").map(&:text).join).not_to include("Summe (gefiltert)")
      expect(doc.css(".ub-select").map { |b| b.text.strip })
        .to eq(["Keine", "Alle (2)", "3800 UL-Team-Wochenende", "nur (1)", "3810 Unit Treffen Reisekosten", "nur (1)"])
      expect(doc.css("input.bk-select-check").pluck("data-atom")).to contain_exactly("3800", "3810")
      expect(doc.at_css(".bk-only-selected-toggle")["data-form"]).to eq("ua-clear-form")
    end

    it "is a tab of the Abstimmung area, and the page carries the lazy frame with the frame's view" do
      get :index, params: {uaf: "!(!(!(cc2,in,'3810')))"}

      expect(doc.css(".nav-tabs a, ul.nav a").map { |a| a.text.strip }).to include("TN-Beiträge", "Unit-Buchungen")
      frame = doc.at_css("turbo-frame#unit_bookings_assigned")
      expect(frame["src"]).to eq(assigned_reconciliation_unit_bookings_path(uaf: "!(!(!(cc2,in,'3810')))"))
      expect(frame["loading"]).to eq("lazy")
      expect(doc.at_css('[data-bs-target="#ub-assigned"]').text.squish)
        .to eq("Unit-Buchungen mit sekundärer Kostenstelle, die nicht zum Unit-Budget zählen")
    end

    # The frame's filter: its apply comes back to the frame, and the frame's
    # clear form carries the filter back to the page.
    it "filters the assigned bookings inside the frame" do
      post :apply_assigned, params: {filter_json: [[["secondary_cost_center", "in", "3810"]]].to_json}
      location = URI.parse(response.location)
      expect(location.path).to eq(assigned_reconciliation_unit_bookings_path)
      expect(CGI.unescape(location.query)).to eq("uaf=!(!(!(cc2,in,'3810')))")

      request.headers["Turbo-Frame"] = "unit_bookings_assigned"
      get :assigned, params: {uaf: "!(!(!(cc2,in,'3810')))"}

      expect(response.body.scan(/bkframe-ua-(\d+)/).flatten.map(&:to_i).uniq).to eq([assigned_unit.id])
      expect(doc.at_css("form#ua-clear-form")["action"])
        .to eq(clear_reconciliation_unit_bookings_path(uaf: "!(!(!(cc2,in,'3810')))"))
      expect(doc.at_css("form#ua-clear-form")["data-all-count"]).to eq("1")
    end
  end

  context "as the read tier" do
    before { sign_in(reader) }

    it "reads the page and the section without checkboxes or forms" do
      get :index

      expect(response).to be_successful
      expect(open_row_ids.size).to eq(4)
      expect(doc.at_css("form#ub-assign-form")).to be_nil
      expect(doc.css("input.bk-select-check")).to be_empty

      request.headers["Turbo-Frame"] = "unit_bookings_assigned"
      get :assigned
      expect(doc.at_css("form#ua-clear-form")).to be_nil
      expect(doc.css("input.bk-select-check")).to be_empty
    end

    it "may neither assign nor clear" do
      expect do
        post :assign, params: {booking_ids: [open_oepnv.id], secondary_cost_center_number: "3810"}
      end.to raise_error(CanCan::AccessDenied)
      expect { post :clear, params: {booking_ids: [assigned.id]} }.to raise_error(CanCan::AccessDenied)
      expect(open_oepnv.reload.secondary_cost_center_number).to be_nil
      expect(assigned.reload.secondary_cost_center_number).to eq("U1")
    end
  end
end
