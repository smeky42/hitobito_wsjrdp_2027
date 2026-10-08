# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Planning, activating and discarding an individual installment plan from the
# "Ratenplan" section of the Beitrag page. They change how the fee is paid, so
# they need :update_finance; the fee rule records who did what.
describe Person::InstallmentsController, type: :controller do
  let(:finance) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let(:leader) { Fabricate(Group::Root::Leader.name.to_sym, group: groups(:root)).person }
  let(:person) { people(:yp_a_1) }

  def rule(status, **attrs)
    Wsj27RdpFeeRule.create!(people_id: person.id, status: status,
      custom_installments_starting_year: 2026, custom_installments_cents: [0, 10_000],
      custom_installments_issue: "HELP-1", custom_installments_comment: "Vereinbarung", **attrs)
  end

  def planned_rule = Wsj27RdpFeeRule.find_by(people_id: person.id, status: "planned", deleted_at: nil)

  def plan(commit_action: nil, format: nil, context: nil, **attrs)
    top = {person_id: person.id, commit_action: commit_action, context: context}.compact
    values = {planned_custom_installments_string: "2026: 0; 312,50; 500",
              planned_custom_installments_issue: "HELP-2",
              planned_custom_installments_comment: "Vereinbarung",
              planned_custom_installments_payment_method: "credit_transfer"}
    put :update, format: format, params: top.merge(person: values.merge(attrs))
  end

  describe "as finance" do
    render_views

    before { sign_in(finance) }

    it "stores a plan, with its author, without touching the plan in effect or the log" do
      person.save! # the fixture fills in its payment role on its first save
      with_versioning do
        expect { plan }.not_to change { person.versions.count }
      end

      expect(response).to redirect_to(person_fee_path(person))
      expect(planned_rule).to have_attributes(custom_installments_starting_year: 2026,
        custom_installments_cents: [0, 31_250, 50_000], custom_installments_issue: "HELP-2",
        custom_installments_payment_method: "credit_transfer", created_by: finance, updated_by: finance)
      expect(person.reload.wsjrdp_raw_installments_eur).to be_nil
    end

    it "keeps who created a plan when another person changes it" do
      plan
      other = Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person
      sign_in(other)

      plan(planned_custom_installments_issue: "HELP-3")

      expect(planned_rule).to have_attributes(created_by: finance, updated_by: other, custom_installments_issue: "HELP-3")
    end

    it "refuses a missing or malformed plan, keeping what was typed" do
      ["", "100; 200", "2026: 100;", "2026: abc"].each do |text|
        plan(planned_custom_installments_string: text)

        expect(response).to have_http_status(422)
        expect(planned_rule).to be_nil
        expect(response.body).to include(ERB::Util.html_escape(text)) if text.present?
      end
    end

    it "saves and activates: the plan takes effect on the person, replacing the active one, authors recorded" do
      active = rule("active", activated_at: 1.day.ago)

      plan(commit_action: "activate")

      activated = Wsj27RdpFeeRule.find_by(people_id: person.id, status: "active", deleted_at: nil)
      expect(activated).to have_attributes(prev_rule_id: active.id, activated_by: finance,
        custom_installments_payment_method: "credit_transfer")
      expect(active.reload).to have_attributes(status: "deleted", deleted_by: finance)
      expect(person.reload).to have_attributes(wsjrdp_raw_installments_eur: [2026, 0, 312.5, 500],
        wsjrdp_installments_issue: "HELP-2", wsjrdp_installments_payment_method: "credit_transfer")
    end

    it "activates a stored plan, and says so without one" do
      planned = rule("planned")

      post :activate, params: {person_id: person.id}
      expect(planned.reload).to have_attributes(status: "active", activated_by: finance)
      expect(flash[:installments_notice]["text"]).to eq("Ratenplan aktiviert.")

      post :activate, params: {person_id: person.id}
      expect(flash[:installments_notice]["text"]).to eq("Es ist kein Ratenplan geplant.")
    end

    it "discards a stored plan, from the buttons and from the form" do
      planned = rule("planned")
      post :discard, params: {person_id: person.id}
      expect(planned.reload).to have_attributes(status: "deleted", deleted_by: finance)

      second = rule("planned")
      plan(commit_action: "discard", planned_custom_installments_string: "")
      expect(second.reload.status).to eq("deleted")
    end

    it "answers Turbo with a refresh on the Beitrag page and a reload keeping the scroll in the list" do
      plan(format: :turbo_stream)
      expect(response.body).to include('action="refresh"')

      plan(format: :turbo_stream, context: "fin")
      expect(response.body).to include('action="reload_keep_scroll"')
    end

    describe "the form" do
      def form_for(mode)
        get :edit, format: :turbo_stream, params: {person_id: person.id, mode: mode}
        response.body
      end

      it "starts blank, from the active plan or from the standard plan" do
        rule("active", activated_at: 1.day.ago, custom_installments_cents: [0, 20_000])
        person.update!(Wsjrdp2027::ParticipationFee.person_installments_attrs(person.active_fee_rule))
        WsjrdpPaymentPlan.kept.find_or_create_by!(wsjrdp_role: person.wsjrdp_role, single_payment: false,
          payment_method: "direct_debit") { |standard| standard.raw_installments_eur = [2025, 0, 300] }
        standard = WsjrdpPaymentPlan.kept.find_by(wsjrdp_role: person.wsjrdp_role, single_payment: false)

        expect(form_for("new")).not_to include("2026: 0; 200")
        expect(form_for("from_active")).to include("2026: 0; 200")
        expect(form_for("from_standard")).to include(standard.installments_string.split(";").first)
      end
    end
  end

  it "refuses every action to a leader, who only sees the section" do
    rule("planned")
    sign_in(leader)

    expect { plan }.to raise_error(CanCan::AccessDenied)
    expect { post :activate, params: {person_id: person.id} }.to raise_error(CanCan::AccessDenied)
    expect { post :discard, params: {person_id: person.id} }.to raise_error(CanCan::AccessDenied)
    expect { get :edit, params: {person_id: person.id} }.to raise_error(CanCan::AccessDenied)
    expect(planned_rule).to be_present
  end
end
