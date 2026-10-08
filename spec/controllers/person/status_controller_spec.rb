# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The status tab names the fee arrangements and links to the Beitrag page,
# where they are maintained: the installment plan in effect in two lines, the
# total fee reduction in one. It plans and activates nothing itself.
describe Person::StatusController, type: :controller do
  render_views

  let(:manager) { Fabricate(Group::Root::FinanceManager.name.to_sym, group: groups(:root)).person }
  let(:person) { people(:yp_a_1) }

  def rule(status, **attrs)
    Wsj27RdpFeeRule.create!(people_id: person.id, status: status,
      custom_installments_starting_year: 2026, custom_installments_cents: [0, 10_000],
      custom_installments_issue: "HELP-1", custom_installments_comment: "Vereinbarung", **attrs)
  end

  before do
    sign_in(manager)
    rule("active", activated_at: 1.day.ago, custom_installments_payment_method: "credit_transfer")
    person.update!(Wsjrdp2027::ParticipationFee.person_installments_attrs(person.active_fee_rule))
  end

  it "shows the plan in effect in two lines with a link, on the page and in the form, nothing to plan" do
    rule("planned", custom_installments_cents: [0, 0, 5_000])

    %i[show edit].each do |action|
      get action, params: {group_id: person.primary_group_id, id: person.id}

      lines = Nokogiri::HTML(response.body).css("dt").find { |dt| dt.text.strip == "Ratenplan" }.next_element
      expect(lines.text).to include("2026-02: 100€").and include("Überweisung")
      expect(lines.at_css("a[href='#{person_fee_path(person, anchor: "payment_plan_#{person.id}")}']")).to be_present
      # The planned plan, its fields and buttons live on the Beitrag page.
      expect(response.body).not_to include("planned_custom_installments")
      expect(response.body).not_to include("2026-03: 50€")
    end
  end

  describe "total fee reduction" do
    before { person.update!(wsjrdp_total_fee_reduction: 500, wsjrdp_total_fee_reduction_hint: "Härtefall") }

    it "names it and links to the Beitrag page, on the page and in the form" do
      %i[show edit].each do |action|
        get action, params: {group_id: person.primary_group_id, id: person.id}

        expect(response.body).to include("Härtefall: reduziert um 500€")
        expect(response.body).to include(person_fee_path(person, anchor: "total_fee_#{person.id}"))
        expect(response.body).not_to include("planned_total_fee_reduction")
      end
    end
  end
end
