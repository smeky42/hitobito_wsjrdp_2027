# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Kontingent > Units: every unit that is a WSJRDP group and has people with a
# contract in force, with how many they are and how many are deregistering
# (Wsjrdp2027::ContingentUnits), narrowed by the Schnellauswahl
# (Wsjrdp2027::ContingentUnitsFilterSchema::PRESETS); a row opens the unit's
# people (#show, loaded into the row's frame) -- a table of their own, with
# the filter of the overview's people list. Like the IST tab, only for
# whoever may see the contingent's people
# (WsjrdpContingentHelper#contingent_people_visible?).
class Contingent::WsjrdpUnitsController < ApplicationController
  include Wsjrdp::TableStateful
  include WsjrdpContingentHelper

  # While nobody has chosen a sort: by name, A2 before A10.
  UNITS_POLICY = wsjrdp_expandable_table_policy prefix: "un",
    columns: Wsjrdp2027::ContingentUnitsColumns::COLUMNS.codec,
    cols: {default: Wsjrdp2027::ContingentUnitsColumns::COLUMNS.default_keys},
    sort: {hidden: [["name", "asc"]]},
    per_page: {default: 100},
    view: {default: "history", values: Wsjrdp2027::ContingentUnitsColumns::VIEWS},
    filter: {policy: :url, schema: Wsjrdp2027::ContingentUnitsFilterSchema,
             presets: Wsjrdp2027::ContingentUnitsFilterSchema::PRESETS},
    # Versioned like PEOPLE_POLICY's: v2 brought the column Haushalt, v3
    # "ohne Patrol".
    store_key: "contingent/wsjrdp_units#index:v3"

  # The people of one unit (Wsjrdp2027::ContingentUnits::PEOPLE_COLUMNS) with
  # the filter of the overview's people list and whether a person still
  # belongs to the unit (Wsjrdp2027::ContingentUnitPeopleFilterSchema) --
  # whoever moved to another group shows only when the switch of the filter
  # line asks for it; in the natural order while nobody has chosen a sort.
  PEOPLE_POLICY = wsjrdp_expandable_table_policy prefix: "up",
    columns: Wsjrdp2027::ContingentUnits::PEOPLE_COLUMNS.codec,
    cols: {default: %w[role person patrol contract status cancel budget]},
    sort: {hidden: Wsjrdp2027::ContingentUnits::PEOPLE_ORDER},
    per_page: {default: 50},
    filter: {policy: :url, schema: Wsjrdp2027::ContingentUnitPeopleFilterSchema,
             exclude: %i[group_kind group_name], presets: Wsjrdp2027::ContingentUnits::PEOPLE_PRESETS,
             fixed_groups: [Wsjrdp2027::ContingentUnitPeopleFilterSchema::PRESENCE_GROUP]},
    # The memory of columns and sort, versioned: a remembered column choice
    # keeps its order and hides every column added after it, so a change of
    # the columns comes with a new version -- and everybody starts on the
    # defaults again.
    store_key: "contingent/wsjrdp_units#show:v3"

  # The prefix of the frame a unit's people answer in on a direct visit.
  DETAIL_FRAME_PREFIX = "un"

  before_action :authorize_action
  before_action :ensure_unit, only: %i[show apply]

  helper_method :unit_rows, :unit_rows_summary, :unit, :unit_people, :unit_people_rows, :unit_people_table_state, :unit_people_summary

  def index
  end

  # A unit's people: in the frame of its row, or as a page of its own.
  def show
  end

  # Apply target of the people filter's pane (PRG, Wsjrdp::TableStateful),
  # back into the unit's frame.
  def apply
    wsjrdp_apply_table_filter(unit_people_table_state, redirect_to: contingent_unit_path(unit.id))
  end

  private

  def authorize_action
    authorize!(:show_wsjrdp_contingent, Group.root)
    raise CanCan::AccessDenied unless contingent_people_visible?
  end

  def ensure_unit
    raise ActiveRecord::RecordNotFound unless unit
  end

  def contingent_units = @contingent_units ||= Wsjrdp2027::ContingentUnits.new

  # A unit without anybody whose contract is in force is left out -- the
  # registration groups, a unit not filled yet.
  def unit_rows
    @unit_rows ||= Wsjrdp::ExpandableTableRows.new(unit_table_state, unit_rows_filtered,
      sort: Wsjrdp2027::ContingentUnitsColumns.sort_lambdas, tiebreaker: ->(unit) { unit.id })
  end

  def unit_table_state = @unit_table_state ||= wsjrdp_expandable_table_state(UNITS_POLICY)

  def unit_rows_filtered
    @unit_rows_filtered ||= unit_table_state.filter.scope(
      contingent_units.units.select { |unit| unit.in_force_total.positive? }
    )
  end

  # "37 Units, 12 mit unvollständiger Patrol-Einteilung" -- over all units
  # the filter leaves, not only the page.
  def unit_rows_summary
    total = unit_rows.total_count
    incomplete = unit_rows_filtered.count(&:patrols_incomplete?)
    text = "#{total} #{(total == 1) ? "Unit" : "Units"}"
    incomplete.positive? ? "#{text}, #{incomplete} mit unvollständiger Patrol-Einteilung" : text
  end

  def unit = @unit ||= contingent_units.find(params[:id])

  def unit_people_table_state = wsjrdp_expandable_table_state(PEOPLE_POLICY)

  def unit_people_rows
    @unit_people_rows ||= Wsjrdp::ExpandableTableRows.new(unit_people_table_state, unit_people_filtered,
      sort: Wsjrdp2027::ContingentUnits.people_sort_lambdas(unit), tiebreaker: ->(entry) { entry.id })
  end

  def unit_people_filtered = @unit_people_filtered ||= unit_people_table_state.filter.scope(unit.people_rows)

  # The summary of a unit's people as the filter leaves them: the people
  # staying, then "+ n in Abmeldung", "+ n abgemeldet" and "+ n gewechselt"
  # where there are any.
  def unit_people_summary
    cancelling = unit_people_filtered.count { |e| Wsjrdp2027::ContingentUnits.cancelling?(e) }
    deregistered = unit_people_filtered.count { |e| Wsjrdp2027::ContingentUnits.deregistered?(e) }
    moved = unit_people_filtered.count { |e| unit.moved?(e) }
    staying = unit_people_filtered.size - cancelling - deregistered - moved
    parts = ["#{staying} #{(staying == 1) ? "Person" : "Personen"}"]
    parts << "+ #{cancelling} in Abmeldung" if cancelling.positive?
    parts << "+ #{deregistered} abgemeldet" if deregistered.positive?
    parts << "+ #{moved} gewechselt" if moved.positive?
    parts.join(" ")
  end

  # The people on the shown page in full -- name and mini tags need them -- by id.
  def unit_people
    @unit_people ||= Person.where(id: unit_people_rows.page.map(&:id)).includes(:tags, :primary_group)
      .index_by(&:id)
  end
end
