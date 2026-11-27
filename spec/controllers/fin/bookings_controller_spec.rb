# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Buchungen page and one booking's detail, which doubles as the pane an
# expandable table lazy-loads into its open row.
describe Fin::BookingsController do
  before_all(setup_fixtures: true) {}

  let_it_be(:person, refind: true) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

  # Invented header coordinates; the batch only has to exist so the detail's
  # Verknüpfungen block has a Buchungsstapel to link to.
  let_it_be(:batch) do
    DatevBookingBatch.create!(consultant_number: "1", client_number: "2",
      label: "Teststapel", period_from: Date.new(2026, 1, 1),
      period_to: Date.new(2026, 1, 31), financial_year_start: Date.new(2026, 1, 1),
      primanota_number: "01-2026/0001", import_export: "import")
  end

  # The Konto is a BANK account, so signed_base_amount is +amount for "D" and
  # -amount for "C" (no income/expense sign flip, see
  # doc/fin/money_conventions.md).
  def self.create_booking(batch, posting_text, amount, debit_credit = "D")
    DatevBooking.create!(batch: batch, buchungs_guid: SecureRandom.uuid,
      account_number: "1200", account_kind: "BANK",
      offsetting_account_number: "66500", offsetting_account_kind: "EXPENSE",
      cost_center_number: "K100",
      base_amount: amount, transaction_amount: amount, debit_credit: debit_credit,
      base_currency: "EUR", booking_date: Date.new(2026, 2, 1),
      posting_text: posting_text)
  end

  def create_booking(...) = self.class.create_booking(batch, ...)

  let_it_be(:booking, refind: true) { create_booking("Testbuchung Alpha", 100) }
  let_it_be(:other_booking, refind: true) { create_booking("Testbuchung Beta", 70, "C") }

  # 1200 says yes to the Unit-Budget, 66500 says no, so an untouched booking of
  # this spec is a "nein".
  before_all do
    WsjrdpLedgerAccount.create!(number: "1200", name: "Testbank")
    WsjrdpLedgerAccount.create!(number: "66500", name: "Testaufwand", is_unit_budget: false)
  end

  let_it_be(:auditor) do
    extern = Group::Extern.create!(name: "Extern", parent: groups(:root))
    Fabricate(Group::Extern::FinanceAuditor.name.to_sym, group: extern).person
  end

  before { sign_in(person) }

  def rendered_ids = controller.bookings.page.map(&:id)

  def summary_line = controller.view_context.booking_table_summary(controller.bookings)

  describe "GET index" do
    it "lists the bookings" do
      get :index

      expect(response).to be_successful
      expect(rendered_ids).to contain_exactly(booking.id, other_booking.id)
    end

    it "offers the Unit-Budget as a column, not shown by default" do
      get :index, params: {c: "bdt,ub"}

      aggregate_failures do
        expect(Fin::DatevBookingsColumns.default_keys).not_to include("unit_budget")
        expect(controller.booking_table_state.visible_column_keys).to eq(%w[booking_date unit_budget])
      end
    end

    it "sorts the list by the resolved Unit-Budget answer" do
      booking.update!(is_unit_budget: true)
      get :index, params: {c: "bdt,ub", s: "ub"}

      expect(rendered_ids).to eq([other_booking.id, booking.id])
    end

    # The summary's third figure: how much of the sum beside it counts against a
    # unit's budget. Both come from the SAME filtered relation.
    it "states the Unit-Budget share of the sum" do
      booking.update!(is_unit_budget: true)
      get :index

      nbsp = Fin::MoneyHelper::NBSP
      expect(summary_line).to eq("2 Buchungen · Summe (gefiltert): 30,00#{nbsp}€ · " \
        "davon Unit-Budget: 100,00#{nbsp}€ (1 Buchungen)")
    end

    it "computes the share over the filtered rows only" do
      booking.update!(is_unit_budget: true)
      get :index, params: {f: "!(!(!(q,ct,Beta)))"}

      nbsp = Fin::MoneyHelper::NBSP
      expect(summary_line).to eq("1 Buchungen · Summe (gefiltert): -70,00#{nbsp}€ · " \
        "davon Unit-Budget: 0,00#{nbsp}€ (0 Buchungen)")
    end

    # "Kostenstelle (Budget-Zuordnung)": a unit's booking outside its
    # Unit-Budget counts against its regular secondary cost center.
    it "filters by the budget assignment" do
      WsjrdpCostCenter.create!(number: "U9", name: "Unit", is_unit_cost_center: true)
      WsjrdpCostCenter.create!(number: "K900", name: "Regulär")
      unit = create_booking("Unit-Reise", 12)
      unit.update!(cost_center_number: "U9", secondary_cost_center_number: "K900", is_unit_budget: false)
      kept = create_booking("Unit-Budget", 13)
      kept.update!(cost_center_number: "U9", secondary_cost_center_number: "K900", is_unit_budget: true)

      get :index, params: {f: "!(!(!(bcc,in,K900)))"}
      expect(rendered_ids).to eq([unit.id])
    end
  end

  describe "GET show" do
    it "renders the reading page, also for the read tier" do
      sign_in(auditor)
      get :show, params: {id: booking.id}

      expect(response).to be_successful
      expect(assigns(:ctx)).to be_regular
    end

    # Lazily loaded out of a table, the frame comes back alone, at the level of
    # the table that asked.
    it "answers a table's frame without a layout" do
      request.headers["Turbo-Frame"] = "bkframe-b-#{booking.id}"
      get :show, params: {id: booking.id, expandable_table_level: "2"}

      aggregate_failures do
        expect(response).to render_template(layout: false)
        expect(assigns(:ctx)).to be_embedded
        expect(assigns(:ctx).level).to eq(2)
      end
    end

    describe "the views" do
      render_views

      def doc = Nokogiri::HTML(response.body)

      def input_names = doc.css("input, select, textarea").pluck("name").compact

      def link(text) = doc.css("a").find { |a| a.text.strip == text }

      # The reading page reads: no input, the way to the edit page and back to
      # the list instead.
      it "carries no input on the reading page and leads to the edit page" do
        get :show, params: {id: booking.id}

        aggregate_failures do
          expect(input_names).not_to include("datev_booking[comment]", "datev_booking[user_comment]",
            "datev_booking[secondary_cost_center_number]")
          expect(link("Bearbeiten")["href"]).to eq(edit_booking_path(booking))
          expect(link("Zurück zur Liste")["href"]).to eq(bookings_path)
        end
      end

      # The pane inside an open table row turns into inputs where it stands.
      it "keeps the inline edit in the lazy pane" do
        request.headers["Turbo-Frame"] = "bkframe-bk-#{booking.id}"
        get :show, params: {id: booking.id, expandable_table_level: "1"}

        expect(input_names).to include("datev_booking[comment]", "datev_booking[user_comment]")
      end

      # Only the edit page offers the number of a new sub cost center.
      it "renders the inputs of every editable field on the edit page" do
        get :edit, params: {id: booking.id}

        expect(input_names).to include("datev_booking[secondary_cost_center_number]",
          "datev_booking[is_unit_budget]", "datev_booking[sub_cost_center_number]",
          "datev_booking[comment]", "datev_booking[user_comment]",
          "datev_booking[new_sub_cost_center_number]")
      end
    end
  end

  describe "GET edit" do
    it "refuses the read tier" do
      sign_in(auditor)

      expect { get :edit, params: {id: booking.id} }.to raise_error(CanCan::AccessDenied)
    end
  end

  describe "PATCH update" do
    it "stores both comments" do
      patch :update, params: {id: booking.id,
                              datev_booking: {comment: "intern", user_comment: "für alle"}}

      expect(booking.reload.comment).to eq("intern")
      expect(booking.user_comment).to eq("für alle")
    end

    # The columns are NOT NULL with "" as their default: an emptied comment is
    # stored as "", never as NULL.
    it "clears a comment to the empty string" do
      booking.update!(user_comment: "für alle")

      patch :update, params: {id: booking.id, datev_booking: {user_comment: ""}}

      expect(booking.reload.user_comment).to eq("")
    end

    it "stores the Unit-Budget override" do
      patch :update, params: {id: booking.id, datev_booking: {is_unit_budget: "true"}}
      expect(booking.reload.is_unit_budget).to be true
    end

    it "clears the Unit-Budget override, so the accounts decide again" do
      booking.update!(is_unit_budget: true)

      patch :update, params: {id: booking.id, datev_booking: {is_unit_budget: ""}}

      expect(booking.reload.is_unit_budget).to be_nil
      expect(booking.unit_budget).to eq([false, "gegenkonto"])
    end

    # Which of the edit page's two submits was pressed is the whole difference:
    # `stay` comes back to go on editing, `save` goes on to the reading page.
    it "comes back to the edit page for Speichern und weiter bearbeiten" do
      patch :update, params: {id: booking.id, stay: "1",
                              datev_booking: {user_comment: "für alle"}}

      expect(response).to redirect_to(edit_booking_path(booking))
      expect(booking.reload.user_comment).to eq("für alle")
    end

    it "goes on to the reading page for Speichern" do
      patch :update, params: {id: booking.id, save: "1",
                              datev_booking: {user_comment: "für alle"}}

      expect(response).to redirect_to(booking_path(booking))
    end

    describe "a new sub cost center" do
      it "creates it under the booking's own cost center and assigns it" do
        expect do
          patch :update, params: {id: booking.id,
                                  datev_booking: {sub_cost_center_number: "",
                                                  new_sub_cost_center_number: " X9 "}}
        end.to change(WsjrdpSubCostCenter, :count).by(1)

        created = WsjrdpSubCostCenter.find_by(cost_center_number: "K100", number: "X9")
        expect(created).to be_present
        expect(created.name).to be_blank
        expect(booking.reload.sub_cost_center_number).to eq("X9")
      end

      # The number is unique within its cost center only, so an existing one is
      # reused rather than duplicated.
      it "reuses a number that already exists there" do
        WsjrdpSubCostCenter.create!(cost_center_number: "K100", number: "X9", name: "Teil X")

        expect do
          patch :update, params: {id: booking.id,
                                  datev_booking: {new_sub_cost_center_number: "X9"}}
        end.not_to change(WsjrdpSubCostCenter, :count)

        expect(booking.reload.sub_cost_center_number).to eq("X9")
      end

      # It wins over the select: that one cannot offer a number that does not
      # exist yet.
      it "beats the select" do
        WsjrdpSubCostCenter.create!(cost_center_number: "K100", number: "X1", name: "Teil X")

        patch :update, params: {id: booking.id,
                                datev_booking: {sub_cost_center_number: "X1",
                                                new_sub_cost_center_number: "X9"}}

        expect(booking.reload.sub_cost_center_number).to eq("X9")
      end

      it "writes nothing for a booking without a cost center" do
        booking.update!(cost_center_number: nil)

        expect do
          patch :update, params: {id: booking.id,
                                  datev_booking: {user_comment: "für alle",
                                                  new_sub_cost_center_number: "X9"}}
        end.not_to change(WsjrdpSubCostCenter, :count)

        expect(flash[:alert]).to include("keine Kostenstelle")
        expect(booking.reload.user_comment).to eq("")
        expect(booking.sub_cost_center_number).to be_nil
      end

      # The field stands on every save of the edit page; left empty it is not a
      # request for anything, and the select decides as before.
      it "is ignored when it is left empty" do
        WsjrdpSubCostCenter.create!(cost_center_number: "K100", number: "X1", name: "Teil X")

        expect do
          patch :update, params: {id: booking.id,
                                  datev_booking: {sub_cost_center_number: "X1",
                                                  new_sub_cost_center_number: ""}}
        end.not_to change(WsjrdpSubCostCenter, :count)

        expect(booking.reload.sub_cost_center_number).to eq("X1")
      end
    end
  end
end
