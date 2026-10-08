# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# A unit leader (Group::Unit::Leader, group_full on the unit) may edit the
# people of the unit and so reads their Beitrag page -- without the
# privileged view and without changing anything. Nothing else of the finance
# pages: not the Ausgaben (Moss) page, which the person themselves, :log and
# :update_finance reach, and no finance page at all of a person outside the
# unit.
describe "finance pages for a unit leader" do
  let(:unit_leader) { people(:ul_a_1) }
  let(:yp) { people(:yp_a_1) }
  let(:unit_manager) { Fabricate(Group::Unit::Manager.name.to_sym, group: groups(:unit_a)).person }
  let(:finance) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }

  before do
    [yp, people(:yp_b_1)].each do |person|
      WsjrdpPaymentPlan.kept.find_or_create_by!(wsjrdp_role: person.wsjrdp_role, single_payment: false,
        payment_method: "direct_debit") { |plan| plan.raw_installments_eur = [2026, 100, 100] }
    end
  end

  describe Person::FeeController, type: :controller do
    render_views

    it "shows a unit leader the Beitrag page of a person of the unit, without the privileged view or buttons" do
      yp.update!(wsjrdp_total_fee_reduction: 100, wsjrdp_total_fee_reduction_issue: "HELP-77")
      sign_in(unit_leader)
      get :show, params: {person_id: yp.id}

      expect(response).to be_successful
      expect(response.body).not_to include("HELP-77")
      doc = Nokogiri::HTML(response.body)
      expect(doc.at_css("section.fee-reduction")).to be_nil
      expect(doc.css("[id^='installments_actions_'], [id^='fee_reduction_actions_']")).to be_empty
    end

    it "shows a unit leader the Finanzen and Beiträge tabs" do
      sign_in(unit_leader)
      get :show, params: {person_id: yp.id}

      tabs = Nokogiri::HTML(response.body).css("a[data-turbo-submits-with]").map { |link| link.text.strip }
      expect(tabs).to include("Finanzen", "Beiträge")
      expect(tabs).not_to include("Ausgaben (Moss)", "Abmeldung")
    end

    it "offers the Ausgaben tab to the person themselves, a unit manager and finance, not to a unit leader" do
      {yp => true, unit_manager => true, finance => true, unit_leader => false}.each do |viewer, shown|
        sign_in(viewer)
        get :show, params: {person_id: yp.id}

        expect(response.body.include?(person_spend_path(yp))).to eq(shown), "#{viewer}: tab shown #{!shown}"
      end
    end
  end

  describe Person::SpendController, type: :controller do
    it "opens to the person themselves, a unit manager (:log) and finance (:update_finance)" do
      [yp, unit_manager, finance].each do |viewer|
        sign_in(viewer)
        get :show, params: {person_id: yp.id}

        expect(response).to be_successful
      end
    end

    it "refuses a unit leader, the Moss login included" do
      sign_in(unit_leader)

      expect { get :show, params: {person_id: yp.id} }.to raise_error(CanCan::AccessDenied)
      expect { get :moss_sso_login, params: {person_id: yp.id} }.to raise_error(CanCan::AccessDenied)
    end
  end

  # A person of another unit, a person of the CMT and a person in no group at
  # all: none of their finance pages opens to the unit leader -- denied, or, on
  # a page looked up through a group the person is not in, not found. One
  # example group per controller, so that each runs as its own controller
  # spec.
  describe "a person outside the unit" do
    {
      Person::FeeController => [
        ->(o) { get :show, params: {person_id: o.id} },
        ->(o) { get :statement, params: {person_id: o.id} }
      ],
      Person::SpendController => [->(o) { get :show, params: {person_id: o.id} }],
      Person::DeregistrationController => [->(o) { get :show, params: {person_id: o.id} }],
      Person::DebitReturnController => [->(o) { get :edit, params: {person_id: o.id} }],
      Person::InstallmentsController => [->(o) { get :edit, params: {person_id: o.id} }],
      Person::FeeReductionController => [->(o) { get :edit, params: {person_id: o.id} }],
      Person::StatusController => [
        ->(o) { get :show, params: {group_id: o.primary_group_id || groups(:root).id, id: o.id} }
      ]
    }.each do |controller_class, requests|
      describe controller_class, type: :controller do
        let(:outsiders) { [people(:yp_b_1), people(:cmt_leader), Fabricate(:person)] }

        before { sign_in(unit_leader) }

        it "stays closed to the unit leader" do
          outsiders.each do |outsider|
            requests.each do |request|
              expect { instance_exec(outsider, &request) }.to raise_error { |error|
                expect([CanCan::AccessDenied, ActiveRecord::RecordNotFound]).to include(error.class),
                  "#{controller_class} for #{outsider}: #{error.class}"
              }
            end
          end
        end
      end
    end
  end
end
