# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Kontingent > Units: one row per WSJRDP unit with the people whose contract
# is in force (bestätigt / offen / Summe) and the movements since the unit was
# formed (verlassen / getauscht / nachgerückt, or by day) with their balance;
# a row opens the unit's people. Visible like the IST tab: only to whoever may
# see the contingent's people.
describe Contingent::WsjrdpUnitsController, type: :controller do
  render_views

  let(:leader) { people(:cmt_leader) }
  let(:unit_a) { groups(:unit_a) }

  def page = Nokogiri::HTML(response.body)

  def unit_tr(name) = page.css("tbody tr").find { |tr| tr.at_css("td")&.text&.strip == name }

  # The cells of a unit's row by column key.
  def unit_row(name)
    unit_tr(name).css("td").to_h { |td| [td["class"].to_s[/uncol-(\w+)/, 1], td.text.squish] }
  end

  # The balance of a unit: the sum, and the second line ("2 in Abm.").
  def balance(name)
    cell = unit_tr(name).at_css("td.uncol-balance")
    [cell.at_css(".co-balance").text.squish, cell.at_css(".co-balance-pending")&.text&.squish]
  end

  # The movements of a cell: [kind, the visible words of the line] -- the
  # kind by the icon's colour class (WsjrdpContingentHelper::MOVEMENT_ICONS),
  # the tooltip left out.
  def movement_lines(name, key)
    kinds = {"co-move-in" => :arrived, "co-move-out" => :deregistered, "co-move-wait" => :cancelling,
             "co-move-swap" => :swapped, "co-move-moved" => :moved}
    unit_tr(name).at_css("td.uncol-#{key}").css(".co-move").map do |line|
      [kinds.values_at(*line.at_css(".co-move-icon")["class"].split).compact.first, line.text.squish]
    end
  end

  def unit_person(nickname, contract_status:, status:)
    person = Fabricate(Group::Unit::Member.name.to_sym, group: unit_a).person
    person.update_columns(primary_group_id: unit_a.id, nickname: nickname, contract_status: contract_status,
      status: status)
    person
  end

  before do
    Person.where(primary_group_id: unit_a.id).update_all(contract_status: "none", status: "registered")
    unit_person("Ba", contract_status: "confirmed", status: "confirmed")
    unit_person("Bb", contract_status: "confirmed", status: "confirmed")
    unit_person("Oa", contract_status: "confirmed", status: "reviewed")
    # In Abmeldung, whatever the contract -- and not in force with it.
    unit_person("Ca", contract_status: "confirmed", status: "deregistration_noted")
    unit_person("Cb", contract_status: "none", status: "deregistration_noted")
  end

  it "counts a unit's people by contract and Abmeldung" do
    sign_in(leader)

    get :index, params: {unv: "columns"}

    expect(response).to have_http_status(:ok)
    row = unit_row("Unit A")
    expect(row.slice("name", "confirmed", "open", "in_force"))
      .to eq("name" => "Unit A", "confirmed" => "2", "open" => "1", "in_force" => "3")
    # In Abmeldung, still in the unit: a line under verlassen, not counted yet.
    lines = movement_lines("Unit A", "left")
    expect(lines.map(&:first)).to eq(%i[cancelling cancelling])
    expect(lines.map(&:last).join).to include(*Person.where(nickname: %w[Ca Cb]).pluck(:id).map { |id| "##{id}" })
    # Ca and Cb are in Abmeldung: gone from "jetzt" already, like from
    # "Vertrag in Kraft"; the note says how many.
    sum, pending = balance("Unit A")
    expect(sum).to match(/\A(\d+) −2 = (\d+)\z/)
    expect(sum[/= (\d+)/, 1].to_i).to eq(sum.to_i - 2)
    expect(pending).to eq("2 in Abm.")
    expect(movement_lines("Unit A", "swapped")).to be_empty
    expect(movement_lines("Unit A", "arrived")).to be_empty
  end

  it "counts the leaving for the unit they were in last, and links the helpdesk tickets" do
    waiting_list = Fabricate(Group::Unit.name.to_sym, parent: groups(:root), name: "YP Warteliste")
    waiting_list.update_columns(is_wsjrdp: false)
    cancelling = Fabricate(Group::Unit::Member.name.to_sym, group: waiting_list).person
    cancelling.update_columns(primary_group_id: waiting_list.id, nickname: "Wa", status: "deregistration_noted",
      contract_status: "confirmed", additional_info: {"deregistration_issue" => "HELP-77"})
    Fabricate(Group::Unit::Member.name.to_sym, group: unit_a, person: cancelling,
      start_on: Date.new(2026, 1, 7), end_on: Date.new(2026, 10, 30))
    deregistered = unit_person("De", contract_status: "ended", status: "deregistered")
    deregistered.update_columns(contract_ended_at: Time.zone.local(2026, 4, 16, 12),
      additional_info: {"deregistration_issue" => "https://helpdesk.worldscoutjamboree.de/browse/HELP-78"})
    successor = unit_person("Su", contract_status: "confirmed", status: "confirmed")
    successor.update_columns(additional_info: {"late_confirmation_issue" => "HELP-79"})
    # Nachgerückt only after the unit was formed (07.01.2026 while the unit stores none).
    successor.roles.where(group_id: unit_a.id).update_all(start_on: Date.new(2026, 3, 1))
    unit_person("Nt", contract_status: "confirmed", status: "confirmed")
      .update_columns(additional_info: {"late_confirmation_issue" => "kein Ticket"})
    sign_in(leader)

    get :index, params: {unv: "columns"}

    # A line per movement: icon, day, "#<id>", the ticket linked in brackets.
    left = movement_lines("Unit A", "left")
    expect(left).to include([:cancelling, "30.10.26 ##{cancelling.id} (HELP-77)"],
      [:deregistered, "16.04.26 ##{deregistered.id} (HELP-78)"])
    expect(movement_lines("Unit A", "arrived")).to eq([[:arrived, "01.03.26 ##{successor.id} (HELP-79)"]])
    # Gone: De, and Wa, Ca and Cb in Abmeldung -- whether their role in the
    # unit has ended or not; the note counts the three open deregistrations.
    sum, pending = balance("Unit A")
    expect(sum).to match(/\A(\d+) −4 \+1 = (\d+)\z/)
    expect(sum[/= (\d+)/, 1].to_i).to eq(sum.to_i - 3)
    expect(pending).to eq("3 in Abm.")
    expect(page.css("tbody a[href='/people/#{deregistered.id}']").map(&:text)).to include("##{deregistered.id}")
    links = page.css("tbody a[href^='https://helpdesk']").map { |a| a.attr("href") }
    expect(links).to include("https://helpdesk.worldscoutjamboree.de/browse/HELP-77",
      "https://helpdesk.worldscoutjamboree.de/browse/HELP-78")

    get :show, params: {id: unit_a.id}

    wa = page.css(".contingent-unit-people tbody tr").find { |tr| tr.text.include?("/ Wa") }
    expect(wa.text.squish).to include("zuletzt Unit A, jetzt YP Warteliste")
    expect(wa.at_css("a[href='/groups/#{waiting_list.id}']").text).to eq("YP Warteliste")
    # In Abmeldung: the icon, the ticket linked behind it.
    ticket = wa.at_css("td.upcol-cancel a")
    expect(ticket.text).to eq("HELP-77")
    expect(ticket["href"]).to eq("https://helpdesk.worldscoutjamboree.de/browse/HELP-77")
    expect(wa.at_css("td.upcol-cancel .co-cancel-icon")).to be_present
  end

  # A unit with one person whose contract is in force -- or several, or
  # one in Abmeldung on top.
  def unit_with_people(name, in_force: 1, cancelling: 0)
    unit = Fabricate(Group::Unit.name.to_sym, parent: groups(:root), name: name)
    in_force.times do
      person = Fabricate(Group::Unit::Member.name.to_sym, group: unit).person
      person.update_columns(primary_group_id: unit.id, contract_status: "confirmed", status: "confirmed")
    end
    cancelling.times do
      person = Fabricate(Group::Unit::Member.name.to_sym, group: unit).person
      person.update_columns(primary_group_id: unit.id, contract_status: "confirmed", status: "deregistration_noted")
    end
    unit
  end

  def shown_units = page.css("tbody tr td:first-child a").map { |a| a.text.strip }

  it "lists the WSJRDP units with people in force only, in a natural order of their names" do
    groups(:unit_b).update_columns(is_wsjrdp: false)
    unit_with_people("A10")
    unit_with_people("A2")
    unit_with_people("A3", in_force: 0, cancelling: 1)
    sign_in(leader)

    get :index, params: {unv: "columns"}

    expect(shown_units).not_to include("Unit B", "Empty Unit", "A3")
    expect(shown_units & %w[A2 A10]).to eq(%w[A2 A10])
  end

  it "narrows the list by the Schnellauswahl: a series, a check, or both" do
    unit_with_people("A1", in_force: Group::DEFAULT_EXPECTED_UNIT_SIZE)
    unit_with_people("A2")
    unit_with_people("B1", in_force: Group::DEFAULT_EXPECTED_UNIT_SIZE, cancelling: 1)
    sign_in(leader)

    get :index, params: {unf: "!(!(!(se,in,'A')))"}
    expect(shown_units).to eq(%w[A1 A2])

    get :index, params: {unf: "!(!(!(ch,in,'1')))"}
    expect(shown_units).to include("A2", "Unit A")
    expect(shown_units).not_to include("A1", "B1")

    get :index, params: {unf: "!(!(!(se,in,'B')),!(!(ch,in,'2')))"}
    expect(shown_units).to eq(%w[B1])
    expect(page.text).to include("Schnellauswahl", "A-Units", "K-Units", "Summe ≠ Soll-Größe", "offene Abmeldungen")
  end

  it "compares the people in force with the size the unit is to have, not the one at the Unit-Einteilung" do
    a1 = unit_with_people("A1", in_force: 38)
    a1.update!(expected_unit_size: 38, initial_unit_size: 40)
    a2 = unit_with_people("A2", in_force: 40)
    a2.update!(expected_unit_size: 38, initial_unit_size: 40)
    sign_in(leader)

    get :index, params: {unf: "!(!(!(ch,in,'1')))"}

    expect(shown_units).to include("A2")
    expect(shown_units).not_to include("A1")
  end

  it "counts the people in force without a patrol, says how many units are not divided, and selects them" do
    divided = unit_with_people("P1", in_force: 2)
    Person.where(primary_group_id: divided.id).update_all(patrol: "A")
    unit_with_people("P3", in_force: 2)
    partly = unit_with_people("P2", in_force: 3, cancelling: 1)
    Person.where(primary_group_id: partly.id).order(:id).first.update_columns(patrol: "B")
    sign_in(leader)

    get :index, params: {unv: "columns"}

    expect(unit_row("P1")["without_patrol"]).to eq("0")
    # Who is in Abmeldung does not count, though without a patrol.
    expect(unit_row("P2")["without_patrol"]).to eq("2")
    # Orange where some have a patrol, red where nobody has one.
    expect(unit_tr("P2").at_css("td.uncol-without_patrol .co-patrol-partly")).to be_present
    expect(unit_tr("P3").at_css("td.uncol-without_patrol .co-patrol-unset").text).to eq("2")
    expect(unit_tr("P1").at_css("td.uncol-without_patrol .text-muted")).to be_present
    expect(page.css("thead th").map(&:text).join).to include("Patrol nicht gesetzt")
    incomplete = page.css("tbody td.uncol-without_patrol").count { |td| td.text.strip.to_i.positive? }
    expect(page.text).to include("#{incomplete} mit unvollständiger Patrol-Einteilung")

    get :index, params: {unf: "!(!(!(ch,in,'3')))"}
    expect(shown_units).to include("P2")
    expect(shown_units).not_to include("P1")
    expect(page.text).to include("Patrols unvollständig")
  end

  it "shows a unit's people in Abmeldung first, then without a contract in force, then not confirmed, " \
     "the deregistered last" do
    leader_of_unit = Fabricate(Group::Unit::Leader.name.to_sym, group: unit_a).person
    leader_of_unit.update_columns(primary_group_id: unit_a.id, nickname: "Zz", contract_status: "confirmed",
      status: "confirmed")
    unit_person("De", contract_status: "ended", status: "deregistered")
    sign_in(leader)

    get :show, params: {id: unit_a.id}

    rows = page.css(".contingent-unit-people tbody tr")
    names = rows.map { |tr| tr.at_css("td.cocol-person").text.squish }
    # The person's id stands after the role in the person cell.
    ids = rows.map { |tr| tr.at_css("td.cocol-person").text[/\b(\d+)\b/, 1].to_i }
    shown = Person.where(id: ids).index_by(&:id).values_at(*ids)
    order = shown.map do |p|
      leaving = {"deregistration_noted" => 0, "deregistered" => 2}.fetch(p.status, 1)
      [leaving, (p.contract_status == "confirmed") ? 1 : 0, (p.status == "confirmed") ? 1 : 0]
    end
    expect(order).to eq(order.sort)
    expect(names.last).to include("/ De")
    expect(page.at_css(".contingent-unit-people h3").text.strip).to eq("Personen in Unit A")
    # The people staying, then those leaving.
    staying = shown.count { |p| %w[deregistration_noted deregistered].exclude?(p.status) }
    expect(page.text).to include("#{staying} Personen + 2 in Abmeldung + 1 abgemeldet")
    expect(names.first(2).join).to include("/ Ca", "/ Cb")
    # Among the people confirmed with a contract in force, the leader first.
    expect(names.index { |n| n.start_with?("#{leader_of_unit.id} ") }).to be < names.index { |n| n.include?("/ Ba") }

    ca = rows.find { |tr| tr.at_css("td.cocol-person").text.include?("/ Ca") }
    expect(ca.at_css("td.upcol-cancel .co-cancel-icon")["title"]).to eq("in Abmeldung")
    expect(rows.find { |tr| tr.at_css("td.cocol-person").text.include?("/ Ba") }.at_css("td.upcol-cancel .co-cancel-icon")).to be_nil
    # The word, then its tooltip (the full label).
    expect(ca.at_css("td.cocol-contract").text.squish).to start_with("in Kraft")
    expect(ca.at_css("td.cocol-status").text.squish).to start_with("Abmeldung")
  end

  it "narrows a unit's people by the bare patrol letter or by no patrol set" do
    Person.where(nickname: "Ba").update_all(patrol: "A")
    sign_in(leader)
    nicks = -> { page.css(".contingent-unit-people td.cocol-person").map { |td| td.text[%r{/ (\w+)}, 1] } }

    get :show, params: {id: unit_a.id, upf: "!(!(!(pt,in,'A')))"}
    expect(nicks.call).to eq(%w[Ba])

    get :show, params: {id: unit_a.id, upf: "!(!(!(pt,in,'none')))"}
    expect(nicks.call).to include("Bb", "Oa")
    expect(nicks.call).not_to include("Ba")
    expect(page.text).to include("Patrol nicht gesetzt")
    options = Wsjrdp2027::ContingentUnitPeopleFilterSchema::PATROL_OPTIONS.pairs.map(&:first)
    expect(options).to eq(%w[none A B C D])
  end

  it "narrows a unit's people by role and contract, and applies its filter back into the unit" do
    leader_of_unit = Fabricate(Group::Unit::Leader.name.to_sym, group: unit_a).person
    leader_of_unit.update_columns(primary_group_id: unit_a.id, nickname: "Zz", contract_status: "confirmed",
      status: "confirmed")
    sign_in(leader)

    get :show, params: {id: unit_a.id, upf: "!(!(!(ro,in,'UL')))"}
    names = page.css(".contingent-unit-people tbody tr").map { |tr| tr.text.squish }
    expect(names).to all(include("UL "))
    expect(names.join).to include("/ Zz")

    get :show, params: {id: unit_a.id, upf: "!(!(!(vs,in,'cancel')))"}
    names = page.css(".contingent-unit-people tbody tr").map { |tr| tr.text.squish }
    expect(names.size).to eq(2)
    expect(names.join).to include("/ Ca", "/ Cb")

    post :apply, params: {id: unit_a.id, expandable_table_level: 1,
                          filter_json: [[["wsjrdp_role", "in", "UL"]]].to_json}
    expect(response).to have_http_status(:see_other)
    expect(response.location).to start_with("http://test.host/contingent/units/#{unit_a.id}?")
    expect(response.location).to include("expandable_table_level=1", "upf=")
  end

  it "counts who came after the unit was formed as nachgerückt, with where from, and shows since when" do
    waiting_list = Fabricate(Group::Unit.name.to_sym, parent: groups(:root), name: "YP Warteliste")
    waiting_list.update_columns(is_wsjrdp: false)
    successor = unit_person("Nr", contract_status: "confirmed", status: "confirmed")
    successor.update_columns(contract_confirmed_at: Time.zone.local(2026, 3, 9, 12))
    successor.roles.where(group_id: unit_a.id).update_all(start_on: Date.new(2026, 3, 25))
    Fabricate(Group::Unit::Member.name.to_sym, group: waiting_list, person: successor,
      start_on: Date.new(2025, 12, 7), end_on: Date.new(2026, 3, 8))
    # On a waiting list only after joining the unit: no successor.
    later = unit_person("La", contract_status: "confirmed", status: "confirmed")
    later.roles.where(group_id: unit_a.id).update_all(start_on: Date.new(2026, 1, 7))
    Fabricate(Group::Unit::Member.name.to_sym, group: waiting_list, person: later,
      start_on: Date.new(2026, 2, 1), end_on: Date.new(2026, 2, 2))
    sign_in(leader)

    get :index, params: {unv: "columns"}

    # No ticket: the person and where they came from.
    expect(movement_lines("Unit A", "arrived")).to eq([[:arrived, "25.03.26 ##{successor.id} YP WL"]])
    expect(unit_tr("Unit A").at_css("td.uncol-arrived a[href='/groups/#{waiting_list.id}']")).to be_present

    get :show, params: {id: unit_a.id, ups: "js~", upc: "ro,p,c,s,cs,js"}

    rows = page.css(".contingent-unit-people tbody tr")
    first = rows.first
    expect(first.at_css("td.cocol-person").text).to include("/ Nr")
    expect(first.at_css("td.upcol-confirmed_at").text.strip).to eq("09.03.2026")
    expect(first.at_css("td.upcol-joined").text.strip).to eq("25.03.2026")
  end

  it "counts nobody as nachgerückt who joined on the day the unit was formed or before" do
    unit_a.update!(unit_formed_date: "01.02.2026")
    on_the_day = unit_person("Od", contract_status: "confirmed", status: "confirmed")
    on_the_day.update_columns(additional_info: {"late_confirmation_issue" => "HELP-80"})
    on_the_day.roles.where(group_id: unit_a.id).update_all(start_on: Date.new(2026, 2, 1))
    after = unit_person("Af", contract_status: "confirmed", status: "confirmed")
    after.update_columns(additional_info: {"late_confirmation_issue" => "HELP-81"})
    after.roles.where(group_id: unit_a.id).update_all(start_on: Date.new(2026, 2, 2))
    sign_in(leader)

    get :index, params: {unv: "columns"}

    expect(movement_lines("Unit A", "arrived")).to eq([[:arrived, "02.02.26 ##{after.id} (HELP-81)"]])
  end

  it "counts who left the unit without deregistering as gewechselt, at the end of its people" do
    other = groups(:unit_b)
    moved = unit_person("Mv", contract_status: "confirmed", status: "confirmed")
    moved.roles.where(group_id: unit_a.id).update_all(start_on: Date.new(2026, 1, 7), end_on: Date.new(2026, 3, 1))
    Fabricate(Group::Unit::Member.name.to_sym, group: other, person: moved, start_on: Date.new(2026, 3, 2))
    moved.update_columns(primary_group_id: other.id)
    # Still in the unit with another role: not gewechselt.
    stays = unit_person("St", contract_status: "confirmed", status: "confirmed")
    stays.roles.where(group_id: unit_a.id).update_all(end_on: Date.new(2026, 3, 1))
    Fabricate(Group::Unit::Leader.name.to_sym, group: unit_a, person: stays, start_on: Date.new(2026, 3, 2))
    sign_in(leader)

    get :index, params: {unv: "columns"}

    expect(movement_lines("Unit A", "left")).to include([:moved, "01.03.26 ##{moved.id} Unit B"])
    expect(movement_lines("Unit A", "left").map(&:last).join).not_to include("##{stays.id}")
    expect(unit_tr("Unit A").at_css("td.uncol-left a[href='/groups/#{other.id}']").text).to eq("Unit B")
    # For the other unit a newcomer, from here.
    expect(movement_lines("Unit B", "arrived")).to include([:arrived, "02.03.26 ##{moved.id} Unit A"])

    get :show, params: {id: unit_a.id}

    names = page.css(".contingent-unit-people tbody tr").map { |tr| tr.at_css("td.cocol-person").text.squish }
    expect(names.join).not_to include("/ Mv")

    get :show, params: {id: unit_a.id, upu: "moved.shown"}

    rows = page.css(".contingent-unit-people tbody tr")
    mv = rows.last
    expect(mv.at_css("td.cocol-person").text.squish).to include("/ Mv", "gewechselt, bis 01.03.2026 hier, jetzt Unit B")
    # Gone from the unit: the role muted and struck through, no patrol, no joining day.
    expect(mv.at_css("td.upcol-role .text-decoration-line-through").text).to eq("YP")
    expect(mv.at_css("td.upcol-patrol").text.strip).to eq("")
    rows = rows.map { |tr| tr.at_css("td.cocol-person").text.squish }
    expect(rows.join).not_to include("/ St gewechselt")
    expect(page.text).to include("+ 1 gewechselt")
  end

  it "shows a swap: both start in the other's unit on the same day" do
    other = groups(:unit_b)
    other_person = Fabricate(Group::Unit::Member.name.to_sym, group: other).person
    other_person.update_columns(primary_group_id: other.id, contract_status: "confirmed", status: "confirmed")
    Fabricate(Group::Unit::Member.name.to_sym, group: other).person
      .update_columns(primary_group_id: other.id, contract_status: "confirmed", status: "confirmed")
    mine = unit_person("Sw", contract_status: "confirmed", status: "confirmed")
    # Mine moves to B, the other one to A, both on 01.03.; mine's old role ends later.
    mine.roles.where(group_id: unit_a.id).update_all(start_on: Date.new(2026, 1, 7), end_on: Date.new(2026, 3, 20))
    Fabricate(Group::Unit::Member.name.to_sym, group: other, person: mine, start_on: Date.new(2026, 3, 1))
    mine.update_columns(primary_group_id: other.id)
    other_person.roles.where(group_id: other.id).update_all(start_on: Date.new(2026, 1, 7), end_on: Date.new(2026, 2, 28))
    Fabricate(Group::Unit::Member.name.to_sym, group: unit_a, person: other_person, start_on: Date.new(2026, 3, 1))
    other_person.update_columns(primary_group_id: unit_a.id)
    sign_in(leader)

    get :index, params: {unv: "columns"}

    expect(movement_lines("Unit A", "swapped")).to eq([[:swapped, "01.03.26 ##{mine.id} mit ##{other_person.id} Unit B"]])
    expect(movement_lines("Unit B", "swapped")).to eq([[:swapped, "01.03.26 ##{other_person.id} mit ##{mine.id} Unit A"]])
    # Neither verlassen nor nachgerückt: the size of both units stays.
    %w[Unit\ A Unit\ B].each do |name|
      expect(movement_lines(name, "left").map(&:first)).not_to include(:moved)
      expect(movement_lines(name, "arrived")).to be_empty
      expect(unit_tr(name).at_css(".co-balance-bad")).to be_nil
    end
  end

  it "balances a newcomer who left again: nachgerückt and verlassen" do
    other = groups(:unit_b)
    passing = unit_person("Pa", contract_status: "confirmed", status: "confirmed")
    passing.roles.where(group_id: unit_a.id).update_all(start_on: Date.new(2026, 3, 9), end_on: Date.new(2026, 3, 24))
    Fabricate(Group::Unit::Member.name.to_sym, group: other, person: passing, start_on: Date.new(2026, 3, 25))
    passing.update_columns(primary_group_id: other.id)
    sign_in(leader)

    get :index, params: {unv: "columns"}

    expect(movement_lines("Unit A", "arrived")).to eq([[:arrived, "09.03.26 ##{passing.id}"]])
    expect(movement_lines("Unit A", "left")).to include([:moved, "24.03.26 ##{passing.id} Unit B"])
    # Pa came and left again (+1 −1); Ca and Cb are in Abmeldung (−2).
    sum = balance("Unit A").first
    expect(sum).to match(/\A(\d+) −3 \+1 = (\d+)\z/)
    expect(sum[/= (\d+)/, 1].to_i).to eq(sum.to_i - 2)
    expect(unit_tr("Unit A").at_css(".co-balance-bad")).to be_nil
  end

  it "shows the movements by day in one column in the view Verlauf, the default, the day first" do
    successor = unit_person("Nr", contract_status: "confirmed", status: "confirmed")
    successor.roles.where(group_id: unit_a.id).update_all(start_on: Date.new(2026, 3, 25))
    sign_in(leader)

    # Verlauf is the default view.
    get :index

    headers = page.css("thead th").map { |th| th.text.strip }.join
    expect(headers).to include("Bewegungen")
    expect(headers).not_to include("verlassen")
    first = unit_tr("Unit A").at_css("td.uncol-movements .co-move")
    expect(first.children.first["class"]).to include("co-move-day")
    expect(movement_lines("Unit A", "movements").last).to eq([:arrived, "25.03.26 ##{successor.id}"])
    expect(page.text).to include("nachgerückt", "abgemeldet", "in Abmeldung", "getauscht", "gewechselt")
  end

  # A reduction, a JSF reduction, a deregistered person's Einbehalt and the
  # Einbehalt of one in Abmeldung (Ca).
  def budget_people
    reduced = unit_person("Rd", contract_status: "confirmed", status: "confirmed")
    reduced.update_columns(wsjrdp_total_fee_reduction: 250, wsjrdp_total_fee_reduction_hint: "Nachrücken")
    jsf = unit_person("Js", contract_status: "confirmed", status: "confirmed")
    jsf.update_columns(wsjrdp_total_fee_reduction: 1700, wsjrdp_total_fee_reduction_hint: "JSF")
    gone = unit_person("Go", contract_status: "ended", status: "deregistered")
    gone.update_columns(additional_info: {"deregistration_actual_compensation_cents" => 155_00})
    Person.where(nickname: "Ca").update_all(additional_info: {"deregistration_actual_compensation_cents" => 2550_00})
    # Without it the T&R's compensation would count for Cb.
    Person.where(nickname: "Cb").update_all(additional_info: {"deregistration_actual_compensation_cents" => 0})
  end

  it "shows the people's effect on the budget: Einbehalt, open Einbehalt, fee reductions without JSF" do
    budget_people
    sign_in(leader)

    get :show, params: {id: unit_a.id}

    budget = page.css(".contingent-unit-people tbody tr").to_h do |tr|
      [tr.at_css("td.cocol-person").text[%r{/ (\w+)}, 1], tr.at_css("td.upcol-budget")]
    end
    expect(budget["Rd"].text.squish).to eq("−250,00 €")
    expect(budget["Js"].text.squish).to eq("")
    expect(budget["Go"].text.squish).to eq("+155,00 €")
    expect(budget["Ca"].text.squish).to eq("+2.550,00 €")
    expect(budget["Ca"].at_css("div")["class"]).to include("text-muted")
    expect(budget["Go"].at_css("div")["class"].to_s).not_to include("text-muted")
  end

  it "sums the budget of a unit's people, and below it the sum with the Einbehalt of those in Abmeldung, no sum of all" do
    budget_people
    sign_in(leader)

    get :index, params: {unv: "columns"}

    cell = unit_tr("Unit A").at_css("td.uncol-budget")
    expect(cell.at_css(".co-budget").text.squish).to eq("−95,00 €")
    expect(cell.at_css(".co-budget-pending").text.squish).to eq("+2.455,00 €")
    expect(page.at_css(".exp-footer-row .uncol-budget").text.strip).to eq("")
  end

  it "shows a unit's budget without a second line when nobody is in Abmeldung" do
    Person.where(nickname: %w[Ca Cb]).update_all(status: "confirmed")
    reduced = unit_person("Rd", contract_status: "confirmed", status: "confirmed")
    reduced.update_columns(wsjrdp_extra_total_fee_reduction: 40)
    sign_in(leader)

    get :index, params: {unv: "columns"}

    cell = unit_tr("Unit A").at_css("td.uncol-budget")
    expect(cell.text.squish).to eq("−40,00 €")
    expect(cell.at_css(".co-budget-pending")).to be_nil
  end

  it "leaves a unit's budget empty at 0 €" do
    # Nobody in Abmeldung, whose Einbehalt by the T&R would show below.
    Person.where(nickname: %w[Ca Cb]).update_all(status: "confirmed")
    sign_in(leader)

    get :index, params: {unv: "columns"}

    expect(unit_tr("Unit A").at_css("td.uncol-budget").text.strip).to eq("")
  end

  it "puts the role before a person's id only while the column Rolle is hidden" do
    sign_in(leader)
    ba = Person.find_by(nickname: "Ba")
    prefix = -> { page.css("td.cocol-person .co-person > .text-muted").map(&:text).find { |t| t.end_with?(ba.id.to_s) } }

    get :show, params: {id: unit_a.id}
    expect(prefix.call).to eq(ba.id.to_s)

    get :show, params: {id: unit_a.id, upc: "p,c,s"}
    expect(prefix.call).to match(/\A\S+ #{ba.id}\z/)
  end

  it "shows Haushalt by default, also to whoever remembered a column choice made before it existed" do
    session["wsjrdp_table_state"] = {"contingent/wsjrdp_units#show|up" => {"c" => "p,ca,c,s,cs,js,~r,~ro,~pt"}}
    sign_in(leader)

    get :show, params: {id: unit_a.id}

    expect(page.css(".contingent-unit-people thead th").map { |th| th.text.strip }.join).to include("Haushalt")
  end

  it "shows the unit's people in the column order Rolle, Person, Patrol, Vertrag, Status, in Abmeldung, Haushalt" do
    sign_in(leader)

    get :show, params: {id: unit_a.id}

    headers = page.css(".contingent-unit-people thead th").map { |th| th.text.delete("⇅").strip }.reject(&:empty?)
    expect(headers).to eq(["Rolle", "Person", "Patrol", "Vertrag", "Status", "in Abmeldung", "Haushalt"])
  end

  it "is refused to an eHoC, who may not see the people" do
    ehoc = Fabricate(Group::Root::ExtendedHeadOfContingent.name.to_sym, group: groups(:root)).person
    sign_in(ehoc)

    expect { get :index }.to raise_error(CanCan::AccessDenied)
    expect { get :show, params: {id: unit_a.id} }.to raise_error(CanCan::AccessDenied)
  end
end
