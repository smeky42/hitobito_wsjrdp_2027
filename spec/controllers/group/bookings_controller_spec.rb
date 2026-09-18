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
# Two things are asserted throughout: the SCOPE -- only the bookings of the
# group's own cost centers exist here -- and the FIELD LIST, which is what keeps
# the group's view out of the bookkeeping internals (the raw DATEV block, the
# Verknüpfungen into /fin, the Sphäre, the GUID and the internal comment).
#
# All numbers, names and booking texts invented.
describe Group::BookingsController do
  render_views

  let(:extern) { Group::Extern.create!(name: "Extern", parent: groups(:root)) }
  let(:auditor) { Fabricate(Group::Extern::FinanceAuditor.name.to_sym, group: extern).person }

  let!(:batch) do
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

  # The unit's OWN cost center, so the Unit-Budget question reaches the accounts
  # instead of being settled by the cost center (doc/fin/unit_budget.md).
  let!(:cost_center) do
    WsjrdpCostCenter.create!(number: "A1", name: "Kostenstelle A1", is_unit_cost_center: true)
  end
  let!(:sub_cost_center) do
    WsjrdpSubCostCenter.create!(cost_center_number: "A1", number: "X1", name: "Teil X")
  end

  let!(:booking) { create_booking("Buchung Alpha", cost_center: "A1") }
  let!(:secondary_booking) { create_booking("Buchung Beta", cost_center: "B1", secondary: "A1") }
  let!(:foreign_booking) { create_booking("Buchung Gamma", cost_center: "B1") }

  let(:group) { groups(:unit_a) }

  before { group.update!(cost_center_numbers: ["A1"]) }

  def show(record, **params)
    get(:show, params: {group_id: group.id, id: record.id}.merge(params))
  end

  def edit(record, **params)
    get(:edit, params: {group_id: group.id, id: record.id}.merge(params))
  end

  def doc = Nokogiri::HTML(response.body)

  # The field labels of the rendered detail, in document order.
  def detail_labels = doc.css("dt").map { |dt| dt.text.strip }

  # The value of the row with this label.
  def detail_value(label)
    index = detail_labels.index(label)
    index && doc.css("dd")[index].text.squish
  end

  # The inputs of the page, by name.
  def input_names = doc.css("input, select, textarea").pluck("name").compact

  # The WRITING forms of the page -- the layout's quicksearch is a GET form and
  # submits on every page.
  def edit_forms
    doc.css("form").reject { |form| form["method"].to_s.casecmp?("get") }
  end

  describe "GET show" do
    before { sign_in(people(:ul_a_1)) }

    it "renders a booking of the group's cost center" do
      show(booking)

      expect(response).to be_successful
      expect(response.body).to include("Buchung Alpha")
      expect(response.body).to include("<html")
    end

    # Booked elsewhere, only tagged with the group's cost center as the
    # secondary one -- the same set the table's fixed filter slot pins.
    it "renders a booking reached through the secondary cost center" do
      show(secondary_booking)

      expect(response).to be_successful
      expect(response.body).to include("Buchung Beta")
    end

    # THE point of the route: without the scope check every booking id of the
    # contingent would be readable through any group a person may open.
    it "does not find a booking outside the group's cost centers" do
      expect { show(foreign_booking) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "finds nothing at all for a group without cost centers" do
      group.update!(cost_center_numbers: [])

      expect { show(booking) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    # Lazily loaded out of the Buchhaltung tab's table (prefix "gb"): the frame
    # it named comes back, and nothing else.
    it "answers the table's frame without a layout" do
      request.headers["Turbo-Frame"] = "bkframe-gb-#{booking.id}"

      show(booking, expandable_table_level: "1")

      expect(response).to be_successful
      expect(response.body).to include(%(<turbo-frame id="bkframe-gb-#{booking.id}"))
      expect(response.body).not_to include("<html")
      expect(response.body).to include("Buchung Alpha")
    end

    it "shows the group's fields and none of the bookkeeping internals" do
      booking.update!(user_comment: "für die Unit")
      show(booking)

      expect(detail_labels).to include("Betrag", "Notizen")
      # The internal comment is a row of its own on /fin and has no place here;
      # "Kommentar" is a substring of the label above, so the ROW is asserted.
      expect(detail_labels).not_to include("Kommentar")
      expect(response.body).not_to include("datev_booking[comment]")
      expect(detail_labels).not_to include("Sphäre")
      expect(response.body).not_to include("Verknüpfungen")
      expect(response.body).not_to include("Rohdaten")
      expect(response.body).not_to include(booking.buchungs_guid)
    end

    # The reading page reads: an unset field is not worth a row, and none of
    # them carries an input.
    it "hides the fields that are unset and offers no input" do
      show(booking)

      expect(detail_labels).not_to include("Sekundäre Kostenstelle", "Notizen")
      expect(input_names).not_to include("datev_booking[user_comment]")
    end

    # The sub cost center is the finance team's breakdown and stays off the
    # group's pages altogether, set or not.
    it "never shows the sub cost center" do
      booking.update_column(:sub_cost_center_number, "X1")

      show(booking)

      expect(detail_labels).not_to include("Unter-Kostenstelle")
      expect(response.body).not_to include("X1")
    end

    # Unit-Budget is never unset: the answer is resolved from the booking's own
    # flag, else its two accounts, else the default -- and neither account number
    # of this spec names a master record, so the default speaks.
    it "always states the Unit-Budget answer and where it comes from" do
      show(booking)

      expect(detail_value("Unit-Budget?")).to eq("ja (automatisch, Standard)")

      WsjrdpLedgerAccount.create!(number: "66500", name: "Testaufwand",
        is_unit_budget: false)
      show(booking)

      expect(detail_value("Unit-Budget?")).to eq("nein (automatisch, Gegenkonto 66500)")
    end

    # Two accounts that agree name no source at all: the ordinary case reads
    # "ja (automatisch)", here with both numbers known and both saying yes.
    it "names no source where both accounts agree" do
      WsjrdpLedgerAccount.create!(number: "1200", name: "Testbank")
      WsjrdpLedgerAccount.create!(number: "66500", name: "Testaufwand")

      show(booking)

      expect(detail_value("Unit-Budget?")).to eq("ja (automatisch)")
    end

    # The cost-centre step comes before the accounts: on a cost center that is
    # not a unit's own, the answer is no whatever the accounts say.
    it "names the cost center where it is not a unit's own" do
      WsjrdpLedgerAccount.create!(number: "1200", name: "Testbank")
      WsjrdpLedgerAccount.create!(number: "66500", name: "Testaufwand")
      cost_center.update!(is_unit_cost_center: false)

      show(booking)

      expect(detail_value("Unit-Budget?")).to eq("nein (automatisch, Kostenstelle A1)")
    end

    # The original amount is a special case: an EUR booking would only repeat
    # the Betrag with it, so it stays away.
    it "shows the original amount only for a foreign-currency booking" do
      show(booking)
      expect(detail_labels).not_to include("Original-Betrag", "Original-Währung")

      booking.update!(base_amount: 230, transaction_amount: 1000, transaction_currency: "PLN",
        exchange_rate: 4.3478)
      show(booking)
      expect(detail_value("Original-Betrag")).to include("1.000,00")
      expect(detail_labels).not_to include("Original-Währung")
    end

    # The Wechselkurs belongs to that pair and follows the same rule: on an EUR
    # booking there are not two amounts, so there is no rate to state.
    it "shows the exchange rate only for a foreign-currency booking" do
      booking.update!(exchange_rate: 4.3478)
      show(booking)
      expect(detail_labels).not_to include("Wechselkurs")

      booking.update!(base_amount: 230, transaction_amount: 1000, transaction_currency: "PLN")
      show(booking)
      expect(detail_value("Wechselkurs")).to eq("4,3478")
    end

    # No back link: the page hangs under the Buchhaltung tab, which stands
    # active above it, so a "Zurück zur Buchhaltung" would only repeat the tab
    # (doc/fin/detail_partials.md §9). Nothing here leads into /fin either.
    it "carries no back link and nothing into /fin" do
      show(booking)

      link_texts = doc.css("#main a").map { |a| a.text.strip }
      expect(link_texts.grep(/\AZurück/)).to be_empty
      expect(response.body).not_to include("/fin/bookkeeping/bookings/")
    end

    # Neither the Finanzen tab nor the Buchhaltung sub-tab carries an `alt:` for
    # this page: a tab's own path_method is matched as a PREFIX in the last pass
    # of Wsjrdp2027::Sheet::Base#find_active_tab, and the bookkeeping path is the
    # beginning of this one. Both levels render their tab list, so the
    # bookkeeping path is the active tab twice.
    it "keeps the Finanzen tab and the Buchhaltung sub-tab active" do
      show(booking)

      active = doc.css("ul.nav-sub li.active a").pluck("href")
      expect(active).to eq([group_finance_bookkeeping_path(group)] * 2)
    end

    it "refuses a youth participant on their own unit" do
      sign_in(people(:yp_a_1))

      expect { show(booking) }.to raise_error(CanCan::AccessDenied)
    end
  end

  # The Notizen: the group's own words on a booking. They stand right under the
  # description, in the description's own group, so the booking and the group's
  # note on it are read in one glance. A URL in them is a link; the helpdesk's
  # ticket keys become links only for a viewer who holds :log on the booking
  # (the audit tier and up) -- a unit leader reads them as text.
  describe "the notes" do
    let(:notes_help) { "Deine permanenten Notizen zu dieser Buchung" }

    def notes_cell
      index = detail_labels.index("Notizen")
      index && doc.css("dd")[index]
    end

    # The labels of every field group (one dl each), in document order.
    def group_labels = doc.css("dl").map { |dl| dl.css("dt").map { |dt| dt.text.strip } }

    before do
      booking.update!(user_comment: "Beleg unter https://example.org/beleg/1 abgelegt, siehe FIN-123")
    end

    it "stand right after the description, in the same group" do
      sign_in(people(:ul_a_1))
      show(booking)

      expect(detail_labels.index("Notizen")).to eq(detail_labels.index("Beschreibung") + 1)
      shared = group_labels.find { |labels| labels.include?("Beschreibung") }
      expect(shared).to include("Notizen")
    end

    it "link a URL but not a ticket for a unit leader" do
      sign_in(people(:ul_a_1))
      show(booking)

      links = notes_cell.css("a").to_h { |a| [a.text, a["href"]] }
      expect(links).to eq("https://example.org/beleg/1" => "https://example.org/beleg/1")
      expect(notes_cell.at_css("a")["target"]).to eq("_blank")
      expect(notes_cell.text).to include("FIN-123")
    end

    it "link the ticket as well for a viewer with :log on the booking" do
      sign_in(auditor)
      show(booking)

      ticket = notes_cell.css("a").find { |a| a.text == "FIN-123" }
      expect(ticket["href"]).to eq("https://helpdesk.worldscoutjamboree.de/browse/FIN-123")
    end

    it "carry their help on the reading page and under the input" do
      sign_in(people(:ul_a_1))
      show(booking)
      expect(notes_cell.text).to include(notes_help)

      edit(booking)
      expect(input_names).to include("datev_booking[user_comment]")
      expect(notes_cell.at_css(".fin-edit-input").text).to include(notes_help)
    end

    # The pane keeps what the page splits off: the inline "Bearbeiten" toggle
    # with the notes' own textarea, and the help beside it.
    it "stand after the description in the table's pane too, inline editable" do
      sign_in(people(:ul_a_1))
      request.headers["Turbo-Frame"] = "bkframe-gb-#{booking.id}"
      show(booking, expandable_table_level: "1")

      expect(detail_labels.index("Notizen")).to eq(detail_labels.index("Beschreibung") + 1)
      expect(doc.at_css(".fin-edit-toggle").text).to include("Bearbeiten")
      expect(input_names).to include("datev_booking[user_comment]")
      expect(notes_cell.at_css(".fin-edit-input").text).to include(notes_help)
    end
  end

  describe "the edit page" do
    it "leads a unit leader there from the reading page" do
      sign_in(people(:ul_a_1))

      show(booking)

      button = doc.css("a").find { |a| a.text.strip == "Bearbeiten" }
      expect(button["href"]).to eq(group_edit_finance_bookkeeping_booking_path(group, booking))
    end

    it "offers the one editable field to a unit leader" do
      sign_in(people(:ul_a_1))

      edit(booking)

      expect(response).to be_successful
      expect(edit_forms).not_to be_empty
      expect(input_names).to include("datev_booking[user_comment]")
      expect(input_names).not_to include("datev_booking[sub_cost_center_number]",
        "datev_booking[new_sub_cost_center_number]")
      expect(detail_labels).not_to include("Unter-Kostenstelle")
    end

    # The two fields that move money between cost centers stay with the finance
    # team: a group READS them here -- unset, with the marker -- and gets no
    # input for either.
    it "keeps the finance team's fields read-only" do
      sign_in(people(:ul_a_1))

      edit(booking)

      expect(detail_labels).to include("Sekundäre Kostenstelle", "Unit-Budget?")
      expect(input_names).not_to include("datev_booking[secondary_cost_center_number]",
        "datev_booking[is_unit_budget]")
      expect(detail_value("Sekundäre Kostenstelle")).to eq("nicht gesetzt")
      # Read-only means the resolved text stands where the select would be.
      expect(detail_value("Unit-Budget?")).to eq("ja (automatisch, Standard)")
    end

    it "carries both submits and the way back" do
      sign_in(people(:ul_a_1))

      edit(booking)

      buttons = doc.css("button[type=submit]").to_h { |b| [b.text.strip, b["name"]] }
      expect(buttons).to include("Speichern" => "save",
        "Speichern und weiter bearbeiten" => "stay")
      cancel = doc.css("a").find { |a| a.text.strip == "Abbrechen" }
      expect(cancel["href"]).to eq(group_finance_bookkeeping_booking_path(group, booking))
    end

    # "Abbrechen" is the way back from here; a back link above the heading would
    # be a second, different one.
    it "carries no back link" do
      sign_in(people(:ul_a_1))

      edit(booking)

      expect(doc.css("#main a").map { |a| a.text.strip }.grep(/\AZurück/)).to be_empty
    end

    it "does not reach a booking outside the group's cost centers" do
      sign_in(people(:ul_a_1))

      expect { edit(foreign_booking) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    # :show_finance through the audit tier, no :update_finance anywhere -- the
    # page reads, and offers no control that would answer 403.
    it "gives the audit tier a reading view" do
      sign_in(auditor)

      show(booking)

      expect(response).to be_successful
      expect(response.body).to include("Buchung Alpha")
      expect(edit_forms).to be_empty
      expect(response.body).not_to include("datev_booking[user_comment]")
      expect(doc.css("a").map { |a| a.text.strip }).not_to include("Bearbeiten")
    end

    it "refuses the audit tier the edit page itself" do
      sign_in(auditor)

      expect { edit(booking) }.to raise_error(CanCan::AccessDenied)
    end
  end

  describe "PATCH update" do
    def update(record, attrs)
      patch(:update, params: {group_id: group.id, id: record.id, datev_booking: attrs})
    end

    it "stores the comment for a unit leader" do
      sign_in(people(:ul_a_1))

      update(booking, {user_comment: "für die Unit"})

      expect(booking.reload.user_comment).to eq("für die Unit")
      expect(flash[:notice]).to include("aktualisiert")
    end

    # A field this page does not offer is refused as a WHOLE payload, not
    # silently dropped: the rest is not written either.
    %i[is_unit_budget secondary_cost_center_number sub_cost_center_number
      new_sub_cost_center_number].each do |field|
      it "refuses a payload carrying #{field} and writes nothing" do
        sign_in(people(:ul_a_1))

        expect do
          update(booking, {:user_comment => "für die Unit", field => "X1"})
        end.not_to change(WsjrdpSubCostCenter, :count)

        expect(flash[:alert]).to include("es wurde nichts gespeichert")
        expect(booking.reload.user_comment).to eq("")
        expect(booking.is_unit_budget).to be_nil
        expect(booking.secondary_cost_center_number).to be_nil
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
    it "comes back to the group's edit page for Speichern und weiter bearbeiten" do
      sign_in(people(:ul_a_1))

      patch(:update, params: {group_id: group.id, id: booking.id, stay: "1",
                              datev_booking: {user_comment: "für die Unit"}})

      expect(response).to redirect_to(
        group_edit_finance_bookkeeping_booking_path(group, booking)
      )
      expect(booking.reload.user_comment).to eq("für die Unit")
    end

    it "goes on to the group's reading page for Speichern" do
      sign_in(people(:ul_a_1))

      patch(:update, params: {group_id: group.id, id: booking.id, save: "1",
                              datev_booking: {user_comment: "für die Unit"}})

      expect(response).to redirect_to(group_finance_bookkeeping_booking_path(group, booking))
    end
  end
end
