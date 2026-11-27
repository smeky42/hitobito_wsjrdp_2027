# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# A Beitragsbuchung and its person as the finance pages name them. Both hang on
# one question: may the viewer see the entry's PERSON? The entry's label
# carries that person's description and amount, so without it the entry is
# named by its bare id and the person by name alone.
describe Fin::LinkedEntryHelper do
  before_all(setup_fixtures: true) {}

  let_it_be(:accountant) { Fabricate(Group::Root::Finance.name.to_sym, group: groups(:root)).person }
  let_it_be(:auditor) do
    extern = Group::Extern.create!(name: "Extern", parent: groups(:root))
    Fabricate(Group::Extern::FinanceAuditor.name.to_sym, group: extern).person
  end
  let_it_be(:entry) do
    AccountingEntry.create!(subject: people(:yp_a_1), author: accountant,
      amount_cents: 10_000, amount_currency: "EUR", description: "Teilnahmebeitrag",
      value_date: Date.new(2026, 2, 1), booking_date: Date.new(2026, 2, 1))
  end

  def as(person)
    helper.extend(FormatHelper)
    ability = Ability.new(person)
    allow(helper).to receive(:can?) { |*args| ability.can?(*args) }
  end

  def fragment(html) = Nokogiri::HTML.fragment(html.to_s)

  it "links the person and the entry for the write tier" do
    as(accountant)

    aggregate_failures do
      expect(fragment(helper.fin_entry_link(entry)).at_css("a")["href"]).to eq("/fin/ae/#{entry.id}")
      expect(fragment(helper.fin_entry_link(entry)).text).to include("Teilnahmebeitrag")
      expect(fragment(helper.fin_subject_link(entry.subject)).at_css("a")).to be_present
    end
  end

  it "gives the auditor the name and a bare id -- no link, no entry data" do
    as(auditor)

    aggregate_failures do
      expect(helper.fin_entry_link(entry)).to eq("##{entry.id}")
      subject_link = fragment(helper.fin_subject_link(entry.subject))
      expect(subject_link.at_css("a")).to be_nil
      expect(subject_link.text).to eq(people(:yp_a_1).short_full_name_with_nickname)
    end
  end
end
