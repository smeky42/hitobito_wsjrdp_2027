# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The person chips of the contingent pages: the mini tags behind the name and
# the contract label of the overview.
describe WsjrdpContingentHelper do
  let(:person) { people(:yp_a_1) }

  before { person.update_columns(contract_status: "confirmed", wsj_role: "YP") }

  def mini_tags(person)
    Nokogiri::HTML.fragment(helper.person_chip(person)).css(".p-chip > span").map(&:text)
  end

  it "shows the role difference in place of the JPT tag" do
    person.update_columns(wsj_role: "JPT")

    expect(mini_tags(person)).to eq(["YP→JPT"])
  end

  it "shows no role tag when the jamboree role goes with the contingent role" do
    expect(mini_tags(person)).to eq([])
  end

  it "shows a person with role and id, the name and the mini tags" do
    person.update_columns(wsj_role: "JPT")
    label = Nokogiri::HTML.fragment(helper.contingent_person_label(person, role: "YP"))

    expect(label.at_css("span.text-muted").text).to eq("YP #{person.id}")
    expect(label.at_css("a").text).to eq(person.short_full_name_with_nickname)
    expect(label.at_css(".tag-role-diff").text).to eq("YP→JPT")
  end

  it "words the contract as the finance lists, a pending one new and none as a muted dash" do
    contract = ->(p) { Nokogiri::HTML.fragment(helper.fin_person_contract(p, words: helper.contingent_contract_words)) }
    person.update_columns(contract_confirmed_at: Time.zone.local(2026, 3, 1))
    confirmed = contract.call(person)
    person.update_columns(contract_status: "replacement_pending")
    pending = contract.call(person)
    person.update_columns(contract_status: "none")
    none = contract.call(person)

    expect(confirmed.at_css(".fin-status-confirmed").text).to eq("in Kraft")
    expect(confirmed.text).to include("01.03.2026") # the date, in the tooltip
    expect(pending.at_css(".fin-status-noted").text).to eq("neu ausstehend")
    expect(none.at_css(".text-muted").text).to eq("—")
  end

  # The IST page loads people with a reduced column list; the chip must render
  # from those columns alone.
  it "renders a chip from the columns the IST page loads" do
    reduced = Person.select(Contingent::WsjrdpIstController::PERSON_COLUMNS).includes(:tags).find(person.id)

    expect { helper.person_chip(reduced) }.not_to raise_error
  end
end
