# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# One booking on the group's own route
# (/groups/:group_id/finance/bookkeeping/bookings/:id): the page a row of the
# Buchhaltung tab's table links to, and the pane that table lazy-loads.
#
# Two things are asserted: the SCOPE -- only the bookings of the group's own
# cost centers exist here -- and the FIELD LIST, which keeps the group's view
# out of the bookkeeping internals.
#
# All numbers, names and booking texts invented.
describe Group::BookingsController do
  before_all(setup_fixtures: true) {}

  let_it_be(:auditor) do
    Fabricate(Group::Extern::FinanceAuditor.name.to_sym,
      group: Group::Extern.create!(name: "Extern", parent: groups(:root))).person
  end

  let_it_be(:batch) do
    DatevBookingBatch.create!(consultant_number: "1", client_number: "2",
      label: "Teststapel", period_from: Date.new(2026, 1, 1),
      period_to: Date.new(2026, 1, 31), financial_year_start: Date.new(2026, 1, 1),
      primanota_number: "01-2026/0001", import_export: "import")
  end

  def create_booking(posting_text, cost_center:, secondary: nil)
    DatevBooking.create!(batch: batch, buchungs_guid: SecureRandom.uuid,
      account_number: "1200", account_kind: "BANK",
      offsetting_account_number: "66500", offsetting_account_kind: "EXPENSE",
      cost_center_number: cost_center, secondary_cost_center_number: secondary,
      sphere_number: "S1",
      base_amount: 100, transaction_amount: 100, debit_credit: "D",
      base_currency: "EUR", booking_date: Date.new(2026, 2, 1),
      posting_text: posting_text)
  end

  before_all do
    WsjrdpCostCenter.create!(number: "A1", name: "Kostenstelle A1", is_unit_cost_center: true)
    WsjrdpSubCostCenter.create!(cost_center_number: "A1", number: "X1", name: "Teil X")
    groups(:unit_a).update!(cost_center_numbers: ["A1"])
  end

  let_it_be(:booking, refind: true) { create_booking("Buchung Alpha", cost_center: "A1") }
  let_it_be(:secondary_booking) { create_booking("Buchung Beta", cost_center: "B1", secondary: "A1") }
  let_it_be(:foreign_booking, refind: true) { create_booking("Buchung Gamma", cost_center: "B1") }

  let(:group) { groups(:unit_a) }

  def show(record, **params)
    get(:show, params: {group_id: group.id, id: record.id}.merge(params))
  end

  def edit(record, **params)
    get(:edit, params: {group_id: group.id, id: record.id}.merge(params))
  end

  describe "the scope" do
    before { sign_in(people(:ul_a_1)) }

    # Booked elsewhere, only tagged with the group's cost center as the
    # secondary one -- the same set the table's fixed filter slot pins.
    it "finds a booking reached through the secondary cost center" do
      show(secondary_booking)

      expect(assigns(:booking)).to eq(secondary_booking)
    end

    # Without the scope check every booking id of the contingent would be
    # readable through any group a person may open.
    it "does not find a booking outside the group's cost centers" do
      expect { show(foreign_booking) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "finds nothing at all for a group without cost centers" do
      group.update!(cost_center_numbers: [])

      expect { show(booking) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "does not reach a booking outside the group's cost centers for editing" do
      expect { edit(foreign_booking) }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "permissions" do
    it "refuses a youth participant on their own unit" do
      sign_in(people(:yp_a_1))

      expect { show(booking) }.to raise_error(CanCan::AccessDenied)
    end

    it "refuses the audit tier the edit page" do
      sign_in(auditor)

      expect { edit(booking) }.to raise_error(CanCan::AccessDenied)
    end
  end

  describe "the rendered pages" do
    render_views

    def doc = Nokogiri::HTML(response.body)

    def detail_labels = doc.css("dt").map { |dt| dt.text.strip }

    def detail_cell(label)
      index = detail_labels.index(label)
      index && doc.css("dd")[index]
    end

    def input_names = doc.css("input, select, textarea").pluck("name").compact

    # The layout's quicksearch is a GET form on every page.
    def edit_forms = doc.css("form").reject { |form| form["method"].to_s.casecmp?("get") }

    def link_texts = doc.css("#main a").map { |a| a.text.strip }

    # The sub cost center is the finance team's breakdown and stays off the
    # group's pages, set or not. A ticket key links only for a viewer with :log.
    it "shows the group's fields, none of the internals, and stays on the group's routes" do
      booking.update_columns(sub_cost_center_number: "X1",
        user_comment: "Beleg unter https://example.org/beleg/1 abgelegt, siehe FIN-123")
      sign_in(people(:ul_a_1))

      show(booking)

      expect(detail_labels).to include("Betrag", "Notizen", "Unit-Budget?")
      expect(detail_labels).not_to include("Kommentar", "Sphäre", "Unter-Kostenstelle", "Sekundäre Kostenstelle")
      expect(response.body).not_to include("Verknüpfungen", "Rohdaten", booking.buchungs_guid, "/fin/bookkeeping/")
      expect(input_names).not_to include("datev_booking[user_comment]")
      expect(detail_cell("Notizen").css("a").map(&:text)).to eq(["https://example.org/beleg/1"])
      expect(doc.css("a").find { |a| a.text.strip == "Bearbeiten" }["href"])
        .to eq(group_edit_finance_bookkeeping_booking_path(group, booking))
      expect(link_texts.grep(/\AZurück/)).to be_empty
      expect(doc.css("ul.nav-sub li.active a").pluck("href")).to eq([group_finance_bookkeeping_path(group)] * 2)
    end

    # Lazily loaded out of the Buchhaltung tab's table (prefix "gb"), with the
    # inline toggle of the notes the page splits off into its edit page.
    it "answers the table's frame without a layout, the notes inline editable" do
      sign_in(people(:ul_a_1))
      request.headers["Turbo-Frame"] = "bkframe-gb-#{booking.id}"

      show(booking, expandable_table_level: "1")

      expect(response.body).to include(%(<turbo-frame id="bkframe-gb-#{booking.id}"))
      expect(response.body).not_to include("<html")
      expect(input_names).to include("datev_booking[user_comment]")
    end

    # :show_finance through the audit tier, no :update_finance anywhere.
    it "gives the audit tier a reading view without controls" do
      sign_in(auditor)

      show(booking)

      expect(edit_forms).to be_empty
      expect(response.body).not_to include("datev_booking[user_comment]")
      expect(doc.css("a").map { |a| a.text.strip }).not_to include("Bearbeiten")
    end

    # The fields that move money between cost centers stay with the finance team.
    it "offers the one editable field on the edit page, the others read-only" do
      sign_in(people(:ul_a_1))

      edit(booking)

      expect(input_names).to include("datev_booking[user_comment]")
      expect(input_names).not_to include("datev_booking[sub_cost_center_number]",
        "datev_booking[new_sub_cost_center_number]", "datev_booking[secondary_cost_center_number]",
        "datev_booking[is_unit_budget]")
      expect(detail_labels).to include("Sekundäre Kostenstelle", "Unit-Budget?")
      expect(detail_labels).not_to include("Unter-Kostenstelle")
      expect(doc.css("a").find { |a| a.text.strip == "Abbrechen" }["href"])
        .to eq(group_finance_bookkeeping_booking_path(group, booking))
      expect(link_texts.grep(/\AZurück/)).to be_empty
    end
  end

  describe "PATCH update" do
    def update(record, attrs, **params)
      patch(:update, params: {group_id: group.id, id: record.id, datev_booking: attrs, **params})
    end

    # A field this page does not offer is refused as a WHOLE payload, not
    # silently dropped: the rest is not written either.
    %i[is_unit_budget new_sub_cost_center_number].each do |field|
      it "refuses a payload carrying #{field} and writes nothing" do
        sign_in(people(:ul_a_1))

        expect do
          update(booking, {:user_comment => "für die Unit", field => "X1"})
        end.not_to change(WsjrdpSubCostCenter, :count)

        expect(flash[:alert]).to include("es wurde nichts gespeichert")
        expect(booking.reload.user_comment).to eq("")
        expect(booking.is_unit_budget).to be_nil
        expect(booking.sub_cost_center_number).to be_nil
      end
    end

    it "refuses the audit tier, which may read but not edit" do
      sign_in(auditor)

      expect { update(booking, {user_comment: "x"}) }.to raise_error(CanCan::AccessDenied)
      expect(booking.reload.user_comment).to eq("")
    end

    it "does not reach a booking outside the group's cost centers" do
      sign_in(people(:ul_a_1))

      expect { update(foreign_booking, {user_comment: "x"}) }
        .to raise_error(ActiveRecord::RecordNotFound)
      expect(foreign_booking.reload.user_comment).to eq("")
    end

    # The edit page's second submit comes back to the GROUP's edit route, never
    # to the one under /fin.
    it "stores the comment and comes back to the group's edit page for Speichern und weiter bearbeiten" do
      sign_in(people(:ul_a_1))

      update(booking, {user_comment: "für die Unit"}, stay: "1")

      expect(response).to redirect_to(group_edit_finance_bookkeeping_booking_path(group, booking))
      expect(booking.reload.user_comment).to eq("für die Unit")
    end

    it "goes on to the group's reading page for Speichern" do
      sign_in(people(:ul_a_1))

      update(booking, {user_comment: "für die Unit"}, save: "1")

      expect(response).to redirect_to(group_finance_bookkeeping_booking_path(group, booking))
    end
  end
end
