# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The finance audit tier reads a person's Beitrag page (:show_finance) -- with
# the privileged view of a person with :log, comments included, and without
# anything that changes something -- but no other page of the person. The
# read tier reads none of them.
describe "the Beitrag page for the finance audit tier" do
  let(:yp) { people(:yp_a_1) }
  let(:extern) { Group::Extern.create!(name: "Extern", parent: groups(:root)) }
  let(:auditor) { Fabricate(Group::Extern::FinanceAuditor.name.to_sym, group: extern).person }
  let(:reader) { Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person }
  let(:finance) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

  before do
    WsjrdpPaymentPlan.kept.find_or_create_by!(wsjrdp_role: yp.wsjrdp_role, single_payment: false,
      payment_method: "direct_debit") { |plan| plan.raw_installments_eur = [2026, 100, 100] }
  end

  describe Person::FeeController, type: :controller do
    render_views

    before do
      active = Wsj27RdpFeeRule.create!(people_id: yp.id, status: "active", activated_at: 1.day.ago,
        custom_installments_starting_year: 2026, custom_installments_cents: [0, 10_000],
        custom_installments_issue: "HELP-11", custom_installments_comment: "Vereinbarung aktiv",
        activated_by: finance)
      Wsj27RdpFeeRule.create!(people_id: yp.id, status: "planned",
        custom_installments_starting_year: 2026, custom_installments_cents: [0, 0, 7_000],
        custom_installments_issue: "HELP-12")
      yp.update!(**Wsjrdp2027::ParticipationFee.person_installments_attrs(active),
        wsjrdp_total_fee_reduction: 250, wsjrdp_total_fee_reduction_hint: "Härtefall",
        wsjrdp_total_fee_reduction_comment: "Nachweis liegt vor")
      AccountingEntry.create!(subject: yp, author: finance, amount_cents: 0, description: "Nullbuchung",
        value_date: Date.new(2026, 2, 1), booking_date: Date.new(2026, 2, 1))
    end

    def doc = Nokogiri::HTML(response.body)

    it "shows the auditor the page with the privileged view, comments included" do
      sign_in(auditor)
      get :show, params: {person_id: yp.id}

      expect(response).to be_successful
      installments = doc.at_css("section.installments")
      expect(installments.text).to include("HELP-11").and include("Vereinbarung aktiv")
      expect(installments.text).to include("Geplant:").and include("Änderungen am Ratenplan")
      reduction = doc.at_css("section.fee-reduction")
      expect(reduction.text).to include("Härtefall").and include("Nachweis liegt vor")
      expect(response.body).to include("Nullbuchung")
    end

    it "offers the auditor nothing that changes anything" do
      sign_in(auditor)
      get :show, params: {person_id: yp.id}

      expect(doc.css("[id^='installments_actions_'], [id^='fee_reduction_actions_']")).to be_empty
      expect(response.body).not_to include("Neue Buchung")
      expect(response.body).not_to include("Finanzstatus ändern")
      expect(response.body).not_to include(edit_person_installments_path(yp))
    end

    it "shows the auditor the Finanzen and Beiträge tabs, and no tab of a page it may not open" do
      sign_in(auditor)
      get :show, params: {person_id: yp.id}

      tabs = doc.css("a[data-turbo-submits-with]").map { |link| link.text.strip }
      expect(tabs).to include("Finanzen", "Beiträge")
      expect(tabs).not_to include("Ausgaben (Moss)", "Abmeldung", "Status", "Log")
    end

    it "lets the auditor print the statement" do
      sign_in(auditor)
      get :statement, params: {person_id: yp.id}

      expect(response).to be_successful
      expect(response.media_type).to eq("application/pdf")
    end

    it "refuses the read tier" do
      sign_in(reader)

      expect { get :show, params: {person_id: yp.id} }.to raise_error(CanCan::AccessDenied)
      expect { get :statement, params: {person_id: yp.id} }.to raise_error(CanCan::AccessDenied)
    end
  end

  describe "no other page of the person" do
    before { sign_in(auditor) }

    describe PeopleController, type: :controller do
      it "refuses the person's page and its edit form" do
        expect { get :show, params: {group_id: yp.primary_group_id, id: yp.id} }.to raise_error(CanCan::AccessDenied)
        expect { get :edit, params: {group_id: yp.primary_group_id, id: yp.id} }.to raise_error(CanCan::AccessDenied)
      end
    end

    describe Person::StatusController, type: :controller do
      it "refuses the status page" do
        expect { get :show, params: {group_id: yp.primary_group_id, id: yp.id} }.to raise_error(CanCan::AccessDenied)
      end
    end

    describe Person::LogController, type: :controller do
      it "refuses the log" do
        expect { get :index, params: {group_id: yp.primary_group_id, id: yp.id} }.to raise_error(CanCan::AccessDenied)
      end
    end

    describe Person::InstallmentsController, type: :controller do
      it "refuses planning, activating and discarding" do
        expect { get :edit, params: {person_id: yp.id} }.to raise_error(CanCan::AccessDenied)
        expect { post :activate, params: {person_id: yp.id} }.to raise_error(CanCan::AccessDenied)
        expect { post :discard, params: {person_id: yp.id} }.to raise_error(CanCan::AccessDenied)
      end
    end

    describe Person::FeeReductionController, type: :controller do
      it "refuses planning, activating and discarding" do
        expect { get :edit, params: {person_id: yp.id} }.to raise_error(CanCan::AccessDenied)
        expect { post :activate, params: {person_id: yp.id} }.to raise_error(CanCan::AccessDenied)
      end
    end
  end
end
