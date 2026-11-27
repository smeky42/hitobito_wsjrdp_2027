# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The cells of Kontingent > Units: balance, budget and helpdesk tickets.
describe WsjrdpContingentHelper do
  def text(html) = Nokogiri::HTML.fragment(html.to_s).text.squish

  it "writes a unit's balance, the number alone without movements, marked where it does not add up" do
    aggregate_failures do
      expect(text(helper.contingent_balance_sum(10, 0, 0, 10))).to eq("10")
      expect(text(helper.contingent_balance_sum(10, 4, 1, 7))).to eq("10 −4 +1 = 7")
      expect(text(helper.contingent_balance_sum(10, 2, 0, 9))).to eq("10 −2 = 8 ≠ 9")
    end
  end

  it "writes a unit's budget, the sum with the open Einbehalt below, nothing at 0 €" do
    with_pending = Nokogiri::HTML.fragment(helper.contingent_unit_budget(-9_500, 255_000).to_s)

    aggregate_failures do
      expect(with_pending.at_css(".co-budget").text.squish).to eq("−95,00 €")
      expect(with_pending.at_css(".co-budget-pending").text.squish).to eq("+2.455,00 €")
      expect(text(helper.contingent_unit_budget(-4_000, 0))).to eq("−40,00 €")
      expect(helper.contingent_unit_budget(0, 0)).to eq("")
    end
  end

  it "links each helpdesk ticket key of a field, and nothing else" do
    entry = Struct.new(:name, :deregistration_issue)

    links = helper.contingent_ticket_links(entry.new("X", "https://helpdesk.worldscoutjamboree.de/browse/HELP-78, HELP-77"),
      :deregistration_issue)

    expect(links.map { |link| Nokogiri::HTML.fragment(link).at_css("a")[:href] }).to eq(
      %w[https://helpdesk.worldscoutjamboree.de/browse/HELP-78 https://helpdesk.worldscoutjamboree.de/browse/HELP-77]
    )
    expect(helper.contingent_ticket_links(entry.new("X", "kein Ticket"), :deregistration_issue)).to be_empty
  end
end
