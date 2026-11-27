# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Individuelle Ratenpläne tab of the Beiträge area: every person with an
# active or a planned individual plan, for the audit tier and up.
describe Fin::IndividualPaymentPlansController do
  before_all(setup_fixtures: true) {}

  let_it_be(:finance) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let_it_be(:reader) { Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person }
  # yp: an active plan from 2026; other: an active plan activated later, and a
  # planned one; planner: a planned plan only; long: an active plan to August
  # 2027, by direct debit; reduced: a reduction alone -- not listed.
  let_it_be(:yp) { people(:yp_a_1) }
  let_it_be(:other) { people(:yp_b_1) }
  let_it_be(:planner) { people(:ul_a_1) }
  let_it_be(:long) { people(:ul_a_2) }

  before_all do
    rule = ->(person, status, cents, **attrs) {
      Wsj27RdpFeeRule.create!(people_id: person.id, status: status, custom_installments_starting_year: 2026,
        custom_installments_cents: cents, **attrs).tap do |created|
        person.update!(Wsjrdp2027::ParticipationFee.person_installments_attrs(created)) if status == "active"
      end
    }
    rule.call(yp, "active", [20_000] * 17, activated_at: Time.zone.local(2025, 11, 6, 21, 6))
    rule.call(other, "active", [*([0] * 10), 235_000, 0, 0, 40_000, 0, 0, 40_000],
      custom_installments_payment_method: "credit_transfer", activated_at: Time.zone.local(2026, 10, 1, 16))
    rule.call(other, "planned", [*([15_000] * 12), 80_000, 0, 0, 80_000])
    rule.call(planner, "planned", [20_000] * 17)
    rule.call(long, "active", [*([0] * 10), 1000, *([0] * 8), 1000], activated_at: Time.zone.local(2026, 5, 1, 12))
    Wsj27RdpFeeRule.create!(people_id: people(:yp_a_2).id, status: "active", total_fee_reduction_cents: 170_000,
      activated_at: 1.day.ago)
  end

  def listed = controller.send(:individual_payment_plans).page.map(&:id)

  it "refuses the read tier" do
    sign_in(reader)

    expect { get :index }.to raise_error(CanCan::AccessDenied)
  end

  it "lists the people with a plan, the newest activation first, a planned plan alone last" do
    sign_in(finance)
    get :index

    expect(listed).to eq([other, long, yp, planner].map(&:id))
  end

  it "sizes the strip by the longest plan of the whole list, whatever the filter shows" do
    sign_in(finance)
    get :index, params: {f: "!(!(!(pm,in,'credit_transfer')))"}

    expect(listed).to eq([other.id])
    expect(controller.send(:strip_length)).to eq(21)
  end

  it "applies the filter builder's form and comes back to the page" do
    sign_in(finance)
    post :apply, params: {filter_json: [[["planned", "in", "ja"]]].to_json}

    expect(response).to have_http_status(:see_other)
    expect(CGI.unescape(response.location)).to end_with("/fin/individual_payment_plans?f=!(!(!(pl,in,'ja')))")
  end
end
