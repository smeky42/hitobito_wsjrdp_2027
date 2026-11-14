# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # The figures of the contingent overview (Contingent::WsjrdpContingentController):
  # every person with a primary group, put into one state by the contract
  # (contract_status, the main factor) and the registration status, and
  # counted for the jamboree tiles, the matrix and the list.
  #
  # The people are loaded with a handful of columns and no associations, so
  # all of them -- units included -- take a few dozen milliseconds. Only the
  # page of the list that is shown loads its people in full
  # (WsjrdpContingentHelper#contingent_page_people).
  #
  # Where a person is counted:
  # - WSJRDP groups (groups.is_wsjrdp): the contingent proper. The waiting
  #   lists, T1 and the groups of external staff are not WSJRDP groups.
  # - waiting lists: the groups that are not WSJRDP groups and are named
  #   "…Warteliste" (UL, YP, IST, CMT; Group.waiting_list_name?).
  # - all groups: deregistrations being noted ("in Abmeldung": status
  #   deregistration_noted, whatever the contract), deregistrations and
  #   contradictions -- a deregistration moves a person onto a waiting list.
  class ContingentOverview
    COLUMNS = %w[id primary_group_id first_name last_name nickname status contract_status contract_confirmed_at
      contract_ended_at payment_role wsj_role additional_info patrol].freeze

    # The states, most urgent first -- the order of the list. A person is in
    # exactly one.
    STATES = {
      "inconsistent" => "Widersprüchlich",
      "cancel" => "In Abmeldung",
      "review" => "Zu prüfen",
      "pending" => "Neuer Vertrag ausstehend",
      "docs" => "Vertrag in Kraft, Unterlagen offen",
      "open" => "Ohne Vertrag, in Anmeldung",
      "full" => "Vertrag in Kraft",
      "ended" => "Abgemeldet, Vertrag beendet",
      "dereg" => "Abgemeldet vor Vertrag"
    }.freeze

    # What needs doing ("Handlungsbedarf"): the Schnellauswahl's buttons, one
    # per state that needs something done; every other state needs nothing
    # ("none").
    NEEDS = {
      "inconsistent" => "Widersprüchlich",
      "review" => "Zu prüfen",
      "pending" => "Neuer Vertrag",
      "docs" => "Unterlagen offen",
      "cancel" => "in Abmeldung"
    }.freeze

    # The columns of the matrix: label (header: its lines, when it has two;
    # narrow: what a very narrow table shows instead),
    # states, and whether a column counts in all groups (in WSJRDP groups
    # otherwise) and adds to the row's sum; a subtotal column names the
    # columns it adds up. In Abmeldung (deregistration noted, with a
    # contract or without) counts in all groups -- a person in the middle of
    # deregistering may already sit on a waiting list -- and not in the sum. A cell links its people through
    # ContingentPeopleFilterSchema.cell_tree, by the column a person falls into
    # (Entry#contract_column; filter_label: its name there, the label otherwise).
    MATRIX_COLUMNS = {
      "full" => {label: "bestätigt", states: %w[full], everywhere: false, in_sum: true},
      "docs" => {label: "offen", states: %w[docs], everywhere: false, in_sum: true},
      # bestätigt + offen, already counted in the row's sum through those two.
      "inforce" => {label: "Summe", states: %w[full docs], everywhere: false, in_sum: false, subtotal: %w[full docs]},
      "cancel" => {label: "in Abmeldung", header: %w[in Abmeldung], narrow: "in Abm.", states: %w[cancel],
                   everywhere: true, in_sum: false},
      "none" => {label: "Vertrag", filter_label: "ohne Vertrag", states: %w[pending open review], everywhere: false, in_sum: true},
      # Deregistered with a contract that has ended -- they were in once. In
      # all groups (a deregistration moves a person onto a waiting list), not
      # in any sum.
      "ended" => {label: "abgemeldet", short: "abge\u00ADmeldet", states: %w[ended], everywhere: true, in_sum: false,
                  title: "abgemeldet, Vertrag beendet – waren einmal dabei; in allen Gruppen, in keiner Summe"}
    }.freeze
    # The headings over the columns, by the contract: in force (contract_status
    # confirmed) or not; in Abmeldung and abgemeldet stand apart, whatever the
    # contract. A heading over one column only is the first line of that
    # column's own heading ("ohne" / "Vertrag"), the row above stays empty;
    # nil: no heading. Pairs, in the order of the columns.
    MATRIX_GROUPS = [
      ["Vertrag in Kraft", %w[full docs inforce]],
      [nil, %w[cancel]],
      ["ohne", %w[none]],
      [nil, %w[ended]]
    ].freeze

    # The comparison with the jamboree registration: the people who go to the
    # jamboree through the contingent, by their jamboree role (JPT and EXT do
    # not), and how far their contract is. In force and none yet count in
    # WSJRDP groups; being cancelled and ended count in all groups -- a
    # deregistration moves a person onto a waiting list.
    JAMBOREE_ROWS = {"CMT" => %w[CMT], "IST" => %w[IST], "UL + YP" => %w[UL YP]}.freeze
    JAMBOREE_COLUMNS = {
      "inforce" => "Vertrag in Kraft",
      "cancel" => "in Abmeldung",
      "none" => "noch kein Vertrag",
      "ended" => "abgemeldet, Vertrag beendet"
    }.freeze
    # The columns the total of a row adds up: the people still on their way.
    JAMBOREE_TOTAL_COLUMNS = %w[inforce cancel none].freeze

    # One person as the overview sees them -- a row of the people list, too.
    Entry = Struct.new(:id, :name, :status, :contract_status, :contract_confirmed_at, :contract_ended_at, :state,
      :reason, :wsjrdp, :waitlist, :wsjrdp_role, :wsj_role, :role_difference, :group_name, :patrol, :contract_column,
      keyword_init: true) do
      # The NEEDS key of the state, "none" when nothing needs doing.
      def need = NEEDS.key?(state) ? state : "none"

      # "wsjrdp", "waitlist" or "other" (ContingentPeopleFilterSchema::GROUP_KINDS).
      def group_kind
        return "wsjrdp" if wsjrdp

        waitlist ? "waitlist" : "other"
      end
    end

    def self.state(status, contract_status)
      # In Abmeldung: the deregistration is noted, whatever the contract.
      return "cancel" if status == "deregistration_noted"
      # An ended contract means deregistered, whatever the status still says.
      return "ended" if contract_status == "ended"
      return "inconsistent" if inconsistency(status, contract_status)

      case contract_status
      when "confirmed" then (status == "confirmed") ? "full" : "docs"
      when "replacement_pending" then "pending"
      else
        if status == "deregistered" then "dereg"
        elsif %w[in_review reviewed].include?(status) then "review"
        else
          "open"
        end
      end
    end

    # Why status and contract contradict each other, nil when they do not. An
    # ended contract contradicts no status: it means deregistered, even where
    # the status was not moved on.
    def self.inconsistency(status, contract_status)
      contract = Settings.contract_status[contract_status] || contract_status
      if status == "confirmed" && !%w[confirmed ended].include?(contract_status)
        "Status bestätigt, Vertrag: #{contract}"
      elsif status == "deregistered" && contract_status == "confirmed"
        "Abgemeldet, Vertrag in Kraft"
      end
    end

    # The patrol of a person, as the list filters it (ContingentPeopleFilterSchema
    # "patrol"): "<unit id>-<letter>" (people.patrol, set on a unit's Patrols
    # tab), "none" for an UL or YP of a unit without one, nil for everybody
    # else -- a patrol only means something in a WSJRDP unit.
    PATROL_ROLES = %w[UL YP].freeze

    def self.patrol_value(group_id, unit, role, patrol)
      return nil unless unit && PATROL_ROLES.include?(role)

      patrol.present? ? "#{group_id}-#{patrol}" : "none"
    end

    # The matrix column a person falls into -- one of MATRIX_COLUMNS without
    # the subtotals --, nil for a state no column counts (or counts in WSJRDP
    # groups only, outside them).
    def self.contract_column(state, wsjrdp)
      MATRIX_COLUMNS.find { |_, c| !c[:subtotal] && c[:states].include?(state) && (c[:everywhere] || wsjrdp) }&.first
    end

    def entries
      @entries ||= begin
        groups = ::Group.unscoped.pluck(:id, :is_wsjrdp, :name, :type)
          .to_h { |id, wsjrdp, name, type| [id, [wsjrdp, name, wsjrdp && type == "Group::Unit"]] }
        ::Person.select(COLUMNS).where.not(primary_group_id: nil).map do |person|
          wsjrdp, group_name, unit = groups.fetch(person.primary_group_id, [false, nil, false])
          state = self.class.state(person.status, person.contract_status)
          Entry.new(
            id: person.id, name: person.short_full_name_with_nickname,
            status: person.status, contract_status: person.contract_status,
            contract_confirmed_at: person.contract_confirmed_at, contract_ended_at: person.contract_ended_at,
            state: state,
            reason: (state == "inconsistent") ? self.class.inconsistency(person.status, person.contract_status) : STATES[state],
            wsjrdp: wsjrdp, waitlist: !wsjrdp && ::Group.waiting_list_name?(group_name),
            wsjrdp_role: person.wsjrdp_role, wsj_role: person.effective_wsj_role,
            role_difference: person.role_difference, group_name: group_name,
            patrol: self.class.patrol_value(person.primary_group_id, unit, person.wsjrdp_role, person.patrol),
            contract_column: self.class.contract_column(state, wsjrdp)
          )
        end
      end
    end

    # The rows of the matrix (WSJRDP groups), by the jamboree role (wsj_role)
    # -- so a tile above and its row count the same people. BMT (contingent
    # role, IST on the jamboree) is a row of its own, IST the other IST. A
    # combined row takes rows above together (`combined:` names them) -- for
    # reading only, "Alle im Kontingent" does not count it. A row narrows by
    # jamboree roles (wsj / wsj_not) and contingent roles (roles / roles_not).
    MATRIX_ROWS = [
      {label: "CMT", wsj: %w[CMT]},
      {label: "BMT", wsj: %w[IST], roles: %w[BMT]},
      {label: "IST", wsj: %w[IST], roles_not: %w[BMT]},
      {label: "IST inkl. BMT", wsj: %w[IST], combined: %w[BMT IST]},
      {label: "CMT + IST inkl. BMT", wsj: %w[CMT IST], combined: %w[CMT BMT IST]},
      {label: "UL", wsj: %w[UL]},
      {label: "YP", wsj: %w[YP]},
      {label: "UL + YP", wsj: %w[UL YP], combined: %w[UL YP]}
    ].freeze
    # Shown only while someone counts in it.
    EXT_ROW = {label: "EXT", wsj: %w[EXT]}.freeze
    # Between "Alle ohne JPT" and "Alle im Kontingent".
    JPT_ROW = {label: "JPT", wsj: %w[JPT]}.freeze
    # Whoever no row takes (a jamboree role none of them knows): shown only
    # while someone counts in it, with a warning, and in no "Alle".
    OTHER_ROW = {label: "andere J-Rolle", warning: true,
                 wsj_not: (MATRIX_ROWS + [EXT_ROW, JPT_ROW]).flat_map { |row| row[:wsj] }.uniq}.freeze

    # The matrix: MATRIX_ROWS, EXT and the others where someone counts, then
    # "Alle ohne JPT", JPT and "Alle im Kontingent"; each row with
    # {counts: {column => n}, sum:}, the sum adding the columns MATRIX_COLUMNS
    # marks `in_sum`.
    def matrix_rows
      relevant = matrix_entries
      count = ->(row) { row.merge(matrix_counts(matrix_row_entries(row, relevant))) }
      someone = ->(row) { row[:counts].values.any?(&:positive?) }
      rows = MATRIX_ROWS.map(&count)
      rows += [EXT_ROW, OTHER_ROW].map(&count).select(&someone)
      parts = rows.reject { |row| row[:combined] || row[:warning] }
      jpt = count.call(JPT_ROW)
      rows << count.call({label: "Alle ohne JPT", wsj: parts.flat_map { |row| row[:wsj] }.uniq,
                          combined: parts.pluck(:label)})
      rows << jpt
      rows << count.call({label: "Alle im Kontingent", wsj: (parts + [jpt]).flat_map { |row| row[:wsj] }.uniq,
                          combined: (parts + [jpt]).pluck(:label), total: true})
    end

    # The people of one matrix row: the jamboree roles it takes (wsj) or
    # leaves out (wsj_not), narrowed by contingent roles (roles / roles_not).
    def matrix_row_entries(row, relevant = matrix_entries)
      relevant.select do |e|
        (row[:wsj].nil? || row[:wsj].include?(e.wsj_role)) && (row[:wsj_not].nil? || !row[:wsj_not].include?(e.wsj_role)) &&
          (row[:roles].nil? || row[:roles].include?(e.wsjrdp_role)) &&
          (row[:roles_not].nil? || !row[:roles_not].include?(e.wsjrdp_role))
      end
    end

    def matrix_totals = matrix_counts(matrix_entries)

    # The lines in the right margin of the matrix, one per combined row: from
    # the first row it takes together down to the row itself. Per row a mark,
    # nil outside the line: {segment: "top"/"mid"/"bot", stop: "in" (counts),
    # "out" (passed, does not count) or "result" (the combined row)}. Lines
    # that share no row share a lane (`lane:`), so the margin stays narrow.
    # [{label:, lane:, marks: [...]}]
    def matrix_lines(rows = matrix_rows)
      lanes = []
      rows.each_with_index.select { |row, _index| row[:combined] }.map do |row, last|
        first = rows.index { |other| row[:combined].include?(other[:label]) }
        lane = lanes.index { |spans| spans.none? { |from, to| from <= last && first <= to } } || lanes.size
        (lanes[lane] ||= []) << [first, last]
        marks = rows.each_with_index.map do |other, index|
          next nil unless index.between?(first, last)

          segment = if index == first
            "top"
          elsif index == last
            "bot"
          else
            "mid"
          end
          stop = if index == last
            "result"
          elsif row[:combined].include?(other[:label])
            "in"
          else
            "out"
          end
          {segment: segment, stop: stop}
        end
        {label: row[:label], lane: lane, marks: marks}
      end
    end

    # The jamboree comparison by contract: {label => {counts: {column => n}, sum:}}
    # plus "Summe". By the contract alone: in force (a replacement pending
    # counts, the old contract is in force until then), being cancelled
    # (status "Abmeldung vermerkt") and none yet; ended contracts and
    # deregistrations are no longer on the way to the jamboree.
    def jamboree_rows
      @jamboree_rows ||= JAMBOREE_ROWS.to_h do |label, roles|
        list = entries.select { |e| roles.include?(e.wsj_role) }
        [label, jamboree_row(list)]
      end
    end

    # The tiles of people over the matrix: label => the jamboree rows they add
    # up, and the matrix row counting the same people.
    PEOPLE_TILES = {
      "CMT" => {jamboree: %w[CMT], matrix_row: "CMT"},
      "IST" => {jamboree: %w[IST], matrix_row: "IST inkl. BMT"},
      "CMT + IST" => {jamboree: %w[CMT IST], matrix_row: "CMT + IST inkl. BMT"},
      "UL + YP" => {jamboree: ["UL + YP"], matrix_row: "UL + YP"}
    }.freeze

    # The big number of a tile of people: the matrix columns bestätigt and
    # offen (a contract in force, no deregistration noted, no new contract
    # pending) of its jamboree roles -- the rule of the matrix, so the tile and
    # its row's "Summe" are the same number.
    def tile_in_force(*jamboree_keys)
      roles = jamboree_keys.flat_map { |key| JAMBOREE_ROWS.fetch(key) }
      in_force = MATRIX_COLUMNS.fetch("inforce")[:subtotal]
      entries.count { |e| roles.include?(e.wsj_role) && in_force.include?(e.contract_column) }
    end

    # The matrix cells ("Summe" under "Vertrag in Kraft") that show a tile's
    # number: matrix row label => tile label.
    def matrix_tile_marks(rows)
      labels = rows.pluck(:label)
      PEOPLE_TILES.to_h { |tile, spec| [spec[:matrix_row], tile] }.slice(*labels)
    end

    # The units (WSJRDP unit groups with people) and the patrols they are
    # divided into (people.patrol, set on a unit's Patrols tab): all, and those
    # with at least one person whose contract is in force. A unit is divided
    # when all its active people (not deregistered, no deregistration noted)
    # have a patrol, partly when some do.
    # {units: {total:, inforce:, undivided:, partly:}, patrols: {total:}}
    def unit_figures
      units = ::Group.where(type: "Group::Unit", is_wsjrdp: true)
        .where(id: ::Person.select(:primary_group_id)).pluck(:id)
      people = ::Person.where(primary_group_id: units)
      active = people.where("people.status IS NULL OR people.status NOT IN ('deregistered', 'deregistration_noted')")
      in_force = active.where(contract_status: ::Person::CONTRACT_IN_FORCE)
      with_patrol = ->(scope) { scope.where.not(patrol: [nil, ""]) }
      patrols = ->(scope) { with_patrol.call(scope).distinct.pluck(:primary_group_id, :patrol).size }
      divided = with_patrol.call(active).group(:primary_group_id).count
      members = active.group(:primary_group_id).count
      {
        units: {total: units.size, inforce: in_force.distinct.count(:primary_group_id),
                undivided: members.keys.count { |unit| divided[unit].to_i.zero? },
                partly: members.count { |unit, n| divided[unit].to_i.between?(1, n - 1) }},
        patrols: {total: patrols.call(active)}
      }
    end

    # The people whose jamboree role differs, in all groups: "CMT→JPT" => entries.
    def role_differences
      entries.select(&:role_difference).sort_by { |e| [e.name.downcase, e.id] }.group_by(&:role_difference).sort.to_h
    end

    private

    def jamboree_row(list)
      columns = list.group_by { |e| jamboree_column(e) }.except(nil)
      counts = JAMBOREE_COLUMNS.keys.index_with { |key| columns.fetch(key, []).size }
      # Of "inforce", the ones whose new contract is still pending.
      pending = columns.fetch("inforce", []).count { |e| e.contract_status == "replacement_pending" }
      {counts: counts, sum: counts.values_at(*JAMBOREE_TOTAL_COLUMNS).sum, pending: pending, entries: columns}
    end

    # The column of the jamboree comparison, by the contract (JAMBOREE_COLUMNS);
    # nil for a deregistration without a contract, and for in force or none
    # outside the WSJRDP groups.
    def jamboree_column(entry)
      return "cancel" if entry.status == "deregistration_noted"
      return "ended" if entry.contract_status == "ended"
      return nil unless entry.wsjrdp

      case entry.contract_status
      when *::Person::CONTRACT_IN_FORCE then "inforce"
      else (entry.status == "deregistered") ? nil : "none"
      end
    end

    # The people of the matrix: a state one of its columns counts, in WSJRDP
    # groups or -- for a column counting everywhere -- in any group.
    def matrix_entries
      entries.select { |e| MATRIX_COLUMNS.values.any? { |column| matrix_column?(column, e) } }
    end

    def matrix_column?(column, entry) = column[:states].include?(entry.state) && (column[:everywhere] || entry.wsjrdp)

    def matrix_counts(list)
      counts = MATRIX_COLUMNS.transform_values { |column| list.count { |e| matrix_column?(column, e) } }
      {counts: counts, sum: MATRIX_COLUMNS.sum { |key, column| column[:in_sum] ? counts[key] : 0 }}
    end
  end
end
