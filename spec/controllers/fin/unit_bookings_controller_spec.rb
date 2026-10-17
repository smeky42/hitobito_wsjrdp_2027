# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Abstimmung page "Unit-Buchungen": the figures, the bookings table -- the
# open bookings first, its Schnellauswahl lifting the pins -- and the bar of
# bulk actions (count against the Unit-Budget, set or take off a secondary cost
# center), each action previewing what it changes.
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

  # The ids of the table's rows, from the lazy detail frames.
  def row_ids = response.body.scan(/bkframe-ub-(\d+)/).flatten.map(&:to_i).uniq

  def tiles = doc.css("#main .border.rounded.p-3").map { |tile| tile.css("div").first(2).map { |d| d.text.strip } }

  def preview_doc = Nokogiri::HTML.fragment(response.body)

  def preset_href(label) = doc.css(".flt-presets a").find { |a| a.text.squish == label }&.[]("href")

  context "as the write tier" do
    before { sign_in(accountant) }

    it "states the figures and lists the open bookings with their proposal" do
      get :index

      expect(response).to be_successful
      expect(tiles).to eq([["7", "für Units sichtbar"], ["1", "zählen zum Unit-Budget"],
        ["2", "mit sekundärer Kostenstelle"], ["4", "offen"]])
      expect(row_ids).to contain_exactly(open_oepnv.id, open_oepnv_2.id, open_km.id, refund.id)
      proposals = doc.css("td[data-colkey='proposal']").map { |td| td.text.strip }
      expect(proposals).to all(eq("3810 Unit Treffen Reisekosten"))
      expect(doc.css("thead th[data-colkey]").pluck("data-colkey"))
        .to eq(%w[booking_date signed_base_amount posting_text cost_center_number secondary_cost_center_number
          account_number proposal])
    end

    it "switches the three questions, shows the bookings with a secondary cost center, and goes back to Standard" do
      get :index
      # "alle" / "egal" is the asterisk, its word the tooltip.
      segments = doc.css(".flt-presets .flt-segment").map { |segment|
        segment.css("a").map { |a| a.text.squish.presence || a["title"] }
      }
      expect(segments).to eq([["alle", "Unit-KSt", "Unit-KSt primär oder sekundär"],
        ["egal", "leer", "hat Wert"], ["egal", "nein", "ja"]])
      expect(doc.css(".flt-segment a.flt-preset-icon-only i.fa-asterisk").size).to eq(3)
      expect(doc.css(".flt-presets .flt-group-label").map(&:text)).to eq(["KSt", "Sek KSt", "Unit-Budget?"])
      expect(doc.css(".flt-segment a[aria-pressed=true]").map { |a| a.text.squish }).to eq(%w[Unit-KSt leer nein])
      # The switches say what is shown: their conditions are no chips, neither in the
      # filter line nor in the builder.
      expect(doc.css(".flt-chip-locked")).to be_empty
      expect(JSON.parse(doc.at_css(".flt-root")["data-locked"])).to eq([])
      expect(preset_href("Standard")).to be_nil

      get :index, params: {ubu: "ub.any"}
      expect(row_ids).to contain_exactly(open_oepnv.id, open_oepnv_2.id, open_km.id, refund.id, unit_budget.id)
      expect(preset_href("Standard")).to be_present

      get :index, params: {ubu: "ub.yes"}
      expect(row_ids).to eq([unit_budget.id])

      # "Unit-KSt primär oder sekundär", "hat Wert" and "nein": the bookings with a secondary cost center.
      get :index, params: {ubu: "kst.unit_any,cc2.set"}
      expect(row_ids).to contain_exactly(assigned.id, assigned_unit.id)
      expect(doc.css(".flt-segment a[aria-pressed=true]").map { |a| a.text.squish })
        .to eq(["Unit-KSt primär oder sekundär", "hat Wert", "nein"])
      expect(doc.css(".flt-applied .flt-chip")).to be_empty

      # A position the declaration does not offer cannot be chosen by hand.
      get :index, params: {ubu: "kst.bogus"}
      expect(row_ids.size).to eq(4)
    end

    it "offers the bar with its three actions, the cost center preset to 3810, the quick-select and the switch" do
      get :index

      form = doc.at_css("form#ub-bulk.bk-bulk-box")
      expect(form["action"]).to eq(bulk_reconciliation_unit_bookings_path)
      expect(form["data-preview-url"]).to eq(bulk_preview_reconciliation_unit_bookings_path)
      expect(form.css("[data-bulk-action]").pluck("data-bulk-action").uniq)
        .to eq(%w[unit_budget secondary_cost_center clear])
      select = form.at_css("select[name='secondary_cost_center_number'][data-bulk-param-for=secondary_cost_center]")
      expect(select.at_css("option[selected]")["value"]).to eq("3810")
      expect(select.css("option").pluck("value")).to include("3800")
      expect(select.css("option").pluck("value")).not_to include("U1")
      expect(doc.css(".bk-bulk-quick button").map { |b| b.text.squish })
        .to eq(["Keine", "Alle (4)", "Konto 66630 Reisekosten ÖPNV", "nur (2)",
          "Gegenkto 66680 Kilometergeld", "nur (1)", "Konto 66680 Kilometergeld", "nur (1)"])
      expect(form["data-k66630-count"]).to eq("2")
      expect(form["data-all-count"]).to eq("4")
      expect(doc.css("input.bk-select-check").pluck("form")).to all(eq("ub-bulk"))
      expect(doc.at_css(".bk-bulk-status .bk-only-selected-toggle")["data-form"]).to eq("ub-bulk")
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

      it "previews the bookings it marks with their answer so far, the central one apart with a warning" do
        open_km.update_columns(is_unit_budget: true)
        post :bulk_preview, params: {bulk_action: "unit_budget", ubu: "kst.all,cc2.any,ub.any",
                                     booking_ids: [open_oepnv.id, unit_budget.id, assigned.id, open_km.id]}

        html = preview_doc
        expect(html.at_css(".bk-bulk-preview-head").text.squish).to eq("Betrifft 2 Buchungen")
        list = html.css(".bk-bulk-preview-list").first
        expect(list.css("thead th").last.text).to eq("Bisher")
        expect(list.css("tbody tr td:last-child").map { |td| td.text.squish })
          .to contain_exactly("nein (automatisch, Konto 66630)", "ja (automatisch, Konto 66500)")
        warning = html.at_css(".alert-warning")
        expect(warning.text).to include("1 mit einer primären Kostenstelle, die keine Unit-Kostenstelle ist")
        expect(warning.css("tbody tr").size).to eq(1)
        expect(html.text).to include("1 sind schon als Unit-Budget markiert.")
      end
    end

    describe "Sekundäre Kostenstelle setzen" do
      it "sets it on every selected booking, replacing another one" do
        post :bulk, params: {bulk_action: "secondary_cost_center", secondary_cost_center_number: "3800",
                             ubu: "cc2.any", booking_ids: [open_oepnv.id, assigned_unit.id]}

        expect(flash[:notice]).to eq("2 Buchungen: sekundäre Kostenstelle 3800 UL-Team-Wochenende gesetzt.")
        expect([open_oepnv, assigned_unit].map { |b| b.reload.secondary_cost_center_number }).to eq(%w[3800 3800])
      end

      it "sets it on every booking of the current filter with select_all=1, and on the chosen atoms" do
        post :bulk, params: {bulk_action: "secondary_cost_center", select_all: "1",
                             secondary_cost_center_number: "3800", ubf: "!(!(!(k,in,'66630')))"}
        expect([open_oepnv, open_oepnv_2].map { |b| b.reload.secondary_cost_center_number }).to eq(%w[3800 3800])
        expect(open_km.reload.secondary_cost_center_number).to be_nil
        expect(response).to redirect_to(reconciliation_unit_bookings_path(ubf: "!(!(!(k,in,'66630')))"))

        post :bulk, params: {bulk_action: "secondary_cost_center", select_all: "g66680,k66680",
                             secondary_cost_center_number: "3810"}
        expect([open_km, refund].map { |b| b.reload.secondary_cost_center_number }).to eq(%w[3810 3810])
      end

      it "previews what changes, the bookings carrying it already apart" do
        post :bulk_preview, params: {bulk_action: "secondary_cost_center", secondary_cost_center_number: "3810",
                                     ubu: "cc2.any", booking_ids: [open_oepnv.id, assigned_unit.id]}

        html = preview_doc
        expect(html.at_css(".bk-bulk-preview-head").text.squish).to eq("Betrifft 1 Buchung")
        expect(html.css(".bk-bulk-preview-list tbody td:last-child").map(&:text)).to eq(["— → 3810"])
        expect(html.text).to include("1 haben schon 3810 Unit Treffen Reisekosten.")
      end

      it "refuses a unit's cost center and an unknown one, changing nothing" do
        post :bulk, params: {bulk_action: "secondary_cost_center", booking_ids: [open_oepnv.id],
                             secondary_cost_center_number: "U1"}
        expect(flash[:alert]).to include("U1")

        post :bulk, params: {bulk_action: "secondary_cost_center", booking_ids: [open_oepnv.id],
                             secondary_cost_center_number: "0000"}
        expect(flash[:alert]).to include("0000")
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

      it "previews only the bookings with one, and which one goes" do
        post :bulk_preview, params: {bulk_action: "clear", ubu: "cc2.any",
                                     booking_ids: [assigned_unit.id, open_oepnv.id]}

        html = preview_doc
        expect(html.at_css(".bk-bulk-preview-head").text.squish).to eq("Betrifft 1 Buchung")
        expect(html.css(".bk-bulk-preview-list thead th").last.text).to eq("Sekundäre Kostenstelle (wird gelöscht)")
        expect(html.css(".bk-bulk-preview-list tbody td:last-child").map(&:text).join).to include("3810")
        expect(html.text).to include("1 ohne sekundäre Kostenstelle bleiben unverändert.")
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

    it "is a tab of the Abstimmung area" do
      get :index

      expect(doc.css(".nav-tabs a, ul.nav a").map { |a| a.text.strip }).to include("TN-Beiträge", "Unit-Buchungen")
    end
  end

  context "as the read tier" do
    before { sign_in(reader) }

    it "reads the page without checkboxes or bar" do
      get :index

      expect(response).to be_successful
      expect(row_ids.size).to eq(4)
      expect(doc.at_css(".bk-bulk-box")).to be_nil
      expect(doc.css("input.bk-select-check")).to be_empty
    end

    it "may run no bulk action" do
      expect do
        post :bulk, params: {bulk_action: "secondary_cost_center", booking_ids: [open_oepnv.id],
                             secondary_cost_center_number: "3810"}
      end.to raise_error(CanCan::AccessDenied)
      expect { post :bulk, params: {bulk_action: "unit_budget", booking_ids: [open_oepnv.id]} }
        .to raise_error(CanCan::AccessDenied)
      expect { post :bulk_preview, params: {select_all: "1"} }.to raise_error(CanCan::AccessDenied)
      expect(open_oepnv.reload.is_unit_budget).to be_nil
    end
  end
end
