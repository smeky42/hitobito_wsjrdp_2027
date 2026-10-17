# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The Abstimmung page "Unit-Buchungen" at /fin/reconciliation/unit_bookings
# (Fin::UnitBookingReconciliation): the figures over what the units see and one
# bookings table. The table starts with the OPEN bookings -- three switches of
# locked conditions (FIXED_GROUPS: the cost center a unit's own, no secondary
# cost center, not counting against the Unit-Budget) -- whose other positions
# the Schnellauswahl offers -- "Unit-KSt primär oder sekundär", "hat Wert" and
# "nein" are the bookings that carry a secondary cost center --, "Standard"
# the open ones again (doc/wsjrdp/expandable_table.md, "Fixed groups"). The user's filter narrows
# whatever is shown.
#
# Its bar of bulk actions (ACTIONS, Wsjrdp::BulkActions) marks the selection as
# Unit-Budget, sets or takes off its secondary cost center. Each action splits
# the selection itself (`partition`): what it changes, with what changes, and
# what it leaves alone -- which the panel previews and the action keeps to.
# Renders under the Abstimmung sheet with its tabs (Sheet::Fin::UnitBooking).
class Fin::UnitBookingsController < Fin::FinController
  include Wsjrdp::TableStateful
  include Wsjrdp::BulkActionable

  before_action :authorize_action
  # The bulk actions WRITE the bookings, so they need the write tier on top of
  # the section's :show gate, like the booking's own edit page (each action
  # names the same right for the bar).
  before_action :authorize_write, only: %i[bulk bulk_preview]

  helper_method :reconciliation, :bookings, :atoms, :filtered_figure, :may_assign?, :bulk_totals

  WRITE = [:update, DatevBooking].freeze

  # Three questions the table answers with locked conditions, one switch each
  # in the Schnellauswahl (doc/wsjrdp/expandable_table.md, "Fixed groups");
  # their defaults are the open bookings (Fin::UnitBookingReconciliation#open).
  # None of them the user can edit; the user filter only narrows. Their
  # conditions stay out of the filter line (show: :hidden): the pressed
  # switches say what is shown.
  FIXED_GROUPS = [
    {key: "kst", label: "KSt", default: "unit", show: :hidden,
     members: [{key: "all", label: "alle", slots: nil},
       {key: "unit", label: "Unit-KSt", slots: [[["unit_cost_center", "in", "true"]]]},
       {key: "unit_any", label: "Unit-KSt primär oder sekundär",
        slots: [[["any_unit_cost_center", "in", "true"]]]}]},
    {key: "cc2", label: "Sek KSt", default: "blank", show: :hidden,
     members: [{key: "any", label: "egal", slots: nil},
       {key: "blank", label: "leer", slots: [[["secondary_cost_center", "blank"]]]},
       {key: "set", label: "hat Wert", slots: [[["secondary_cost_center", "present"]]]}]},
    {key: "ub", label: "Unit-Budget?", default: "no", show: :hidden,
     members: [{key: "any", label: "egal", slots: nil},
       {key: "no", label: "nein", slots: [[["unit_budget", "in", "false"]]]},
       {key: "yes", label: "ja", slots: [[["unit_budget", "in", "true"]]]}]}
  ].freeze

  # The bookings ("ub"): the filter -- pins, lifts and the user's part -- stays
  # in the URL, so the page always shows what its link says.
  POLICY = wsjrdp_expandable_table_policy prefix: "ub",
    columns: Fin::DatevBookingsColumns.codec,
    sort: {hidden: [["booking_date", "desc"]]},
    cols: {default: %w[booking_date signed_base_amount posting_text cost_center_number
      secondary_cost_center_number account_number]},
    per_page: {default: 50},
    filter: {policy: :url, schema: Fin::DatevBookingsFilterSchema, fixed_groups: FIXED_GROUPS},
    pane: {default: 0}

  # What the bar over the selected bookings offers.
  ACTIONS = Wsjrdp::BulkActions.define(noun: {one: "Buchung", many: "Buchungen"}) do |a|
    a.action key: "unit_budget", label: "Als Unit-Budget markieren", icon: :wallet,
      hint: {one: "Zählt 1 ausgewählte Buchung zum Unit-Budget",
             many: "Zählt %{count} ausgewählte Buchungen zum Unit-Budget"},
      done: "%{count} Buchungen: als Unit-Budget markiert.", authorize: WRITE,
      partition: :unit_budget_partition, apply: :bulk_mark_unit_budget
    a.action key: "secondary_cost_center", label: "Sekundäre Kostenstelle setzen", icon: :tag,
      param: {name: :secondary_cost_center_number, label: "Sekundäre Kostenstelle",
              options: :secondary_cost_center_options, default: :proposed_secondary_cost_center},
      hint: {one: "Setzt %{target} als sekundäre Kostenstelle bei 1 ausgewählten Buchung",
             many: "Setzt %{target} als sekundäre Kostenstelle bei %{count} ausgewählten Buchungen"},
      done: "%{count} Buchungen: sekundäre Kostenstelle %{target} gesetzt.", authorize: WRITE,
      partition: :assign_partition, apply: :bulk_assign
    a.action key: "clear", label: "Sekundäre Kostenstelle löschen", icon: :eraser, danger: true,
      hint: {one: "Löscht die sekundäre Kostenstelle bei 1 ausgewählten Buchung",
             many: "Löscht die sekundäre Kostenstelle bei %{count} ausgewählten Buchungen"},
      done: "%{count} Buchungen: sekundäre Kostenstelle gelöscht.", authorize: WRITE,
      partition: :clear_partition, apply: :bulk_clear
  end

  # The columns of a panel's list of the bookings an action will touch (the
  # action's partition adds what changes).
  PREVIEW_COLUMNS = %w[booking_date signed_base_amount posting_text cost_center_number].freeze

  def index
  end

  # Apply target of the table's filter builder (PRG).
  def apply
    wsjrdp_apply_table_filter(table_state, redirect_to: reconciliation_unit_bookings_path)
  end

  # Runs a bulk action (ACTIONS) on the selection: the posted booking_ids, or
  # with select_all every booking of the current filter ("1") or those of the
  # named atoms (the quick-select). Ids outside the filtered table are ignored.
  def bulk
    redirect_back_to_list(**run_bulk_action(ACTIONS, scope: filtered, id_param: :booking_ids,
      atoms: atoms_of(Fin::UnitBookingReconciliation::OPEN_ATOM_SQL)))
  end

  # The bookings a bulk action would touch, for the panels of its bar
  # (Wsjrdp::BulkActionable#render_bulk_preview).
  def bulk_preview
    render_bulk_preview(ACTIONS, scope: filtered, id_param: :booking_ids,
      atoms: atoms_of(Fin::UnitBookingReconciliation::OPEN_ATOM_SQL),
      order: {booking_date: :desc, id: :desc}, preload: Fin::DatevBookingsColumns::PRELOADS,
      columns: ->(view) {
        view.booking_table_columns(condensed: true).select { |col| PREVIEW_COLUMNS.include?(col[:key]) }
      })
  end

  private

  Partition = Wsjrdp::BulkActions::Partition
  Group = Wsjrdp::BulkActions::Group

  # Als Unit-Budget markieren: the bookings not marked yet on a unit's own cost
  # center, with their answer so far. A booking on any other cost center cannot
  # count against a unit's budget -- the budget assignment follows its primary
  # cost center (doc/fin/unit_budget.md) -- so it is shown apart, with a
  # warning, and left alone; so are the ones marked already.
  def unit_budget_partition(selected, _value)
    unmarked = reconciliation.unmarked(selected)
    markable = reconciliation.markable(selected)
    Partition.new(affected: DatevBooking.with_unit_budget.where(id: markable.select(:id)),
      columns: [{label: "Bisher", cell: ->(booking) { helpers.fin_format_datev_booking_is_unit_budget(booking) }}],
      groups: [
        Group.new(rows: unmarked.where.not(id: markable.select(:id)), warning: true,
          text: "%{count} mit einer primären Kostenstelle, die keine Unit-Kostenstelle ist: " \
                "Sie lassen sich keiner Unit zuordnen und werden nicht markiert."),
        Group.new(rows: selected.where(is_unit_budget: true), text: "%{count} sind schon als Unit-Budget markiert.")
      ])
  end

  # Sekundäre Kostenstelle setzen: every selected booking whose secondary cost
  # center is another one, with the change; the ones carrying it already stay.
  def assign_partition(selected, number)
    target = reconciliation.assignable_cost_center!(number)
    Partition.new(
      affected: selected.where("datev_bookings.secondary_cost_center_number IS DISTINCT FROM ?", target.number),
      columns: [{label: "Sekundäre Kostenstelle",
                 cell: ->(booking) { "#{booking.secondary_cost_center_number.presence || "—"} → #{target.number}" }}],
      groups: [Group.new(rows: selected.where(secondary_cost_center_number: target.number),
        text: "%{count} haben schon #{Fin::UnitBookingReconciliation.label(target)}.")]
    )
  end

  # Sekundäre Kostenstelle löschen: the selected bookings that carry one, with
  # the one that goes; the others stay as they are.
  def clear_partition(selected, _value)
    Partition.new(affected: selected.where.not(secondary_cost_center_number: nil),
      columns: [{label: "Sekundäre Kostenstelle (wird gelöscht)",
                 cell: ->(booking) { helpers.fin_format_datev_booking_secondary_cost_center_number(booking) }}],
      groups: [Group.new(rows: selected.where(secondary_cost_center_number: nil),
        text: "%{count} ohne sekundäre Kostenstelle bleiben unverändert.")])
  end

  # The bulk actions' work (Wsjrdp::BulkActions `apply`), on the rows the
  # partition calls affected; each answers how many bookings changed.
  def bulk_mark_unit_budget(ids, _value) = reconciliation.mark_unit_budget!(ids)

  def bulk_assign(ids, number) = reconciliation.assign!(ids, number)

  def bulk_clear(ids, _value) = reconciliation.clear!(ids)

  # The secondary cost centers the bar offers, the one for the travel
  # accounts chosen at first.
  def secondary_cost_center_options
    reconciliation.assignable_cost_centers
      .map { |cost_center| [Fin::UnitBookingReconciliation.label(cost_center), cost_center.number] }
  end

  def proposed_secondary_cost_center = reconciliation.proposal_for("66630")&.number

  # The quick-select's atoms as rows of a scope.
  def atoms_of(atom_sql) = ->(scope, keys) { reconciliation.with_atoms(scope, atom_sql, keys) }

  def reconciliation
    @reconciliation ||= Fin::UnitBookingReconciliation.new
  end

  def table_state = wsjrdp_expandable_table_state(POLICY)

  # The bookings the filter -- pins, lifts and the user's part -- leaves, with
  # the resolved Unit-Budget columns the table's cells read.
  def filtered
    @filtered ||= table_state.filter.scope(DatevBooking.with_unit_budget)
  end

  def bookings
    @bookings ||= Wsjrdp::ExpandableTableRows.new(table_state,
      reconciliation.with_atom(filtered, Fin::UnitBookingReconciliation::OPEN_ATOM_SQL),
      sort: Fin::DatevBookingsColumns.sort_expressions,
      sum: :signed_base_amount, preload: Fin::DatevBookingsColumns::PRELOADS)
  end

  # The quick-select: the bookings the filter leaves by the account that keeps
  # them out of the Unit-Budget (or decides it).
  def atoms
    @atoms ||= reconciliation.open_atoms(filtered)
  end

  # Count and sum (cents) of the whole table and of each quick-select atom, for
  # the bar's figures of an all-pages selection (t.bulk_actions totals:).
  def bulk_totals(figure, atoms)
    cents = ->(sum) { (sum * 100).round }
    {"all" => [figure.count, cents.call(figure.sum)]}
      .merge(atoms.to_h { |atom| [atom.key, [atom.count, cents.call(atom.sum)]] })
  end

  def filtered_figure
    @filtered_figure ||= reconciliation.figure(filtered)
  end

  # Back to the page as it was: the URL-chosen params of the table.
  def redirect_back_to_list(**flash)
    redirect_to reconciliation_unit_bookings_path(table_state.wire_params), **flash
  end

  def authorize_action
    authorize!(:show, DatevBooking)
  end

  def authorize_write
    authorize!(:update, DatevBooking)
  end

  # The same gate for the views: whoever may not write gets neither the
  # checkboxes nor the bar; the table stays a reading view.
  def may_assign? = can?(:update, DatevBooking)
end
