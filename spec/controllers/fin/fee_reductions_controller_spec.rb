# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The Reduktionen tab of the Beiträge area: every person with an active or a
# planned total fee reduction, for the audit tier and up.
describe Fin::FeeReductionsController do
  let(:finance) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let(:yp) { people(:yp_a_1) }
  let(:other) { people(:yp_b_1) }
  let(:planner) { people(:ul_a_1) }

  def listed = controller.send(:fee_reductions).page.map(&:id)

  it "lists the people with an active or a planned reduction, by the activation, a plan alone after all" do
    with_versioning do
      PaperTrail.request(whodunnit: finance.id.to_s) { yp.update!(wsjrdp_total_fee_reduction: 300) }
    end
    planner.update!(planned_total_fee_reduction: "400")
    sign_in(finance)
    get :index

    expect(listed).to eq([yp.id, planner.id])
  end

  it "applies the filter of the URL" do
    yp.update!(wsjrdp_total_fee_reduction: 250)
    planner.update!(planned_total_fee_reduction: "400")
    sign_in(finance)
    get :index, params: {f: "!(!(!(pl,in,'ja')))"}

    expect(listed).to eq([planner.id])
  end

  it "is closed to the finance read tier" do
    sign_in(Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person)

    expect { get :index }.to raise_error(CanCan::AccessDenied)
  end
end
