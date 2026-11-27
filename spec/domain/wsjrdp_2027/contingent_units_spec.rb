# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# Unit A holds Ba, Bb and Oa with a contract in force, Ca and Cb in Abmeldung.
describe Wsjrdp2027::ContingentUnits do
  def unit_person(nickname, contract_status:, status:, group: unit_a)
    person = Fabricate(Group::Unit::Member.name.to_sym, group: group).person
    person.update_columns(primary_group_id: group.id, nickname: nickname, contract_status: contract_status,
      status: status)
    person
  end

  before_all(setup_fixtures: true) do
    Person.where(primary_group_id: unit_a.id).update_all(contract_status: "none", status: "registered")
    unit_person("Ba", contract_status: "confirmed", status: "confirmed")
    unit_person("Bb", contract_status: "confirmed", status: "confirmed")
    unit_person("Oa", contract_status: "confirmed", status: "reviewed")
    # In Abmeldung, whatever the contract -- and not in force with it.
    unit_person("Ca", contract_status: "confirmed", status: "deregistration_noted")
    unit_person("Cb", contract_status: "none", status: "deregistration_noted")
  end

  def unit_a = groups(:unit_a)

  def nick(name) = Person.find_by!(nickname: name)

  def unit(group = unit_a) = described_class.new.find(group.id)

  # The movements of a list as [kind, person id, day, group id, partner id].
  def moves(list) = list.map { |m| [m.kind, m.entry.id, m.on, m.group_id, m.partner&.id] }

  def waiting_list
    Fabricate(Group::Unit.name.to_sym, parent: groups(:root), name: "YP Warteliste").tap do |group|
      group.update_columns(is_wsjrdp: false)
    end
  end

  def move(person, from:, to:, last_day:, first_day:, start_on: Date.new(2026, 1, 7))
    person.roles.where(group_id: from.id).update_all(start_on: start_on, end_on: last_day)
    Fabricate(Group::Unit::Member.name.to_sym, group: to, person: person, start_on: first_day)
    person.update_columns(primary_group_id: to.id)
  end

  it "counts a unit's people by contract, and those in Abmeldung as gone already" do
    shown = unit

    aggregate_failures do
      expect([shown.confirmed, shown.open, shown.in_force_total]).to eq([2, 1, 3])
      expect(moves(shown.left_movements).map(&:first)).to eq(%i[cancelling cancelling])
      expect(shown.left_movements.map { |m| m.entry.id }).to match_array([nick("Ca").id, nick("Cb").id])
      expect([shown.left_count, shown.arrived_count, shown.open_cancelling]).to eq([2, 0, 2])
      expect(shown.now_count).to eq(shown.formed_count - 2)
      expect(shown).to be_balanced
      expect(shown.swap_movements).to be_empty
    end
  end

  it "counts the leaving for the unit they were in last, and who came after the unit was formed" do
    list = waiting_list
    cancelling = unit_person("Wa", contract_status: "confirmed", status: "deregistration_noted", group: list)
    Fabricate(Group::Unit::Member.name.to_sym, group: unit_a, person: cancelling,
      start_on: Date.new(2026, 1, 7), end_on: Date.new(2026, 10, 30))
    deregistered = unit_person("De", contract_status: "ended", status: "deregistered")
    deregistered.update_columns(contract_ended_at: Time.zone.local(2026, 4, 16, 12))
    successor = unit_person("Su", contract_status: "confirmed", status: "confirmed")
    # Formed on 07.01.2026 while the unit stores no day.
    successor.roles.where(group_id: unit_a.id).update_all(start_on: Date.new(2026, 3, 1))

    shown = unit

    aggregate_failures do
      expect(moves(shown.left_movements)).to include([:cancelling, cancelling.id, Date.new(2026, 10, 30), nil, nil],
        [:deregistered, deregistered.id, Date.new(2026, 4, 16), nil, nil])
      expect(moves(shown.arrival_movements).map { |m| m.first(3) }).to eq([[:arrived, successor.id, Date.new(2026, 3, 1)]])
      expect([shown.left_count, shown.arrived_count, shown.open_cancelling]).to eq([4, 1, 3])
      expect(shown.now_count).to eq(shown.formed_count - 3)
      expect(shown.former?(Struct.new(:id).new(cancelling.id))).to be(true)
      expect(shown.people_rows.map(&:id)).to include(cancelling.id)
    end
  end

  it "counts who came after the unit was formed as nachgerückt, with where from" do
    list = waiting_list
    successor = unit_person("Nr", contract_status: "confirmed", status: "confirmed")
    successor.roles.where(group_id: unit_a.id).update_all(start_on: Date.new(2026, 3, 25))
    Fabricate(Group::Unit::Member.name.to_sym, group: list, person: successor,
      start_on: Date.new(2025, 12, 7), end_on: Date.new(2026, 3, 8))
    # On a waiting list only after joining the unit: no successor.
    later = unit_person("La", contract_status: "confirmed", status: "confirmed")
    later.roles.where(group_id: unit_a.id).update_all(start_on: Date.new(2026, 1, 7))
    Fabricate(Group::Unit::Member.name.to_sym, group: list, person: later,
      start_on: Date.new(2026, 2, 1), end_on: Date.new(2026, 2, 2))

    shown = unit

    expect(moves(shown.arrival_movements)).to eq([[:arrived, successor.id, Date.new(2026, 3, 25), list.id, nil]])
    expect(shown.joined[successor.id]).to eq(Date.new(2026, 3, 25))
  end

  it "counts nobody as nachgerückt who joined on the day the unit was formed or before" do
    unit_a.update!(unit_formed_date: "01.02.2026")
    on_the_day = unit_person("Od", contract_status: "confirmed", status: "confirmed")
    on_the_day.roles.where(group_id: unit_a.id).update_all(start_on: Date.new(2026, 2, 1))
    after = unit_person("Af", contract_status: "confirmed", status: "confirmed")
    after.roles.where(group_id: unit_a.id).update_all(start_on: Date.new(2026, 2, 2))

    expect(unit.arrival_movements.map { |m| m.entry.id }).to eq([after.id])
  end

  it "counts who left the unit without deregistering as gewechselt, and as nachgerückt where they went" do
    other = groups(:unit_b)
    moved = unit_person("Mv", contract_status: "confirmed", status: "confirmed")
    move(moved, from: unit_a, to: other, last_day: Date.new(2026, 3, 1), first_day: Date.new(2026, 3, 2))
    # Still in the unit with another role: not gewechselt.
    stays = unit_person("St", contract_status: "confirmed", status: "confirmed")
    stays.roles.where(group_id: unit_a.id).update_all(end_on: Date.new(2026, 3, 1))
    Fabricate(Group::Unit::Leader.name.to_sym, group: unit_a, person: stays, start_on: Date.new(2026, 3, 2))

    units = described_class.new
    shown = units.find(unit_a.id)

    aggregate_failures do
      expect(moves(shown.left_movements)).to include([:moved, moved.id, Date.new(2026, 3, 1), other.id, nil])
      expect(shown.left_movements.map { |m| m.entry.id }).not_to include(stays.id)
      expect(moves(units.find(other.id).arrival_movements)).to include([:arrived, moved.id, Date.new(2026, 3, 2),
        unit_a.id, nil])
      row = shown.people_rows.find { |e| e.id == moved.id }
      expect(row.presence).to eq("moved")
      expect(shown.gone?(row)).to be(true)
    end
  end

  it "shows a swap in both units, counted in neither" do
    other = groups(:unit_b)
    partner = unit_person("Pt", contract_status: "confirmed", status: "confirmed", group: other)
    unit_person("Ot", contract_status: "confirmed", status: "confirmed", group: other)
    mine = unit_person("Sw", contract_status: "confirmed", status: "confirmed")
    # Both start in the other's unit on 01.03.; mine's old role ends later.
    move(mine, from: unit_a, to: other, last_day: Date.new(2026, 3, 20), first_day: Date.new(2026, 3, 1))
    move(partner, from: other, to: unit_a, last_day: Date.new(2026, 2, 28), first_day: Date.new(2026, 3, 1))

    units = described_class.new

    aggregate_failures do
      expect(moves(units.find(unit_a.id).swap_movements)).to eq([[:swapped, mine.id, Date.new(2026, 3, 1), other.id,
        partner.id]])
      expect(moves(units.find(other.id).swap_movements)).to eq([[:swapped, partner.id, Date.new(2026, 3, 1),
        unit_a.id, mine.id]])
      [unit_a, other].each do |group|
        shown = units.find(group.id)
        expect(shown.left_movements.map(&:kind)).not_to include(:moved)
        expect(shown.arrival_movements).to be_empty
        expect(shown).to be_balanced
      end
    end
  end

  it "balances a newcomer who left again: nachgerückt and verlassen" do
    passing = unit_person("Pa", contract_status: "confirmed", status: "confirmed")
    move(passing, from: unit_a, to: groups(:unit_b), start_on: Date.new(2026, 3, 9), last_day: Date.new(2026, 3, 24),
      first_day: Date.new(2026, 3, 25))

    shown = unit

    aggregate_failures do
      expect(moves(shown.arrival_movements).map { |m| m.first(3) }).to eq([[:arrived, passing.id, Date.new(2026, 3, 9)]])
      expect(moves(shown.left_movements)).to include([:moved, passing.id, Date.new(2026, 3, 24), groups(:unit_b).id, nil])
      expect([shown.left_count, shown.arrived_count]).to eq([3, 1])
      expect(shown).to be_balanced
      expect(shown.movements_by_day.last.entry.id).to eq(passing.id)
    end
  end

  it "counts the people in force without a patrol, red where nobody has one" do
    Person.where(nickname: "Ba").update_all(patrol: "A")
    unit_person("P3", contract_status: "confirmed", status: "confirmed", group: groups(:unit_b))

    units = described_class.new
    shown = units.find(unit_a.id)

    aggregate_failures do
      # Who is in Abmeldung does not count, though without a patrol.
      expect(shown.without_patrol).to eq(2)
      expect(shown).to be_patrols_incomplete
      expect(shown).not_to be_patrols_unset
      expect(units.find(groups(:unit_b).id)).to be_patrols_unset
    end
  end

  # A reduction, a JSF reduction, a deregistered person's Einbehalt and the
  # Einbehalt of one in Abmeldung (Ca).
  it "sums the people's effect on the budget: Einbehalt, open Einbehalt, fee reductions without JSF" do
    unit_person("Rd", contract_status: "confirmed", status: "confirmed")
      .update_columns(wsjrdp_total_fee_reduction: 250, wsjrdp_total_fee_reduction_hint: "Nachrücken")
    unit_person("Js", contract_status: "confirmed", status: "confirmed")
      .update_columns(wsjrdp_total_fee_reduction: 1700, wsjrdp_total_fee_reduction_hint: "JSF")
    gone = unit_person("Go", contract_status: "ended", status: "deregistered")
    WsjrdpDeregistration.create!(person_id: gone.id, number: 1, actual_compensation: 155)
    WsjrdpDeregistration.create!(person_id: nick("Ca").id, number: 1, actual_compensation: 2550)
    # Without it the T&R's compensation would count for Cb.
    WsjrdpDeregistration.create!(person_id: nick("Cb").id, number: 1, actual_compensation: 0)

    shown = unit
    parts = shown.all_entries.to_h { |e| [e.id, described_class.budget_parts(e, Person.find(e.id))] }

    aggregate_failures do
      expect(parts.fetch(nick("Rd").id)).to include(counted: -25_000)
      expect(parts.fetch(nick("Js").id)).to include(counted: 0, reduction: 0)
      expect(parts.fetch(gone.id)).to include(counted: 15_500)
      expect(parts.fetch(nick("Ca").id)).to include(counted: 0, pending: 255_000)
      expect([shown.budget_cents, shown.budget_pending_cents]).to eq([-9_500, 255_000])
    end
  end

  it "puts a unit's people in Abmeldung first, then without a contract in force, then not confirmed, " \
     "the deregistered last, leaders first within" do
    leader = Fabricate(Group::Unit::Leader.name.to_sym, group: unit_a).person
    leader.update_columns(primary_group_id: unit_a.id, nickname: "Zz", contract_status: "confirmed",
      status: "confirmed")
    unit_person("De", contract_status: "ended", status: "deregistered")
    shown = unit

    order = shown.all_entries.sort_by { |e| described_class.people_natural_key(e, moved: shown.moved?(e)) }
      .map { |e| Person.find(e.id).nickname }

    expect(order.first(2)).to match_array(%w[Ca Cb])
    expect(order.last).to eq("De")
    expect(order.index("Zz")).to be < order.index("Ba")
    expect(order.index("Oa")).to be < order.index("Ba")
  end
end
