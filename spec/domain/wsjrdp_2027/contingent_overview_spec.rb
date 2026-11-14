# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

require "spec_helper"

# The figures of Kontingent > Übersicht: the state of a person by contract and
# status, and where they are counted (WSJRDP groups, waiting lists, all).
describe Wsjrdp2027::ContingentOverview do
  subject(:overview) { described_class.new }

  describe ".state" do
    {
      %w[confirmed confirmed] => "full",
      %w[upload confirmed] => "docs",
      %w[printed confirmed] => "docs",
      %w[deregistration_noted confirmed] => "cancel",
      %w[deregistration_noted none] => "cancel",
      %w[deregistration_noted ended] => "cancel",
      %w[upload replacement_pending] => "pending",
      %w[registered none] => "open",
      %w[in_review none] => "review",
      %w[reviewed none] => "review",
      %w[deregistered ended] => "ended",
      %w[deregistered none] => "dereg",
      %w[confirmed none] => "inconsistent",
      %w[reviewed ended] => "ended",
      %w[confirmed ended] => "ended",
      %w[deregistered confirmed] => "inconsistent"
    }.each do |(status, contract), state|
      it "puts status #{status} with contract #{contract} into #{state}" do
        expect(described_class.state(status, contract)).to eq(state)
      end
    end

    it "says why status and contract contradict each other" do
      expect(described_class.inconsistency("confirmed", "none")).to eq("Status bestätigt, Vertrag: Kein Vertrag")
      expect(described_class.inconsistency("reviewed", "ended")).to be_nil
      expect(described_class.inconsistency("deregistered", "confirmed")).to eq("Abgemeldet, Vertrag in Kraft")
      expect(described_class.inconsistency("confirmed", "confirmed")).to be_nil
    end
  end

  describe "patrols" do
    let(:schema) { Wsjrdp2027::ContingentPeopleFilterSchema }
    let(:unit) { groups(:unit_a) }
    let(:in_patrol) { people(:yp_a_1) }
    let(:without) { people(:yp_a_2) }

    before do
      unit.update_columns(is_wsjrdp: true)
      in_patrol.update_columns(patrol: "B")
      without.update_columns(patrol: nil)
    end

    def ids(*values) = schema.apply([[["patrol", "in", *values]]], overview.entries).map(&:id)

    it "keys a patrol by its unit, marks the ULs and YPs of a unit without one" do
      expect(described_class.patrol_value(7, true, "YP", "C")).to eq("7-C")
      expect(described_class.patrol_value(7, true, "UL", "")).to eq("none")
      expect(described_class.patrol_value(7, true, "CMT", nil)).to be_nil
      expect(described_class.patrol_value(7, false, "YP", "C")).to be_nil
    end

    it "filters by one patrol, several, or none" do
      expect(ids("#{unit.id}-B")).to eq([in_patrol.id])
      expect(ids("#{unit.id}-A", "#{unit.id}-B")).to eq([in_patrol.id])
      expect(ids("none")).to include(without.id)
      expect(ids("none")).not_to include(in_patrol.id)
    end

    it "offers no patrol and every patrol of every WSJRDP unit" do
      pairs = schema::PATROL_OPTIONS.pairs.to_h
      expect(pairs["none"]).to eq("keine Patrol")
      expect(pairs["#{unit.id}-D"]).to eq("Unit A · Patrol D")
    end
  end

  describe "counting" do
    let(:waitlist) { groups(:empty_unit) }
    let(:in_force) { people(:yp_a_1) }
    let(:cancelled_on_waitlist) { people(:yp_a_2) }
    let(:waiting) { people(:ul_b_1) }

    before do
      waitlist.update_columns(name: "YP Warteliste", is_wsjrdp: false)
      in_force.update_columns(status: "confirmed", contract_status: "confirmed")
      cancelled_on_waitlist.update_columns(status: "deregistration_noted", contract_status: "confirmed",
        primary_group_id: waitlist.id)
      waiting.update_columns(status: "reviewed", contract_status: "none", primary_group_id: waitlist.id)
    end

    def ids(tree) = schema.apply(tree, overview.entries).map(&:id)

    def column(*keys) = [[["contract_column", "in", *keys]]]

    let(:schema) { Wsjrdp2027::ContingentPeopleFilterSchema }

    it "puts contracts in force in WSJRDP groups only into a column, cancellations everywhere" do
      expect(ids(column("full"))).to include(in_force.id)
      expect(ids(column("cancel"))).to include(cancelled_on_waitlist.id)
      expect(ids(column("none"))).not_to include(waiting.id)
      expect(overview.entries.find { |e| e.id == waiting.id }.contract_column).to be_nil
      expect(overview.entries.find { |e| e.id == waiting.id }.group_kind).to eq("waitlist")
    end

    it "finds the matrix column of a state, in WSJRDP groups or everywhere" do
      expect(described_class.contract_column("docs", true)).to eq("docs")
      expect(described_class.contract_column("review", true)).to eq("none")
      expect(described_class.contract_column("review", false)).to be_nil
      expect(described_class.contract_column("ended", false)).to eq("ended")
      expect(described_class.contract_column("dereg", true)).to be_nil
      expect(schema::CONTRACT_COLUMNS).to eq("full" => "bestätigt", "docs" => "offen",
        "cancel" => "in Abmeldung", "none" => "ohne Vertrag", "ended" => "abgemeldet")
    end

    it "lists by default the matrix columns offen, in Abmeldung and ohne Vertrag of all rows" do
      rows = overview.matrix_rows
      shown = rows.select { |row| row[:total] || row[:warning] }
      expect(ids(schema::DEFAULT).size).to eq(shown.sum { |row| row[:counts].values_at("docs", "cancel", "none").sum })
      expect(ids(schema::DEFAULT)).to include(cancelled_on_waitlist.id)
      expect(ids(schema::DEFAULT)).not_to include(in_force.id, waiting.id)
    end

    it "filters by the registration status and the contract as stored" do
      tree = [[["status", "in", "confirmed"]], [["contract_status", "in", "confirmed"]]]
      expect(ids(tree)).to include(in_force.id)
      expect(ids(tree)).not_to include(cancelled_on_waitlist.id, waiting.id)
    end

    it "shows the matrix rows in order, the combined ones adding up rows above" do
      rows = overview.matrix_rows.index_by { |row| row[:label] }
      sum = ->(*labels) { labels.sum { |label| rows.fetch(label)[:sum] } }

      expect(rows.keys.first(8)).to eq(["CMT", "BMT", "IST", "IST inkl. BMT", "CMT + IST inkl. BMT", "UL", "YP", "UL + YP"])
      combined = rows.values.select { |row| row[:combined] }
      expect(combined.pluck(:label))
        .to eq(["IST inkl. BMT", "CMT + IST inkl. BMT", "UL + YP", "Alle ohne JPT", "Alle im Kontingent"])
      expect(rows.keys.last(3)).to eq(["Alle ohne JPT", "JPT", "Alle im Kontingent"])
      expect(rows["Alle im Kontingent"][:total]).to be(true)
      expect(rows["Alle ohne JPT"][:combined]).not_to include("JPT")
      expect(rows["Alle im Kontingent"][:combined]).to include("JPT")
      combined.each do |row|
        expect(row[:sum]).to eq(sum.call(*row[:combined])), row[:label]
        described_class::MATRIX_COLUMNS.each_key do |key|
          expect(row[:counts][key]).to eq(row[:combined].sum { |label| rows.fetch(label)[:counts][key] }), "#{row[:label]} / #{key}"
        end
      end
    end

    it "draws a line per combined row, stopping at what counts and passing what does not" do
      rows = overview.matrix_rows
      labels = rows.pluck(:label)
      line = overview.matrix_lines(rows).find { |l| l[:label] == "CMT + IST inkl. BMT" }
      marks = labels.zip(line[:marks]).to_h

      expect(marks["CMT"]).to eq(segment: "top", stop: "in")
      expect(marks["IST"]).to eq(segment: "mid", stop: "in")
      expect(marks["IST inkl. BMT"]).to eq(segment: "mid", stop: "out")
      expect(marks["CMT + IST inkl. BMT"]).to eq(segment: "bot", stop: "result")
      expect(marks["UL"]).to be_nil
      lines = overview.matrix_lines(rows)
      expect(lines.pluck(:label)).to eq(rows.select { |r| r[:combined] }.pluck(:label))
      # Lines that share no row share a lane: "UL + YP" sits in the lane of
      # "IST inkl. BMT"; overlapping lines never share one.
      lane = lines.to_h { |l| [l[:label], l[:lane]] }
      expect(lane["UL + YP"]).to eq(lane["IST inkl. BMT"])
      lines.group_by { |l| l[:lane] }.each_value do |shared|
        shared.combination(2).each do |a, b|
          expect(a[:marks].zip(b[:marks]).none? { |x, y| x && y }).to be(true), "#{a[:label]} / #{b[:label]}"
        end
      end
    end

    it "groups the matrix columns by the contract, each column under one heading" do
      groups = described_class::MATRIX_GROUPS
      states = ->(label) { groups.to_h.fetch(label).flat_map { |key| described_class::MATRIX_COLUMNS[key][:states] } }

      expect(groups.flat_map(&:last)).to eq(described_class::MATRIX_COLUMNS.keys)
      # In force: the states whose contract_status is confirmed; without: the
      # others still on the way. In Abmeldung stands apart, whatever the contract.
      expect(states.call("Vertrag in Kraft")).to eq(%w[full docs full docs])
      expect(states.call("ohne")).to eq(%w[pending open review])
      expect(groups).to include([nil, %w[cancel]])
    end

    it "sums a row without the cancellations, and counts those in all groups" do
      rows = overview.matrix_rows.index_by { |row| row[:label] }
      yp = rows.fetch("YP")

      expect(yp[:sum]).to eq(yp[:counts].values_at("full", "docs", "none").sum)
      expect(yp[:counts]["inforce"]).to eq(yp[:counts].values_at("full", "docs").sum)
      expect(yp[:counts]["cancel"]).to be >= 1 # on the waiting list, outside the WSJRDP groups
    end

    it "counts every matrix cell like the tree its link filters by" do
      in_force.update_columns(wsj_role: "JPT")

      overview.matrix_rows.each do |row|
        described_class::MATRIX_COLUMNS.each do |key, column|
          tree = schema.cell_tree(key, **row.slice(:wsj, :wsj_not, :roles, :roles_not))
          expect(schema.apply(tree, overview.entries).size).to eq(row[:counts][key]), "#{row[:label]} / #{key}"
        end
        sum_keys = described_class::MATRIX_COLUMNS.select { |_, column| column[:in_sum] }.keys
        tree = schema.cell_tree(sum_keys, **row.slice(:wsj, :wsj_not, :roles, :roles_not))
        expect(schema.apply(tree, overview.entries).size).to eq(row[:sum]), "#{row[:label]} / sum"
      end
    end

    it "counts the matrix in WSJRDP groups, the sum without the combined rows" do
      totals = overview.matrix_totals
      yp = overview.matrix_rows.find { |row| row[:label] == "YP" }

      expect(yp[:counts]["full"]).to be >= 1
      expect(totals[:sum]).to eq(overview.matrix_rows.reject { |row| row[:combined] }.sum { |row| row[:sum] })
    end

    it "compares with the jamboree by jamboree role and contract, without JPT" do
      in_force.update_columns(wsj_role: "YP")
      jpt = people(:ul_a_1)
      jpt.update_columns(wsj_role: "JPT", status: "confirmed", contract_status: "confirmed")
      ended = people(:ul_a_2)
      ended.update_columns(wsj_role: "UL", status: "deregistered", contract_status: "ended",
        primary_group_id: waitlist.id)
      cancelled_on_waitlist.update_columns(wsj_role: "YP")
      rows = overview.jamboree_rows
      ul_yp = rows["UL + YP"][:entries].transform_values { |list| list.map(&:id) }

      expect(rows.keys).to eq(["CMT", "IST", "UL + YP"])
      expect(ul_yp["inforce"]).to include(in_force.id)
      expect(ul_yp.values.flatten).not_to include(jpt.id)
      expect(ul_yp["cancel"]).to include(cancelled_on_waitlist.id)
      expect(ul_yp["ended"]).to include(ended.id)
      expect(ul_yp["none"].to_a).not_to include(waiting.id)
      counts = rows["UL + YP"][:counts]
      expect(rows["UL + YP"][:sum]).to eq(counts["inforce"] + counts["cancel"] + counts["none"])
    end

    it "counts a tile and its matrix row alike, even for a role the contingent and jamboree differ in" do
      people(:cmt_member1).update_columns(wsj_role: "EXT", status: "confirmed", contract_status: "confirmed")
      people(:cmt_member2).update_columns(wsj_role: "CMT", status: "upload", contract_status: "confirmed")
      rows = overview.matrix_rows
      marks = overview.matrix_tile_marks(rows)

      expect(marks.values).to match_array(described_class::PEOPLE_TILES.keys)
      marks.each do |label, tile|
        row = rows.find { |r| r[:label] == label }
        spec = described_class::PEOPLE_TILES.fetch(tile)
        expect(row[:counts]["inforce"]).to eq(overview.tile_in_force(*spec[:jamboree])), tile
      end
    end

    it "puts whoever no row takes into a warning row that no Alle counts" do
      people(:yp_a_1).update_columns(wsj_role: "XYZ", status: "confirmed", contract_status: "confirmed")
      rows = overview.matrix_rows.index_by { |row| row[:label] }

      other = rows.fetch("andere J-Rolle")
      expect(other[:warning]).to be(true)
      expect(other[:counts]["full"]).to be >= 1
      expect(rows["Alle im Kontingent"][:combined]).not_to include("andere J-Rolle")
      tree = schema.cell_tree("full", **other.slice(:wsj, :wsj_not, :roles, :roles_not))
      expect(schema.apply(tree, overview.entries).map(&:id)).to include(people(:yp_a_1).id)
    end

    it "counts the units with people and their patrols" do
      unit = groups(:unit_a)
      people(:yp_a_1).update_columns(primary_group_id: unit.id, patrol: "A")
      people(:ul_a_1).update_columns(primary_group_id: unit.id, patrol: "B", status: "registered",
        contract_status: "none")

      figures = overview.unit_figures

      expect(figures[:units][:total]).to be >= 1
      expect(figures[:patrols][:total]).to be >= 2
    end

    it "counts the units not or only partly divided into patrols" do
      unit = groups(:unit_a)
      Person.where(primary_group_id: unit.id).update_all(patrol: nil, status: "confirmed")
      before = overview.unit_figures[:units]
      divided = people(:yp_a_1)
      divided.update_columns(primary_group_id: unit.id, patrol: "A", status: "confirmed")
      people(:ul_a_1).update_columns(primary_group_id: unit.id, patrol: nil, status: "confirmed")
      people(:ul_a_2).update_columns(primary_group_id: unit.id, status: "deregistration_noted", patrol: "B")

      figures = described_class.new.unit_figures

      expect(figures[:units][:partly]).to eq(before[:partly] + 1)
      expect(figures[:units][:undivided]).to eq(before[:undivided] - 1)
    end

    it "lists a jamboree role that is not the contingent role's as a difference" do
      in_force.update_columns(wsj_role: "JPT")

      expect(overview.role_differences.keys).to include("YP→JPT")
      expect(schema.apply([[["role_diff", "in", "yes"]]], overview.entries).map(&:id)).to include(in_force.id)
    end
  end
end
