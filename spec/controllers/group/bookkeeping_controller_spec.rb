# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Buchhaltung sub-tab of a group's Finanzen tab (/groups/:id/finance/bookkeeping).
# The page is gated on :show_finance, so it answers to the group's own leaders,
# to a person whose finance_group_ids list the group, and to the finance tiers
# from the audit tier up; the read tier stays out.
describe Group::BookkeepingController do
  before_all(setup_fixtures: true) {}

  let_it_be(:auditor) do
    extern = Group::Extern.create!(name: "Extern", parent: groups(:root))
    Fabricate(Group::Extern::FinanceAuditor.name.to_sym, group: extern).person
  end
  let_it_be(:reader) { Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person }

  def show(group, **params) = get(:show, params: {group_id: group.id, **params})

  describe "permissions" do
    it "answers a unit leader on their own unit" do
      sign_in(people(:ul_a_1))

      show(groups(:unit_a))

      expect(response).to be_successful
    end

    it "refuses a unit leader on another unit" do
      sign_in(people(:ul_a_1))

      expect { show(groups(:unit_b)) }.to raise_error(CanCan::AccessDenied)
    end

    it "refuses a youth participant on their own unit" do
      sign_in(people(:yp_a_1))

      expect { show(groups(:unit_a)) }.to raise_error(CanCan::AccessDenied)
    end

    it "refuses the CMT leader on a unit without an entry in finance_group_ids" do
      sign_in(people(:cmt_leader))

      expect { show(groups(:unit_b)) }.to raise_error(CanCan::AccessDenied)
    end

    it "answers the CMT leader on a unit listed in their finance_group_ids" do
      cmt_leader = people(:cmt_leader)
      cmt_leader.update!(finance_group_ids: {groups(:unit_b).id.to_s => "show"})
      sign_in(cmt_leader)

      show(groups(:unit_b))

      expect(response).to be_successful
    end

    it "answers the audit tier, which is not layer-bound" do
      sign_in(auditor)

      show(groups(:unit_a))

      expect(response).to be_successful
    end

    it "refuses the read tier, which grants nothing on a group" do
      sign_in(reader)

      expect { show(groups(:unit_a)) }.to raise_error(CanCan::AccessDenied)
    end

    it "refuses the apply POST to a youth participant" do
      sign_in(people(:yp_a_1))

      expect { post :apply, params: {group_id: groups(:unit_a).id, filter_json: "[]"} }
        .to raise_error(CanCan::AccessDenied)
    end
  end

  # All numbers, names and booking texts invented.
  describe "with bookings" do
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
        base_amount: 100, transaction_amount: 100, debit_credit: "D",
        base_currency: "EUR", booking_date: Date.new(2026, 2, 1),
        posting_text: posting_text)
    end

    let_it_be(:cost_center_a) { WsjrdpCostCenter.create!(number: "A1", name: "Kostenstelle A1") }
    let_it_be(:cost_center_b) { WsjrdpCostCenter.create!(number: "B1", name: "Kostenstelle B1") }

    let_it_be(:own_booking) { create_booking("Buchung Alpha", cost_center: "A1") }
    # Booked on ANOTHER cost center and only tagged with the group's as the
    # secondary one -- the reason the pin uses `any_cost_center`.
    let_it_be(:secondary_booking) do
      create_booking("Buchung Beta", cost_center: "B1", secondary: "A1")
    end
    let_it_be(:foreign_booking) { create_booking("Buchung Gamma", cost_center: "B1") }

    before_all do
      groups(:unit_a).update!(cost_center_numbers: ["A1"])
      groups(:unit_b).update!(cost_center_numbers: ["B1"])
    end

    before { sign_in(people(:ul_a_1)) }

    def state = controller.booking_table_state

    def listed_ids = controller.bookings.page.map(&:id)

    def visible_columns = state.visible_column_keys

    def offered_columns = state.column_states.map(&:first)

    describe "the rendered page" do
      render_views

      def doc = Nokogiri::HTML(response.body)

      # The sub-tab links to the group once: a second group in the path args
      # would become the format (".../finance/bookkeeping.8").
      it "shows neither tiles nor table for a group without cost centers, and a clean sub-tab link" do
        groups(:unit_a).update!(cost_center_numbers: [])

        show(groups(:unit_a))

        expect(doc.css(".gb-figure")).to be_empty
        expect(doc.css("table.bookings-table")).to be_empty
        expect(doc.css("ul.nav-sub a").pluck("href")).to include(group_finance_bookkeeping_path(groups(:unit_a)))
        expect(response.body).not_to match(%r{/finance/bookkeeping\.\d})
      end

      it "keeps a unit leader on the group's own routes, the cost-center chip unlinked" do
        show(groups(:unit_a))

        booking_path = group_finance_bookkeeping_booking_path(groups(:unit_a), own_booking)
        expect(doc.css("#main a").pluck("href")).to include(booking_path)
        expect(doc.css("turbo-frame").pluck("src")).to include(a_string_starting_with(booking_path))
        expect(response.body).not_to include("/fin/bookkeeping/")
      end

      it "links the cost-center chip for somebody who may open a cost center" do
        sign_in(Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person)

        show(groups(:unit_a))

        expect(doc.css("#main .badge a").pluck("href")).to include(cost_center_path("A1"))
      end
    end

    it "lists the group's bookings on either cost-center column, pinned by a locked slot" do
      show(groups(:unit_a))

      expect(listed_ids).to contain_exactly(own_booking.id, secondary_booking.id)
      expect(state.filter.readonly_slots).to eq([[["any_cost_center", "in", "A1"]]])
    end

    it "builds no table for a group without cost centers" do
      groups(:unit_a).update!(cost_center_numbers: [])

      show(groups(:unit_a))

      expect(assigns(:bookings)).to be_nil
    end

    it "starts with Unit-Budget and Konto, without Gegenkonto, Kostenstelle where one, and Sphäre" do
      show(groups(:unit_a))

      expect(visible_columns).to include("unit_budget", "account_number")
      expect(visible_columns).not_to include("offsetting_account_number", "cost_center_number")
      expect(offered_columns).to include("offsetting_account_number", "cost_center_number", "document_field_1")
      expect(offered_columns).not_to include("sphere_number")
    end

    it "shows the Kostenstelle where the group has two" do
      groups(:unit_a).update!(cost_center_numbers: %w[A1 B1])

      show(groups(:unit_a))

      expect(visible_columns).to include("cost_center_number")
    end

    it "takes hidden columns back through ?gbc= and drops one the table does not have" do
      show(groups(:unit_a), gbc: "bdt,sphere,cc,oacc")

      expect(visible_columns).to include("booking_date", "cost_center_number", "offsetting_account_number")
      expect(visible_columns).not_to include("sphere_number")
    end

    it "ignores a ?gbs= naming a column outside the table" do
      show(groups(:unit_a), gbs: "sphere~")

      expect(state.sort_list).to eq([])
    end

    it "drops a ?gbf= naming an attribute the picker does not offer" do
      show(groups(:unit_a), gbf: "!(!(!(sph,in,S1)))")

      expect(state.filter.user_slots.flatten).to be_empty
      expect(listed_ids).to contain_exactly(own_booking.id, secondary_booking.id)
    end

    it "offers the Unit-Budget Schnellauswahl, unrestricted at first" do
      show(groups(:unit_a))

      expect(state.filter.presets.size).to eq(3)
      expect(state.filter.presets.first).to be_active
      expect(state.filter.presets.drop(1)).to all(satisfy { |preset| !preset.active? })
    end

    # A shortcut into the USER part, over the RESOLVED answer: 1200 names no
    # account and 66500 says no, so only the booking carrying the flag counts.
    it "narrows on the resolved Unit-Budget in the user part, beside the locked pin" do
      WsjrdpLedgerAccount.create!(number: "66500", name: "Testaufwand", is_unit_budget: false)
      DatevBooking.where(id: own_booking.id).update_all(is_unit_budget: true)

      show(groups(:unit_a), gbf: "!(!(!(ub,in,'true')))")

      expect(listed_ids).to eq([own_booking.id])
      expect(state.filter.user_slots).to eq([[["unit_budget", "in", "true"]]])
      expect(state.filter.readonly_slots).to eq([[["any_cost_center", "in", "A1"]]])
      expect(state.filter.presets.select(&:active?).map(&:value)).to eq(["true"])
    end

    it "sums the Unit-Budget share over the rows the table shows" do
      DatevBooking.where(id: own_booking.id).update_all(is_unit_budget: true)

      show(groups(:unit_a))

      expect(controller.bookings.total_sum).to eq(200)
      expect(controller.bookings.subtotal(DatevBooking::EFFECTIVE_IS_UNIT_BUDGET_SQL)).to eq([1, 100])
    end

    # The table answers what the viewer is looking at, the tiles where the
    # unit stands.
    it "keeps the Kennzahlen on the pinned set whatever the user filters" do
      show(groups(:unit_a), gbf: "!(!(!(q,ct,Alpha)))")

      expect(listed_ids).to eq([own_booking.id])
      expect(controller.bookkeeping_figures.expenses_total).to eq(-200)
    end

    it "redirects the apply POST back to the page, the group in the path (PRG)" do
      post :apply, params: {group_id: groups(:unit_a).id,
                            filter_json: [[["text", "contains", "Alpha"]]].to_json}

      expect(response).to have_http_status(:see_other)
      expect(response.location).to include(group_finance_bookkeeping_path(groups(:unit_a)))
      expect(response.location).to include("gbf=")
      expect(URI.parse(response.location).query).not_to include("group_id")
    end

    it "remembers the filter per group" do
      cmt_leader = people(:cmt_leader)
      cmt_leader.update!(finance_group_ids: {groups(:unit_a).id.to_s => "show",
                                             groups(:unit_b).id.to_s => "show"})
      sign_in(cmt_leader)
      show(groups(:unit_a), gbf: "!(!(!(q,ct,Alpha)))")

      show(groups(:unit_a))
      expect(state.filter.user_slots.flatten.map(&:to_s)).to include("Alpha")

      show(groups(:unit_b))
      expect(state.filter.user_slots.flatten).to be_empty
    end
  end
end
