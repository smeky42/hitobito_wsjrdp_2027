# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # The units of Kontingent > Units (Contingent::WsjrdpUnitsController): every
  # unit that is a WSJRDP group, with the people whose primary group it is and
  # how many of them are in which state of their contract. The people are the
  # entries of ContingentOverview -- loaded with a handful of columns for all
  # units at once.
  #
  # A person who is leaving -- in Abmeldung or deregistered -- and no longer
  # has a unit as primary group (a deregistration moves a person onto a
  # waiting list) counts for the unit they were in last: the unit of their
  # latest role in a unit (.last_unit_ids). Only units with people whose
  # contract is in force take them, so the registration groups never do.
  #
  # The movements of a unit since it was formed come from its roles, ended
  # ones included (one query for all units, one for where the newcomers came
  # from): who was in it on the day of the Unit-Einteilung
  # (Group#effective_unit_formed_date), who left it, who came, who was
  # swapped. They add up: eingeteilt - verlassen + nachgerückt = jetzt
  # (Unit#balanced?), a swap counting for neither unit.
  class ContingentUnits
    # A helpdesk ticket key in a ticket field (ContractHelper#auto_link_escaped_multiline
    # links the same keys).
    TICKET_KEY = /\b(?:FIN|HELP)-[0-9]+\b/

    # One movement of a unit (Unit#movements):
    #
    # - :deregistered -- left the contingent: status deregistered or the
    #   contract ended (still holding a role in the unit or not)
    # - :cancelling   -- in Abmeldung (status deregistration_noted); counts as
    #   gone already, like the contract column "in Kraft" leaves it out --
    #   `present` while the person still holds a role in the unit
    # - :moved        -- left the unit, not the contingent (to another unit,
    #   onto a waiting list, into another group; `group_id`: where to)
    # - :swapped      -- left the unit for another one, whose `partner` came
    #   from there on the same day (`group_id`: that unit)
    # - :arrived      -- came after the unit was formed, not by a swap
    #   (`group_id`: the group they came from, nil when no role says)
    #
    # `on`: the day -- of leaving (the last day of the role in the unit, else
    # the end of the contract), of the deregistration request, of arriving.
    Movement = Struct.new(:kind, :entry, :on, :group_id, :partner, :counted, :present, keyword_init: true)

    LEAVING_KINDS = %i[deregistered cancelling moved].freeze

    # One person in the people table of a unit: the entry, and whether the
    # person still belongs to the unit (ContingentUnitPeopleFilterSchema
    # "presence") -- "moved" for whoever left it for another group.
    class UnitPerson < SimpleDelegator
      attr_reader :presence

      def initialize(entry, presence)
        super(entry)
        @presence = presence
      end
    end

    # One unit and its people (ContingentOverview::Entry): `entries` have the
    # unit as primary group, `former_entries` were in it last and are leaving,
    # `moved_entries` left it without leaving the contingent (`left_on`:
    # person id => the last day of their role in the unit).
    #
    # - in force: own people with contract_status confirmed and the
    #   deregistration not being noted -- "bestätigt" with the status
    #   confirmed, "offen" with any other
    # - in Abmeldung: status deregistration_noted, whatever the contract
    # - abgemeldet: status deregistered or the contract ended, unless in
    #   Abmeldung
    #
    # `budget_cents`: the unit's effect on the budget (.budget_parts of its
    # people, whoever moved elsewhere left out -- they count where they are
    # now); `budget_pending_cents`: what the people in Abmeldung would add.
    #
    # `target_size`: the size the unit is to have
    # (Group#effective_expected_unit_size); `formed_count`: the people with a
    # role in it on `formed_on`; `now_count`: the people with a role in it
    # today who are not leaving (in Abmeldung or deregistered); `joined`: person id => the first day of
    # their roles in the unit; `swapped_with`: person id => the swap partner's
    # entry.
    Unit = Struct.new(:id, :name, :formed_on, :target_size, :entries, :former_entries, :moved_entries, :left_on,
      :joined, :swapped_with, :movements, :formed_count, :now_count, :budget_cents, :budget_pending_cents,
      keyword_init: true) do
      def confirmed = in_force.count { |e| e.status == "confirmed" }

      def open = in_force.count { |e| e.status != "confirmed" }

      def in_force_total = in_force.size

      # The people in force (#in_force) not in a patrol yet: an UL or YP whose
      # patrol is "none" (ContingentOverview.patrol_value); whoever has no
      # place in a patrol (another role) does not count.
      def without_patrol = in_force.count { |e| e.patrol == "none" }

      def patrols_incomplete? = without_patrol.positive?

      # Nobody in force has a patrol yet -- the unit is not divided at all.
      def patrols_unset? = patrols_incomplete? && in_force.none? { |e| e.patrol.present? && e.patrol != "none" }

      def cancelling = cancelling_entries.size

      def in_force
        @in_force ||= entries.select { |e| e.contract_status == "confirmed" && e.status != "deregistration_noted" }
      end

      def all_entries = entries + former_entries + moved_entries

      def cancelling_entries = all_entries.select { |e| ContingentUnits.cancelling?(e) }

      def deregistered_entries = all_entries.select { |e| ContingentUnits.deregistered?(e) }

      def former?(entry) = former_entries.any? { |e| e.id == entry.id }

      def moved?(entry) = left_on.key?(entry.id)

      # Whoever no longer belongs to the unit: moved elsewhere, or deregistered.
      def gone?(entry) = moved?(entry) || ContingentUnits.deregistered?(entry)

      # The people table's rows (UnitPerson).
      def people_rows = all_entries.map { |e| UnitPerson.new(e, moved?(e) ? "moved" : "current") }

      # The movements by column, each by day.
      def left_movements = movements_of(*LEAVING_KINDS)

      def swap_movements = movements_of(:swapped)

      def arrival_movements = movements_of(:arrived)

      def movements_by_day = movements.sort_by { |m| [m.on || Date.new(0), m.entry.id] }

      def left_count = left_movements.count(&:counted)

      def arrived_count = arrival_movements.size

      # The open deregistrations of the unit: everybody in Abmeldung, holding a
      # role in the unit still or not -- all of them in "verlassen".
      def open_cancelling = left_movements.count { |m| m.kind == :cancelling }

      def expected_now = formed_count - left_count + arrived_count

      def balanced? = expected_now == now_count

      private

      def movements_of(*kinds) = movements.select { |m| kinds.include?(m.kind) }.sort_by { |m| [m.on || Date.new(0), m.entry.id] }
    end

    def self.cancelling?(entry) = entry.status == "deregistration_noted"

    def self.deregistered?(entry)
      !cancelling?(entry) && (entry.status == "deregistered" || entry.contract_status == "ended")
    end

    def self.leaving?(entry) = cancelling?(entry) || deregistered?(entry)

    # What a person means for the budget, in cents (`person`: in full):
    # - einbehalt: what a deregistration keeps -- the compensation entered on
    #   the Abmeldung page, else the one of the T&R; for whoever is leaving
    # - reduction: a fee reduction, unless it comes from the JSF (its hint);
    #   not for whoever is deregistered
    # - counted: + einbehalt of the deregistered, − reduction
    # - pending: + einbehalt of whoever is in Abmeldung -- not counted while
    #   the deregistration runs
    def self.budget_parts(entry, person)
      einbehalt = leaving?(entry) ? (person.deregistration_actual_compensation_cents ||
        person.deregistration_contractual_compensation_cents).to_i : 0
      reduction = deregistered?(entry) ? 0 : reduction_cents(person)
      {einbehalt: einbehalt, reduction: reduction,
       counted: (deregistered?(entry) ? einbehalt : 0) - reduction,
       pending: cancelling?(entry) ? einbehalt : 0}
    end

    def self.reduction_cents(person)
      return 0 if person.wsjrdp_total_fee_reduction_hint.to_s.strip.casecmp?("JSF")

      ((person.wsjrdp_total_fee_reduction.to_d + person.wsjrdp_extra_total_fee_reduction.to_d) * 100).round
    end

    # The order of the people of a unit: the leaders first, then the youth
    # participants, then anybody else; by name within each.
    ROLE_ORDER = {"UL" => 0, "YP" => 1}.freeze

    # The natural order of a unit's people: who is in Abmeldung first, then
    # whoever has no contract in force, then whose status is not confirmed --
    # what needs looking at on top --, the deregistered and whoever moved
    # elsewhere (Unit#moved?) at the very end; then
    # by ROLE_ORDER and name.
    def self.people_natural_key(entry, moved: false)
      leaving = if cancelling?(entry) then 0
      elsif deregistered?(entry) || moved then 2
      else
        1
      end
      [leaving, (entry.contract_status == "confirmed") ? 1 : 0,
        (entry.status == "confirmed") ? 1 : 0, ROLE_ORDER.fetch(entry.wsjrdp_role, ROLE_ORDER.size),
        entry.name.to_s.downcase]
    end

    # The columns of a unit's people table, from left to right: the role (its
    # own here, so it can stay at the left with the person), the person, the
    # patrol, contract and status, since when the contract is in force
    # (contract_confirmed_at) and since when the person is in the unit
    # (Unit#joined; its sort needs the unit, .people_sort_lambdas) -- these
    # two hidden by default --, "in Abmeldung" (an icon; it sorts by the
    # natural order, .people_natural_key, the order while nobody has chosen a
    # sort) and the person's effect on the budget
    # (WsjrdpContingentHelper#contingent_budget_cell, from the person in full,
    # so not sortable). The overview's "Grund" and "Gruppe" are left out.
    PEOPLE_COLUMNS = begin
      overview = ContingentPeopleColumns::COLUMNS
      role = Wsjrdp::ExpandableTableColumn.new(key: "role", abbr: "ro", label: "Rolle", width: "4rem",
        truncate: true, sticky: true, css_class: "upcol-role", sort: ->(_e) { 0 }, default: true)
      cancel = Wsjrdp::ExpandableTableColumn.new(key: "cancel", abbr: "ca", label: "in Abmeldung",
        header_tooltip: "Abmeldung vermerkt (Status deregistration_noted); sortiert: Abmeldung, ohne Vertrag " \
                        "in Kraft, nicht bestätigt, dann Rolle und Name",
        width: "7.5rem", header_align: "center", css_class: "upcol-cancel",
        sort: ->(e) { people_natural_key(e) }, default: true)
      confirmed_at = Wsjrdp::ExpandableTableColumn.new(key: "confirmed_at", abbr: "cs", label: "Vertrag seit",
        header_tooltip: "Vertrag bestätigt am", width: "7rem", css_class: "upcol-confirmed_at", tabular_nums: true,
        sort: ->(e) { date_sort_key(e.contract_confirmed_at&.to_date) }, sort_first: "desc")
      joined = Wsjrdp::ExpandableTableColumn.new(key: "joined", abbr: "js", label: "in Unit seit",
        header_tooltip: "Beginn der ersten Rolle in dieser Unit", width: "7rem", css_class: "upcol-joined",
        tabular_nums: true, sort: ->(_e) { 0 }, sort_first: "desc")
      budget = Wsjrdp::ExpandableTableColumn.new(key: "budget", abbr: "hh", label: "Haushalt", numeric: true,
        header_tooltip: "Wirkung auf den Haushalt: + Einbehalt bei Abmeldung (grau, solange sie noch läuft), " \
                        "− Beitragsreduktion (ohne JSF)",
        width: "7.5rem", css_class: "upcol-budget", default: true)
      # The overview's person, narrower: on a phone role and person stay at
      # the left while the rest scrolls, and leave room for it; where there
      # is room, the person widens as on the overview.
      overview_person = overview.fetch("person")
      person = Wsjrdp::ExpandableTableColumn.new(key: overview_person.key, abbr: overview_person.abbr,
        label: overview_person.label, width: "9.5rem", target_width: overview_person.target_width,
        grow: overview_person.grow, truncate: true, sticky: true, css_class: overview_person.css_class,
        sort: overview_person.sort, default: true)
      # The overview's patrol, centred: one letter under a header of six.
      shared = overview.fetch("patrol")
      patrol = Wsjrdp::ExpandableTableColumn.new(key: shared.key, abbr: shared.abbr, label: shared.label,
        width: shared.width, header_align: "center", css_class: "upcol-patrol", sort: shared.sort,
        default: true)
      Wsjrdp::ExpandableTableColumns.new([role, person, patrol,
        overview.fetch("contract"), overview.fetch("status"), confirmed_at, joined, cancel, budget])
    end

    PEOPLE_ORDER = [["cancel", "asc"]].freeze

    # The sorts of the people table of a unit: those of the overview's list,
    # but the role by ROLE_ORDER (the overview sorts it alphabetically), and
    # the day of joining the unit.
    def self.people_sort_lambdas(unit)
      PEOPLE_COLUMNS.sort_expressions.merge(
        "role" => ->(e) { [ROLE_ORDER.fetch(e.wsjrdp_role, ROLE_ORDER.size), (e.role_difference || e.wsjrdp_role).to_s] },
        "joined" => ->(e) { date_sort_key(unit.joined[e.id]) },
        "cancel" => ->(e) { people_natural_key(e, moved: unit.moved?(e)) }
      )
    end

    # A day for sorting, a missing one before every other.
    def self.date_sort_key(date) = date ? [1, date] : [0, Date.new(0)]

    # The Schnellauswahl of a unit's people, over
    # Wsjrdp2027::ContingentUnitPeopleFilterSchema: the role, the contract as
    # the overview's matrix counts it (ContingentOverview::MATRIX_COLUMNS) and
    # whether an UL or YP is still without a patrol -- each an exclusive
    # group, the asterisk for all.
    PEOPLE_PRESETS = [
      {group: "wsjrdp_role", attribute: "wsjrdp_role", operator: "in", exclusive: true,
       members: [{key: "leaders", label: "UL", value: "UL"}, {key: "participants", label: "YP", value: "YP"}]},
      {group: "contract_column", attribute: "contract_column", operator: "in", exclusive: true,
       members: [{key: "in_force", label: "Vertrag in Kraft", value: %w[full docs]},
         {key: "cancelling", label: "in Abmeldung", value: "cancel"},
         {key: "no_contract", label: "ohne Vertrag", value: "none"},
         {key: "ended", label: "abgemeldet", value: "ended"}]},
      {group: "patrol", attribute: "patrol", operator: "in", exclusive: true,
       members: [{key: "no_patrol", label: "Patrol nicht gesetzt", value: "none"}]}
    ].freeze

    def initialize(overview = ContingentOverview.new)
      @overview = overview
    end

    def units
      @units ||= begin
        by_group = @overview.entries.group_by(&:group_id)
        units = ::Group::Unit.without_deleted.where(is_wsjrdp: true).map do |group|
          Unit.new(id: group.id, name: group.name, formed_on: group.effective_unit_formed_date,
            target_size: group.effective_expected_unit_size,
            entries: self.class.sort_people(by_group.fetch(group.id, [])), former_entries: [], moved_entries: [],
            left_on: {}, joined: {}, swapped_with: {}, movements: [], formed_count: 0, now_count: 0,
            budget_cents: 0, budget_pending_cents: 0)
        end
        attach_former(units)
        attach_movements(units)
        attach_budget(units)
        units
      end
    end

    def find(id) = units.find { |unit| unit.id == id.to_i }

    # The unit each person was in last, by person id: the unit of the latest
    # of their roles in one of `unit_ids` -- a role without an end first, then
    # the latest end, the latest start, the latest role. Ended roles stay in
    # `roles` (end_on), so this reaches back past a move onto a waiting list.
    def self.last_unit_ids(person_ids, unit_ids)
      return {} if person_ids.empty? || unit_ids.empty?

      sql = ::Role.sanitize_sql_array([<<~SQL.squish, person_ids, unit_ids])
        SELECT DISTINCT ON (roles.person_id) roles.person_id, roles.group_id
        FROM roles
        WHERE roles.person_id IN (?) AND roles.group_id IN (?)
        ORDER BY roles.person_id, roles.end_on DESC NULLS FIRST, roles.start_on DESC NULLS LAST, roles.id DESC
      SQL
      ::Role.connection.select_rows(sql).to_h
    end

    # The roles, ended ones included: [person id, group id, start_on, end_on]
    # -- in `group_ids` (nil: in any group), of `person_ids` (nil: anybody's).
    def self.role_rows(group_ids, person_ids: nil)
      return [] if group_ids&.empty? || person_ids&.empty?

      conditions = []
      values = []
      (conditions << "roles.group_id IN (?)") && (values << group_ids) if group_ids
      (conditions << "roles.person_id IN (?)") && (values << person_ids) if person_ids
      sql = "SELECT roles.person_id, roles.group_id, roles.start_on, roles.end_on FROM roles " \
        "WHERE #{conditions.join(" AND ")}"
      ::Role.connection.select_rows(::Role.sanitize_sql_array([sql, *values])).map do |person_id, group_id, start_on, end_on|
        [person_id, group_id, start_on&.to_date, end_on&.to_date]
      end
    end

    def self.sort_people(entries)
      entries.sort_by { |e| [ROLE_ORDER.fetch(e.wsjrdp_role, ROLE_ORDER.size), e.name.to_s.downcase, e.id] }
    end

    # A unit name for sorting: "A2" before "A10" -- the letters, then the
    # number, then the rest.
    def self.name_sort_key(name)
      letters, number, rest = name.to_s.match(/\A(\D*)(\d*)(.*)\z/m).captures
      [letters.downcase, number.empty? ? -1 : number.to_i, rest.downcase]
    end

    private

    # The leaving people outside the units, each into the unit they were in
    # last (.last_unit_ids) -- among the units with people in force.
    def attach_former(units)
      real = units.select { |unit| unit.in_force_total.positive? }.index_by(&:id)
      unit_ids = units.map(&:id).to_set
      leaving = @overview.entries.select { |e| !unit_ids.include?(e.group_id) && self.class.leaving?(e) }
      by_id = leaving.index_by(&:id)
      self.class.last_unit_ids(by_id.keys, real.keys).each do |person_id, unit_id|
        real.fetch(unit_id).former_entries << by_id.fetch(person_id)
      end
      real.each_value { |unit| unit.former_entries = self.class.sort_people(unit.former_entries) }
    end

    def entries_by_id = @entries_by_id ||= @overview.entries.index_by(&:id)

    # The budget of the units with people in force (Unit#budget_cents,
    # Unit#budget_pending_cents): only the people it can concern are loaded in
    # full -- whoever is leaving, whoever has a fee reduction.
    def attach_budget(units)
      real = units.select { |unit| unit.in_force_total.positive? }
      counted = real.to_h { |unit| [unit, unit.all_entries.reject { |e| unit.moved?(e) }] }
      ids = counted.values.flatten.map(&:id)
      reduced = ::Person.where(id: ids)
        .where("people.wsjrdp_total_fee_reduction > 0 OR people.wsjrdp_extra_total_fee_reduction > 0").pluck(:id)
      leaving = counted.values.flatten.select { |e| self.class.leaving?(e) }.map(&:id)
      people = ::Person.where(id: (reduced + leaving).uniq).preload(:wsjrdp_deregistrations).index_by(&:id)
      counted.each do |unit, entries|
        entries.each do |entry|
          person = people[entry.id] or next
          parts = self.class.budget_parts(entry, person)
          unit.budget_cents += parts[:counted]
          unit.budget_pending_cents += parts[:pending]
        end
      end
    end

    # A person's stay in a unit, from their roles there: the first day, whether
    # a role is active today, the last day of the latest ended one.
    Stay = Struct.new(:first, :active, :last, keyword_init: true) do
      def at?(day) = (first.nil? || first <= day) && (active || (last && last >= day))
    end

    # The movements of the units with people in force (Unit#movements), and
    # what the people list needs from them (joined, left_on, moved_entries,
    # swapped_with).
    def attach_movements(units)
      real = units.select { |unit| unit.in_force_total.positive? }
      by_id = entries_by_id
      stays = stays_by_unit(real)
      units.each { |unit| stays.fetch(unit.id, {}).each { |person_id, stay| unit.joined[person_id] = stay.first } }
      departures = real.to_h { |unit| [unit.id, departures(unit, stays.fetch(unit.id, {}), by_id)] }
      swaps = find_swaps(real, departures, stays)
      sources = arrival_sources(real, stays)
      real.each do |unit|
        unit_stays = stays.fetch(unit.id, {})
        unit.formed_count = unit_stays.count { |_, stay| stay.at?(unit.formed_on) }
        # Who is in the unit today: an active role, and not leaving -- the
        # same people as "Vertrag in Kraft" plus those without a contract yet.
        unit.now_count = unit_stays.count { |person_id, stay| stay.active && !self.class.leaving?(by_id[person_id]) }
        departures.fetch(unit.id).each do |person_id, last|
          add_departure(unit, by_id.fetch(person_id), last, swaps[[unit.id, person_id]])
        end
        unit_stays.each do |person_id, stay|
          entry = by_id[person_id]
          next unless entry && stay.active && self.class.leaving?(entry)

          unit.movements << if self.class.cancelling?(entry)
            Movement.new(kind: :cancelling, entry: entry, on: entry.deregistration_requested_date, counted: true,
              present: true)
          else
            Movement.new(kind: :deregistered, entry: entry, on: entry.contract_ended_at&.to_date, counted: true)
          end
        end
        # Who came by a swap: left their unit for this one (keyed by where they left).
        incoming = swaps.filter_map { |(_from, person_id), swap| person_id if swap[:to] == unit.id }
        unit_stays.each do |person_id, stay|
          next unless stay.first && stay.first > unit.formed_on && by_id[person_id] && incoming.exclude?(person_id)

          unit.movements << Movement.new(kind: :arrived, entry: by_id[person_id], on: stay.first,
            group_id: sources[[unit.id, person_id]], counted: true)
        end
        unit.moved_entries = self.class.sort_people(unit.moved_entries)
      end
    end

    # Each person's stay in each unit, from one query of all their roles.
    def stays_by_unit(units)
      today = Date.current
      self.class.role_rows(units.map(&:id)).group_by { |_, group_id| group_id }.transform_values do |rows|
        rows.group_by(&:first).transform_values do |person_rows|
          starts = person_rows.pluck(2)
          active = person_rows.any? { |_, _, start_on, end_on| (start_on.nil? || start_on <= today) && (end_on.nil? || end_on >= today) }
          Stay.new(first: starts.include?(nil) ? nil : starts.min, active: active,
            last: active ? nil : person_rows.filter_map { |row| row[3] }.max)
        end
      end
    end

    # Who left the unit since it was formed: person id => the last day of
    # their stay -- whoever holds no role in it today and was in it on or after
    # that day; people without a primary group are left out.
    def departures(unit, unit_stays, by_id)
      unit_stays.filter_map do |person_id, stay|
        next if stay.active || stay.last.nil? || stay.last < unit.formed_on || by_id[person_id].nil?

        [person_id, stay.last]
      end.to_h
    end

    # The swaps: a person who left unit X and is in unit Y now, and one who
    # left Y and is in X now, both starting in their new unit on the same day
    # (the first day of their stay there -- the old role may have ended
    # later). Several on one day pair up in a fixed order (role, then id).
    # [unit id, person id] => {to:, partner_id:, on:}.
    def find_swaps(units, departures, stays)
      by_id = entries_by_id
      unit_ids = units.map(&:id).to_set
      moves = departures.flat_map do |unit_id, left|
        left.keys.filter_map do |person_id|
          entry = by_id[person_id]
          next if self.class.leaving?(entry) || !unit_ids.include?(entry.group_id)

          arrived = stays.dig(entry.group_id, person_id)&.first
          [unit_id, entry.group_id, arrived, entry] if arrived
        end
      end
      grouped = moves.group_by { |from, to, arrived, _| [from, to, arrived] }
      order = ->(list) { list.map(&:last).sort_by { |e| [ROLE_ORDER.fetch(e.wsjrdp_role, ROLE_ORDER.size), e.id] } }
      grouped.each_with_object({}) do |((from, to, arrived), outgoing), swaps|
        next unless from < to

        order.call(outgoing).zip(order.call(grouped.fetch([to, from, arrived], []))).each do |there, back|
          next unless there && back

          swaps[[from, there.id]] = {to: to, partner_id: back.id, on: arrived}
          swaps[[to, back.id]] = {to: from, partner_id: there.id, on: arrived}
        end
      end
    end

    def add_departure(unit, entry, last, swap)
      if self.class.leaving?(entry)
        kind = self.class.cancelling?(entry) ? :cancelling : :deregistered
        unit.movements << Movement.new(kind: kind, entry: entry, on: last, counted: true)
        return
      end
      unit.moved_entries << entry
      unit.left_on[entry.id] = last
      if swap
        partner = entries_by_id.fetch(swap[:partner_id])
        unit.swapped_with[entry.id] = partner
        unit.movements << Movement.new(kind: :swapped, entry: entry, on: swap[:on], group_id: swap[:to],
          partner: partner, counted: false)
      else
        unit.movements << Movement.new(kind: :moved, entry: entry, on: last, group_id: entry.group_id, counted: true)
      end
    end

    # Where each newcomer came from: the group of their latest role that began
    # before they came. [unit id, person id] => group id.
    def arrival_sources(units, stays)
      arrivals = units.flat_map do |unit|
        stays.fetch(unit.id, {}).filter_map do |person_id, stay|
          [unit.id, person_id, stay.first] if stay.first && stay.first > unit.formed_on
        end
      end
      return {} if arrivals.empty?

      roles = self.class.role_rows(nil, person_ids: arrivals.pluck(1).uniq).group_by(&:first)
      arrivals.to_h do |unit_id, person_id, first|
        before = roles.fetch(person_id, []).select { |_, group_id, start_on| group_id != unit_id && start_on && start_on < first }
        [[unit_id, person_id], before.max_by { |row| [row[2], row[3] || Date.new(9999)] }&.at(1)]
      end
    end
  end
end
