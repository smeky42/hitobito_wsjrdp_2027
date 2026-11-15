# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

module Wsjrdp2027
  # Column definitions of the unit list on Kontingent > Units: one
  # ContingentUnits::Unit per row, array-backed, so every column sorts by an
  # extractor. After the name the people in force not in a patrol yet; the
  # three contract columns stand under "Vertrag in Kraft", as
  # on the overview's matrix; then the movements since the unit was formed
  # (ContingentUnits::Unit#movements) and their balance.
  #
  # Narrow screens: the table scrolls sideways, the unit's name stays at the
  # left. Wide screens: the movement lines widen to their targets, then the
  # room goes to the gaps between the blocks -- the unit, "Patrol nicht gesetzt",
  # "Vertrag in Kraft", the movements with their balance, Haushalt (`t.gaps` and
  # GAPLESS in the view); inside a block the columns stay close.
  module ContingentUnitsColumns
    IN_FORCE = "Vertrag in Kraft"

    COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "uncol") do |c|
      c.column key: "name", abbr: "n", label: "Unit", width: "3.25rem", truncate: true, sticky: true,
        sort: ->(u) { ContingentUnits.name_sort_key(u.name) }, default: true
      c.column key: "without_patrol", abbr: "p", label: "Patrol nicht gesetzt", numeric: true, width: "5.5rem", target_width: "10.5rem",
        header_tooltip: "Personen mit Vertrag in Kraft (wie in „Summe“), die noch keiner Patrol zugeteilt sind – " \
                        "rot: niemand in der Unit hat eine Patrol, orange: ein Teil",
        sort_first: "desc", sort: ->(u) { u.without_patrol }, default: true
      c.column key: "confirmed", abbr: "b", label: "bestätigt", group: IN_FORCE, numeric: true, width: "5.75rem",
        header_tooltip: "Vertrag in Kraft, Status bestätigt", sort: ->(u) { u.confirmed }, default: true
      c.column key: "open", abbr: "o", label: "offen", group: IN_FORCE, numeric: true, width: "4rem",
        header_tooltip: "Vertrag in Kraft, Status nicht bestätigt", sort: ->(u) { u.open }, default: true
      c.column key: "in_force", abbr: "s", label: "Summe", group: IN_FORCE, numeric: true, width: "4.5rem",
        header_tooltip: "Vertrag in Kraft: bestätigt und offen", sort: ->(u) { u.in_force_total }, default: true
      # The movements since the unit was formed (ContingentUnits::Movement),
      # one line each: left as columns of their own or by day in one, the
      # view of the table choosing (VIEWS); sorted by their number. Narrow,
      # a line wraps between its parts; with room, the columns widen to
      # their targets, where the lines fit.
      c.column key: "left", abbr: "l", label: "verlassen", width: "12rem", target_width: "17rem",
        tabular_nums: true, sort_first: "desc",
        header_tooltip: "abgemeldet, in Abmeldung oder ohne Abmeldung in eine andere Gruppe gewechselt",
        sort: ->(u) { u.left_movements.size }, default: true
      c.column key: "swapped", abbr: "t", label: "getauscht", width: "12rem", target_width: "16rem",
        tabular_nums: true, sort_first: "desc",
        header_tooltip: "mit einer anderen Unit getauscht – für beide Units ohne Wirkung auf die Größe",
        sort: ->(u) { u.swap_movements.size }, default: true
      c.column key: "arrived", abbr: "r", label: "nachgerückt", width: "12rem", target_width: "19rem",
        tabular_nums: true, sort_first: "desc",
        header_tooltip: "nach der Unit-Einteilung ohne Tausch dazugekommen",
        sort: ->(u) { u.arrival_movements.size }, default: true
      c.column key: "movements", abbr: "m", label: "Bewegungen", width: "16rem", target_width: "24rem",
        tabular_nums: true, sort_first: "desc", header_tooltip: "alle Bewegungen seit der Unit-Einteilung, nach Tag",
        sort: ->(u) { u.movements.size }, default: true
      c.column key: "balance", abbr: "z", label: "Bilanz", numeric: true, width: "6.5rem",
        header_tooltip: "eingeteilt − verlassen + nachgerückt = jetzt",
        sort: ->(u) { [u.balanced? ? 1 : 0, u.now_count] }, default: true
      # The budget of the unit (Unit#budget_cents): Einbehalt of the
      # deregistered minus fee reductions; with those in Abmeldung below.
      c.column key: "budget", abbr: "h", label: "Haushalt", numeric: true, width: "6.75rem",
        header_tooltip: "Einbehalt der Abgemeldeten − Beitragsreduktionen (ohne JSF); " \
                        "darunter grau: mit dem Einbehalt der Personen in Abmeldung",
        sort: ->(u) { u.budget_cents }, default: true
    end

    # The two views of the movements: a column each for verlassen, getauscht
    # and nachgerückt, or one column with all of them by day.
    VIEWS = %w[history columns].freeze
    VIEW_COLUMNS = {"columns" => %w[left swapped arrived], "history" => %w[movements]}.freeze

    # The neighbours without a growing gap: the movement columns and their
    # balance are one block.
    GAPLESS = [%w[left swapped], %w[swapped arrived], %w[arrived balance], %w[movements balance]].freeze

    def self.sort_lambdas = COLUMNS.sort_expressions

    # The columns a view leaves out.
    def self.hidden_in(view) = VIEW_COLUMNS.except(view).values.flatten
  end
end
