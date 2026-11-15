# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The contingent pages link a person's name to the person's page only where
# the viewer may open it: a CMT leader gets every link, an eHoC -- who may see
# the pages, not the people -- gets the names on CMT as plain text, except
# their own, on the Übersicht no people at all, and no IST page (nor its tab).
shared_examples "contingent person link helpers" do
  def person_href = %r{\A/people/(\d+)\z}

  def page = Nokogiri::HTML(response.body)

  def person_links = page.css("#main a").select { |a| a["href"].to_s.match?(person_href) }

  def linked_ids = person_links.map { |a| a["href"][person_href, 1].to_i }

  def plain_names = page.css("#main span.p-chip-name, #main span.co-person-name")

  let(:leader) { people(:cmt_leader) }
  let(:ehoc) { Fabricate(Group::Root::ExtendedHeadOfContingent.name.to_sym, group: groups(:root)).person }

  before { ehoc.update_columns(primary_group_id: groups(:root).id) }
end

shared_examples "contingent person links for a CMT leader" do
  include_examples "contingent person link helpers"

  it "links every person for a CMT leader" do
    sign_in(leader)
    get :index

    expect(response).to have_http_status(:ok)
    expect(linked_ids).to include(*expected_ids)
    expect(plain_names).to be_empty
    ability = Ability.new(leader)
    expect(Person.where(id: linked_ids.uniq)).to all(satisfy { |p| ability.can?(:show, p) })
  end
end

shared_examples "contingent person links for an eHoC" do
  include_examples "contingent person link helpers"

  it "shows the page to an eHoC with the names as text, linking only the people they may see" do
    sign_in(ehoc)
    get :index

    expect(response).to have_http_status(:ok)
    ability = Ability.new(ehoc)
    expect(Person.where(id: linked_ids.uniq)).to all(satisfy { |p| ability.can?(:show, p) })
    expect(linked_ids - [ehoc.id]).to be_empty
    expect(plain_names.map { |name| name.text.strip }).to include(*Person.where(id: expected_ids - [ehoc.id])
      .map { |p| chip_text(p) })
  end
end

describe Contingent::WsjrdpContingentController, type: :controller do
  render_views

  # In the default list (no contract in force) and among the role differences.
  let(:expected_ids) { [people(:yp_a_1).id, people(:yp_a_2).id] }

  before do
    people(:yp_a_1).update_columns(wsj_role: "JPT", contract_status: "none", status: "registered")
    people(:yp_a_2).update_columns(contract_status: "none", status: "registered")
  end

  # The overview shows the people only to whoever may see them in full
  # (:index_deep_full_people on the root group); an eHoC gets the figures
  # alone, the matrix's numbers without links into a list that is not there.
  it "shows an eHoC the figures without the people and without links into the list" do
    ehoc = Fabricate(Group::Root::ExtendedHeadOfContingent.name.to_sym, group: groups(:root)).person
    sign_in(ehoc)
    get :index

    page = Nokogiri::HTML(response.body)
    expect(response).to have_http_status(:ok)
    expect(page.at_css("#co-matrix")).to be_present
    expect(page.css("#co-matrix span.co-figure")).not_to be_empty
    expect(page.css("#co-matrix a")).to be_empty
    expect(page.at_css("#co-list")).to be_nil
    expect(page.at_css("#co-role-differences")).to be_nil
    expect(page.css("#main a").pluck("href").grep(%r{\A/people/\d+\z})).to be_empty
  end

  it "links every person and every number of the matrix for a CMT leader" do
    sign_in(people(:cmt_leader))
    get :index

    page = Nokogiri::HTML(response.body)
    expect(page.css("#co-matrix span.co-figure")).to be_empty
    expect(page.css("#co-matrix a.co-figure")).not_to be_empty
    expect(page.at_css("#co-list")).to be_present
    expect(page.at_css("#co-role-differences")).to be_present
    linked = page.css("#main a").pluck("href").grep(%r{\A/people/(\d+)\z}).map { |href| href[/\d+/].to_i }
    expect(linked).to include(*expected_ids)
    expect(page.css("#main span.co-person-name, #main span.p-chip-name")).to be_empty
  end
end

describe Contingent::WsjrdpCmtController, type: :controller do
  render_views

  let(:expected_ids) { [people(:cmt_leader).id, people(:cmt_member1).id, ehoc.id] }

  def chip_text(person) = person.nickname_or_short_first_name

  include_examples "contingent person links for a CMT leader"
  include_examples "contingent person links for an eHoC"

  it "shows the IST tab only to whoever may see the people" do
    tabs = -> { Nokogiri::HTML(response.body).css(".nav-tabs a, .nav a").pluck("href") }
    sign_in(leader)
    get :index
    expect(tabs.call).to include("/contingent/ist")

    sign_in(ehoc)
    get :index
    expect(tabs.call).not_to include("/contingent/ist")
  end
end

describe Contingent::WsjrdpIstController, type: :controller do
  render_views

  # The page reads fixed groups (here "IST Reg", id 4) and shows the chips
  # only while the people links are switched on.
  let(:ist_reg) { Fabricate(Group::Ist.name.to_sym, id: 4, parent: groups(:root), name: "IST Reg") }
  let(:expected_ids) { [people(:ist_a_1).id, people(:ist_a_2).id] }

  def chip_text(person) = person.nickname_or_short_first_name

  before do
    Person.where(id: expected_ids).update_all(primary_group_id: ist_reg.id, wsj_role: "IST")
    request.cookies[:contingent_show_people_links] = "true"
  end

  include_examples "contingent person links for a CMT leader"

  it "stays closed to an eHoC, who may not see the people" do
    sign_in(ehoc)

    expect { get :index }.to raise_error(CanCan::AccessDenied)
  end
end
