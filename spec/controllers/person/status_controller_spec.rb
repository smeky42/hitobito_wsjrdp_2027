# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Activating a planned fee rule (custom installments) on the status tab: the
# planned rule becomes active and records the rule it replaces as prev_rule_id;
# the person carries the same plan (Wsjrdp2027::ParticipationFee). Activating and
# discarding need :update_finance.
# The total fee reduction is maintained on the Beitrag page; the status tab
# names it and links there.
describe Person::StatusController, type: :controller do
  let(:manager) { Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person }
  let(:person) { people(:yp_a_1) }

  def rule(status, **attrs)
    Wsj27RdpFeeRule.create!(people_id: person.id, status: status,
      custom_installments_starting_year: 2026, custom_installments_cents: [0, 10_000],
      custom_installments_issue: "HELP-1", custom_installments_comment: "Vereinbarung", **attrs)
  end

  before { sign_in(manager) }

  def activate
    post :activate_planned_custom_installments, params: {group_id: person.primary_group_id, id: person.id}
  end

  it "activates the planned rule with the replaced active rule as prev_rule_id" do
    active = rule("active", activated_at: 1.day.ago)
    planned = rule("planned")

    activate

    expect(active.reload).to have_attributes(status: "deleted")
    expect(active.deleted_at).to be_present
    expect(planned.reload).to have_attributes(status: "active", prev_rule_id: active.id)
    expect(planned.activated_at).to be_present
  end

  it "activates a first planned rule without a prev_rule_id" do
    planned = rule("planned")

    activate

    expect(planned.reload).to have_attributes(status: "active", prev_rule_id: nil)
    expect(person.reload).to have_attributes(wsjrdp_raw_installments_eur: [2026, 0, 100],
      wsjrdp_installments_issue: "HELP-1", wsjrdp_installments_comment: "Vereinbarung")
  end

  describe "for a leader, who may see the person's log but not change the fee" do
    let(:leader) { Fabricate(Group::Root::Leader.name.to_sym, group: groups(:root)).person }
    let!(:planned) { rule("planned") }

    before { sign_in(leader) }

    it "refuses activating and discarding" do
      expect { activate }.to raise_error(CanCan::AccessDenied)
      expect {
        post :delete_planned_custom_installments, params: {group_id: person.primary_group_id, id: person.id}
      }.to raise_error(CanCan::AccessDenied)
      expect(planned.reload.status).to eq("planned")
    end

    describe "on the page" do
      render_views

      # The page shows the installments, which the test database only has as
      # a custom plan.
      before { rule("active", activated_at: 1.day.ago) }

      it "offers neither button" do
        get :show, params: {group_id: person.primary_group_id, id: person.id}

        expect(response.body).not_to include("activate_planned_custom_installments")
        expect(response.body).not_to include("delete_planned_custom_installments")
      end
    end
  end

  describe "total fee reduction" do
    render_views

    # The pages show the installments, which the test database only has as a
    # custom plan.
    before do
      rule("active", activated_at: 1.day.ago)
      person.update!(wsjrdp_total_fee_reduction: 500, wsjrdp_total_fee_reduction_hint: "Härtefall")
    end

    it "names it and links to the Beitrag page, on the page and in the form" do
      %i[show edit].each do |action|
        get action, params: {group_id: person.primary_group_id, id: person.id}

        expect(response.body).to include("Härtefall: reduziert um 500€")
        expect(response.body).to include(person_fee_path(person))
        expect(response.body).not_to include("planned_total_fee_reduction")
      end
    end
  end
end
