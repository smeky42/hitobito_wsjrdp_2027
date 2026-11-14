# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Kontingent > Übersicht: the jamboree comparison, the matrix, the tiles, the
# people list (an expandable table with the Schnellauswahl) and the role
# differences. Matrix cells set the list's filter.
describe Contingent::WsjrdpContingentController, type: :controller do
  render_views

  let(:schema) { Wsjrdp2027::ContingentPeopleFilterSchema }
  let(:admin) { Fabricate(Group::Root::Admin.name.to_sym, group: groups(:root)).person }
  let(:waitlist) { groups(:empty_unit) }
  let(:cancelled) { people(:yp_a_2) }

  before do
    waitlist.update_columns(name: "YP Warteliste", is_wsjrdp: false)
    cancelled.update_columns(status: "deregistration_noted", contract_status: "confirmed",
      primary_group_id: waitlist.id, nickname: "Cleo")
    sign_in(admin)
  end

  def page = Nokogiri::HTML(response.body)

  def rows = page.css("tr.exp-row")

  def cell(row, key) = row.at_css("td[data-colkey='#{key}']").text.squish

  def filter_param = described_class::PEOPLE_POLICY.param_name(:filter)

  # The position of a matrix column in the stripe row: Rolle first.
  def column_index(key) = 1 + Wsjrdp2027::ContingentOverview::MATRIX_COLUMNS.keys.index(key)

  def wire(tree) = schema.encode_tree(tree, schema: schema.bound).to_s

  it "shows the jamboree comparison first and by default the people not settled yet" do
    get :index

    expect(response).to have_http_status(:ok)
    expect(page.at_css("#main h2").text).to eq("Abgleich mit der Jamboree-Anmeldung")
    expect(page.css("#co-jamboree-tiles .co-tiles").map { |line| line.css(".co-t").map { |t| t.xpath("text()").text.strip } })
      .to eq([["CMT", "IST", "CMT + IST"], ["Units", "Patrols", "UL + YP"]])
    expect(page.css("a.co-tile")).to be_empty
    first = rows.first
    expect(cell(first, "person")).to start_with("YP #{cancelled.id} ").and include("Cleo")
    expect(first.at_css("td[data-colkey='contract'] .fin-status-confirmed").text).to eq("in Kraft")
    expect(first.at_css("td[data-colkey='status'] .fin-status-noted").text).to eq("Abmeldung")
    expect(cell(first, "status")).to include("Abmeldung Vermerkt") # the full label, in the tooltip
    expect(cell(first, "reason")).to eq("In Abmeldung")
    expect(cell(first, "group")).to eq("YP Warteliste")
  end

  it "counts the CMT with a contract, adds the ones without as +n and warns about them" do
    people(:cmt_member1).update_columns(wsj_role: "CMT", status: "upload", contract_status: "replacement_pending")
    people(:cmt_member2).update_columns(wsj_role: "CMT", status: "registered", contract_status: "none")
    rows = Wsjrdp2027::ContingentOverview.new.jamboree_rows
    figure = ->(key) { [rows[key][:counts]["inforce"] - rows[key][:pending], rows[key][:counts]["none"] + rows[key][:pending]] }

    get :index

    tiles = page.css("#co-jamboree-tiles .co-tile")
    shown = ->(tile) { [tile.at_css(".co-n").xpath("text()").text.to_i, tile.at_css(".co-more")&.text.to_s.delete("+").to_i] }
    expect(tiles.first.at_css(".co-t").text).to eq("CMT")
    expect(shown.call(tiles.first)).to eq(figure.call("CMT"))
    expect(shown.call(tiles[2])).to eq(figure.call("CMT").zip(figure.call("IST")).map(&:sum))
    lines = tiles.first.css(".co-sub").map { |line| line.text.squish }
    expect(lines).to include(a_string_ending_with("ohne Vertrag"), "1 neu ausstehend")
    expect(tiles.first.css(".co-sub .text-warning").size).to eq(2)
  end

  it "shows the patrols to fill, four a unit, and warns about the ones not given out" do
    get :index

    units = Wsjrdp2027::ContingentOverview.new.unit_figures
    patrols = page.css("#co-jamboree-tiles .co-tile").find { |tile| tile.at_css(".co-t").text == "Patrols" }
    expect(patrols.at_css(".co-n").text.to_i).to eq(units[:units][:total] * 4)
    ul_yp = page.css("#co-jamboree-tiles .co-tile").find { |tile| tile.at_css(".co-t").text == "UL + YP" }
    expect(ul_yp.at_css(".co-n").text.squish).to include("/ #{units[:units][:total] * 40}")
    if units[:units][:total] * 4 > units[:patrols][:total]
      expect(patrols.at_css(".co-sub").text).to include("noch nicht eingeteilt")
    end
  end

  it "rings the matrix cells that show a tile's number" do
    get :index

    overview = Wsjrdp2027::ContingentOverview.new
    marks = overview.matrix_tile_marks(overview.matrix_rows)
    ringed = page.css("#co-matrix td.co-tile-mark")
    expect(ringed.size).to eq(marks.size)
    ringed.each do |td|
      tile = td["title"][/„(.+)“/, 1]
      spec = Wsjrdp2027::ContingentOverview::PEOPLE_TILES.fetch(tile)
      expect(td.text.to_i).to eq(overview.tile_in_force(*spec[:jamboree]))
    end
  end

  it "marks under the matrix head what each sum adds up" do
    get :index

    cells = page.css("#co-matrix tr.co-stripes th")
    kinds = ->(key) { cells[column_index(key)].css(".co-stripe").map { |stripe| stripe["class"].split.last } }
    expect(kinds.call("full")).to eq(%w[co-stripe-add co-stripe-add])
    expect(kinds.call("inforce")).to eq(%w[co-stripe-sum])
    expect(kinds.call("cancel")).to eq([])
    expect(kinds.call("none")).to eq(%w[co-stripe-add])
    expect(kinds.call("ended")).to eq([])
  end

  it "offers the Schnellauswahl" do
    get :index

    presets = page.css(".flt-preset").map { |a| a.text.squish }
    expect(presets).to include("Widersprüchlich", "Zu prüfen", "Neuer Vertrag", "Unterlagen offen",
      "in Abmeldung", "WSJRDP-Gruppen", "Wartelisten", "Rolle abweichend")
  end

  it "lists the people of a matrix cell" do
    people(:yp_a_1).update_columns(status: "confirmed", contract_status: "confirmed", nickname: "Yara")

    get :index, params: {filter_param => wire(schema.cell_tree("full", roles: %w[YP]))}

    expect(rows.map { |row| cell(row, "person") }).to include(a_string_including("Yara"))
    expect(rows.map { |row| cell(row, "role") }.uniq).to eq(["YP"])
    expect(page.css("#co-matrix a").pluck("href")).to all(include(filter_param))
  end

  it "lists the people of a patrol, with the patrol column on demand" do
    groups(:unit_a).update_columns(is_wsjrdp: true)
    people(:yp_a_1).update_columns(patrol: "C", nickname: "Pia")
    cols_param = described_class::PEOPLE_POLICY.param_name(:cols)

    get :index, params: {filter_param => wire([[["patrol", "in", "#{groups(:unit_a).id}-C"]]]),
                         cols_param => "p,c,pt"}

    expect(rows.map { |row| cell(row, "person") }).to contain_exactly(a_string_including("Pia"))
    expect(cell(rows.first, "patrol")).to eq("C")
  end

  it "shows the people whose jamboree role differs, with the tag on their chip" do
    people(:yp_a_1).update_columns(wsj_role: "JPT", nickname: "Jule")

    get :index

    row = page.css("#co-role-differences tbody tr").find { |tr| tr.css("td").first(2).map { |td| td.text.strip } == %w[YP JPT] }
    expect(row).to be_present
    expect(row.at_css(".tag-role-diff").text).to eq("YP→JPT")
  end

  it "redirects the filter builder to the overview with the filter" do
    post :apply, params: {filter_json: [[["need", "in", "review"]]].to_json}

    expect(response).to have_http_status(:see_other)
    expect(response.location).to start_with("#{contingent_contingent_url}?")
    expect(response.location).to include("#{filter_param}=")
  end
end
