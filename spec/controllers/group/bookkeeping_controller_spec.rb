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
  render_views

  let(:extern) { Group::Extern.create!(name: "Extern", parent: groups(:root)) }
  let(:auditor) { Fabricate(Group::Extern::FinanceAuditor.name.to_sym, group: extern).person }
  let(:reader) { Fabricate(Group::Root::FinanceReader.name.to_sym, group: groups(:root)).person }

  def show(group) = get(:show, params: {group_id: group.id})

  it "renders the page with its sub-tab for a unit leader on their own unit" do
    sign_in(people(:ul_a_1))

    show(groups(:unit_a))

    expect(response).to be_successful
    expect(response.body).to include("Buchhaltung")
    expect(response.body).to include(I18n.t("groups.finance.bookkeeping.no_cost_centers"))

    # The sub-tab links to the group once. Without Sheet::Group::Finance#path_args
    # the group would travel twice and the second one would become the format
    # (".../finance/bookkeeping.8").
    tabs = Nokogiri::HTML(response.body).css("ul.nav-sub a").pluck("href")
    expect(tabs).to include(group_finance_bookkeeping_path(groups(:unit_a)))
    expect(response.body).not_to match(%r{/finance/bookkeeping\.\d})
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

  it "renders for the CMT leader on a unit listed in their finance_group_ids" do
    cmt_leader = people(:cmt_leader)
    cmt_leader.update!(finance_group_ids: {groups(:unit_b).id.to_s => "show"})
    sign_in(cmt_leader)

    show(groups(:unit_b))

    expect(response).to be_successful
  end

  it "renders for the audit tier, which is not layer-bound" do
    sign_in(auditor)

    show(groups(:unit_a))

    expect(response).to be_successful
  end

  it "refuses the read tier, which grants nothing on a group" do
    sign_in(reader)

    expect { show(groups(:unit_a)) }.to raise_error(CanCan::AccessDenied)
  end

  # The cost centers of the group (groups.additional_info["cost_center_numbers"],
  # assigned on /fin/admin/group_cost_centers). All numbers and names invented.
  describe "the Kostenstellen block" do
    let!(:cost_center) { WsjrdpCostCenter.create!(number: "A1", name: "Kostenstelle A1") }

    def chips = Nokogiri::HTML(response.body).css("#main .badge")

    before { groups(:unit_a).update!(cost_center_numbers: ["A1"]) }

    # A unit leader reaches the page through their own group and holds nothing
    # in the Finanzen section, so the chip carries no link into it.
    it "shows the unit leader the chips as plain text" do
      sign_in(people(:ul_a_1))

      show(groups(:unit_a))

      expect(response).to be_successful
      expect(chips.text).to include("A1").and include("Kostenstelle A1")
      expect(response.body).not_to include("/fin/bookkeeping/cost_centers/")
    end

    it "shows the unit leader the empty text where nothing is assigned" do
      groups(:unit_a).update!(cost_center_numbers: [])
      sign_in(people(:ul_a_1))

      show(groups(:unit_a))

      expect(response.body).to include(I18n.t("groups.finance.bookkeeping.no_cost_centers"))
      expect(chips).to be_empty
    end

    it "links the chips for somebody who may open a cost center" do
      sign_in(Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person)

      show(groups(:unit_a))

      expect(response).to be_successful
      expect(chips.css("a").pluck("href")).to include(cost_center_path("A1"))
    end
  end
end
