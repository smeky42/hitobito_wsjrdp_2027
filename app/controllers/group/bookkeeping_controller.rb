# frozen_string_literal: true

#  Copyright (c) 2026, German Contingent for the Worldscoutjamboree 2027. This file is part of
#  hitobito_wsjrdp_2027 and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/hitobito/hitobito_wsjrdp_2027.

# The Buchhaltung sub-tab of a group's Finanzen tab. The action is :show, not
# :index: the core swaps an index action's sheet for its parent sheet, which
# would drop the sub-tabs (doc/navigation.md).
#
# Below the group's cost-center chips the page carries the group's DATEV
# bookings: the Buchungen table of /fin/bookkeeping/bookings, pinned to those
# cost centers and reduced to what a group needs. Three declarations carry that:
#
#   * ONE fixed filter slot over `any_cost_center` -- compiled into the relation
#     by state.filter.scope and shown as a locked chip, so no URL can remove or
#     widen it (doc/wsjrdp/expandable_table.md, D2e);
#   * `cols: {only: COLUMNS}` and `filter: {only: FILTERS}` -- the columns and
#     filter attributes this table HAS at all, so a hand-written ?gbc= / ?gbf=
#     cannot bring the finance team's columns (Sphäre, Primanota) or attributes
#     back;
#   * a `store_key` per group, so the remembered filter of one unit never shows
#     up on another's page.
#
# Everything here is gated on :show_finance on the GROUP, never on the finance
# models -- a unit leader reaches the page through their own unit and holds
# nothing in the Finanzen section (doc/roles.md -> "Finance on a group's page").
class Group::BookkeepingController < ApplicationController
  include Wsjrdp::TableStateful

  before_action :authorize_action
  prepend_before_action :group

  decorates :group

  helper_method :bookings, :booking_table_state, :group_cost_center_numbers,
    :bookkeeping_figures

  # The columns this table has, in the order the column menu offers them. The
  # rest of Fin::DatevBookingsColumns -- Leistungsdatum, Primanota Periode,
  # Sphäre -- answers questions the finance team asks on /fin, not a group.
  COLUMNS = %w[booking_date signed_base_amount unit_budget posting_text cost_center_number
    secondary_cost_center_number account_number offsetting_account_number
    document_field_1 document_field_2].freeze

  # What the table starts with; every one of them is in COLUMNS (the policy
  # refuses a default column the table does not have). Unit-Budget stands right
  # behind the amount: whether a booking counts against the unit's budget is the
  # first thing a unit reads off its own list, where /fin offers the column
  # without showing it by default.
  #
  # The Gegenkonto is NOT among them: on a group's list the Konto already names
  # the side that carries the money, and the second account number is
  # bookkeeping detail a unit reads in the booking's own detail if at all. It
  # stays in COLUMNS, so the column menu keeps offering it.
  DEFAULT_COLUMNS = %w[booking_date posting_text signed_base_amount unit_budget
    cost_center_number account_number].freeze

  # The filter attributes the picker offers. Left out: Leistungsdatum,
  # Geschäftsjahr, Sphäre, Buchungsstapel and Beitragsbuchung -- bookkeeping
  # internals that say nothing on a group's page.
  FILTERS = %i[text_any text text_document cost_center secondary_cost_center
    any_cost_center unit_budget amount amount_abs amount_original amount_original_abs
    transaction_currency booking_date konto offsetting_account any_account].freeze

  # The "Schnellauswahl" above the filter: one click narrows the list to the
  # bookings that count against the unit's own budget
  # (doc/wsjrdp/expandable_table.md, "Presets"). It is a shortcut into the USER
  # part -- `unit_budget` is one of FILTERS, so the slot the toggle adds becomes
  # an ordinary chip the builder can edit or drop afterwards. The question a
  # unit asks of its list most often, and the answer is the resolved one
  # (doc/fin/unit_budget.md), like the column beside it.
  PRESETS = [
    {key: "unit_budget", label: "Unit-Budget",
     slots: [[["unit_budget", "in", "true"]]]}
  ].freeze

  BOOKINGS_POLICY = wsjrdp_expandable_table_policy prefix: "gb",
    columns: Fin::DatevBookingsColumns.codec,
    cols: {only: COLUMNS, default: -> { default_booking_columns },
           labels: {"booking_date" => "Buchungsdatum"}},
    sort: {default: [["booking_date", "desc"]]},
    per_page: {default: 50},
    filter: {policy: :remember, schema: Fin::DatevBookingsFilterSchema, only: FILTERS,
             presets: PRESETS,
             fixed: [{slots: -> { group_cost_center_slots }, show: :readonly}]},
    pane: {default: 0},
    store_key: -> { "group/bookkeeping:#{params[:group_id]}" }

  # The resolved state of this page's bookings table.
  def booking_table_state
    wsjrdp_expandable_table_state(BOOKINGS_POLICY)
  end

  # The three figures above the table: what the group's bookings add up to, the
  # Unit-Budget part of that and the share of the unit's budget it uses. They
  # read the PINNED set, not the filtered one -- the summary line inside the
  # table states the filtered figures (Fin::GroupBookkeepingFigures).
  def bookkeeping_figures
    @bookkeeping_figures ||= Fin::GroupBookkeepingFigures.new(group_cost_center_numbers)
  end

  # The listing itself, exactly as on /fin/bookkeeping/bookings: the filtered
  # relation handed to Wsjrdp::ExpandableTableRows, which does sorting,
  # pagination and the sum. The group's scope is IN the filter (the fixed slot),
  # so there is no second, hand-written narrowing here that could drift from
  # what the locked chip says.
  def bookings
    @bookings ||= Wsjrdp::ExpandableTableRows.new(booking_table_state,
      booking_table_state.filter.scope(DatevBooking.with_unit_budget),
      sort: Fin::DatevBookingsColumns.sort_expressions,
      sum: :signed_base_amount, preload: Fin::DatevBookingsColumns::PRELOADS)
  end

  def show
    bookings if group_cost_center_numbers.any?
    render :show
  end

  # Apply target of the filter builder (PRG, generic implementation in
  # Wsjrdp::TableStateful). Filtering is reading, so the page's own gate is all
  # it takes.
  def apply
    wsjrdp_apply_table_filter(booking_table_state,
      redirect_to: group_finance_bookkeeping_path(group))
  end

  private

  # The cost centers of the group as bare numbers: the pin of the table, and the
  # reason there is a table at all. Empty without a group -- the policies smoke
  # spec resolves every declaration on a request-less controller instance.
  def group_cost_center_numbers
    Array(@group&.cost_center_numbers).compact_blank
  end

  # DEFAULT_COLUMNS, minus the Kostenstelle where the group has exactly ONE of
  # them: the locked chip above the table already names it and every row would
  # repeat it. With two or more the column says which one a booking belongs to
  # and stays. It remains in COLUMNS either way, so the column menu offers it
  # back.
  #
  # A lambda, because the answer depends on the group the request loaded
  # (Wsjrdp::TableStatePolicy#evaluate runs it on the controller). Without a
  # group -- the policies smoke spec -- the list is empty and the full set
  # stands.
  def default_booking_columns
    return DEFAULT_COLUMNS if group_cost_center_numbers.size != 1

    DEFAULT_COLUMNS - %w[cost_center_number]
  end

  # The ONE fixed slot: every booking whose primary OR secondary cost center is
  # one of the group's (Fin::DatevBookingsFilterSchema's `any_cost_center`). One
  # slot with one condition -- slots are ANDed, the values inside one condition
  # ORed.
  #
  # Without cost centers it is empty, and the page shows its empty text instead
  # of a table: an unpinned table would list every booking of the contingent.
  def group_cost_center_slots
    numbers = group_cost_center_numbers
    return [] if numbers.empty?

    [[["any_cost_center", "in", *numbers]]]
  end

  def authorize_action
    authorize!(:show_finance, group)
  end

  def group
    @group ||= Group.find(params[:group_id])
  end
end
