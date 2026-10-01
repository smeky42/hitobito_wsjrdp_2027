# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The Abstimmung page "Unit-Buchungen" at /fin/reconciliation/unit_bookings
# (Fin::UnitBookingReconciliation): the figures over what the units see, the
# open bookings with a quick-select by the deciding account and the bulk
# assignment of a secondary cost center, and -- lazily loaded into a collapsed
# section -- the bookings that already carry one, with a quick-select by
# central cost center and the bulk removal of the secondary cost center. Both
# lists carry the bookings filter; the assigned one's lives inside its turbo
# frame, so its apply comes back to the frame. Renders under the Abstimmung
# sheet with its tabs (Sheet::Fin::UnitBooking).
class Fin::UnitBookingsController < Fin::FinController
  include Wsjrdp::TableStateful

  before_action :authorize_action
  # Assigning and clearing WRITE the bookings' secondary cost center, so they
  # need the write tier on top of the section's :show gate, like the booking's
  # own edit page.
  before_action :authorize_write, only: %i[assign clear]

  helper_method :reconciliation, :open_bookings, :assigned_bookings, :open_atoms, :assigned_atoms,
    :filtered_open_figure, :assigned_figure, :may_assign?

  # The page pins each list itself (Fin::UnitBookingReconciliation), so the
  # user's filter offers none of the attributes that pin it: either cost center
  # and the Unit-Budget on both lists, the secondary cost center -- always blank
  # -- on the open one. The cost center itself stays: narrowing to one unit is
  # what the filter is for.
  OPEN_PINNED_FILTER_ATTRIBUTES = %i[any_cost_center unit_budget secondary_cost_center].freeze
  ASSIGNED_PINNED_FILTER_ATTRIBUTES = %i[any_cost_center unit_budget].freeze

  # The open bookings ("ub"): the user's filter narrows the pinned set and stays
  # in the URL, so the page always shows what its link says. The Unit-Budget
  # column, "nein" on every row here, is offered rather than shown.
  OPEN_POLICY = wsjrdp_expandable_table_policy prefix: "ub",
    columns: Fin::DatevBookingsColumns.codec,
    sort: {hidden: [["booking_date", "desc"]]},
    cols: {default: %w[booking_date signed_base_amount posting_text cost_center_number account_number]},
    per_page: {default: 50},
    filter: {policy: :url, schema: Fin::DatevBookingsFilterSchema,
             exclude: OPEN_PINNED_FILTER_ATTRIBUTES},
    pane: {default: 0}

  # The assigned bookings ("ua"), in the lazily loaded section: own paging,
  # sorting and filter, all in the URL as well -- the page hands them to the
  # frame, and a bulk action carries them back to the page. The secondary cost
  # center stands right behind the primary one; the Unit-Budget column, "nein"
  # on every row here, is offered rather than shown.
  ASSIGNED_POLICY = wsjrdp_expandable_table_policy prefix: "ua",
    columns: Fin::DatevBookingsColumns.codec,
    sort: {hidden: [["booking_date", "desc"]]},
    cols: {default: %w[booking_date signed_base_amount posting_text cost_center_number
      secondary_cost_center_number account_number]},
    per_page: {default: 50},
    filter: {policy: :url, schema: Fin::DatevBookingsFilterSchema,
             exclude: ASSIGNED_PINNED_FILTER_ATTRIBUTES},
    pane: {default: 0}

  def index
  end

  # Apply target of the open table's filter builder (PRG), keeping the assigned
  # table's view.
  def apply
    wsjrdp_apply_table_filter(open_table_state,
      redirect_to: reconciliation_unit_bookings_path(assigned_table_state.wire_params))
  end

  # The assigned bookings, as the turbo frame the page's collapsed section
  # loads when it opens; a direct visit gets the frame inside the page.
  def assigned
    render layout: false if request.headers["Turbo-Frame"].present?
  end

  # Apply target of the assigned table's filter builder, which submits inside
  # the frame: the redirect renders the frame anew.
  def apply_assigned
    wsjrdp_apply_table_filter(assigned_table_state,
      redirect_to: assigned_reconciliation_unit_bookings_path)
  end

  # Sets ONE secondary cost center on the selected open bookings: the posted
  # booking_ids, or with select_all every open booking of the current filter
  # ("1") or those of the named atoms (a comma-separated list, the
  # quick-select). Ids outside the open set are ignored by the reconciliation.
  def assign
    ids = selected_ids(filtered_open, Fin::UnitBookingReconciliation::OPEN_ATOM_SQL)
    return redirect_back_to_list(alert: "Keine Buchungen ausgewählt.") if ids.empty?

    number = params[:secondary_cost_center_number].to_s
    count = reconciliation.assign!(ids, number)
    target = reconciliation.assignable_cost_centers.find { |cost_center| cost_center.number == number }
    label = Fin::UnitBookingReconciliation.label(target)
    redirect_back_to_list(notice: "#{count} Buchungen: sekundäre Kostenstelle #{label} gesetzt.")
  rescue ArgumentError => e
    redirect_back_to_list(alert: e.message)
  end

  # Takes the secondary cost center off the selected assigned bookings of the
  # current filter, the same way.
  def clear
    ids = selected_ids(assigned_scope, Fin::UnitBookingReconciliation::ASSIGNED_ATOM_SQL)
    return redirect_back_to_list(alert: "Keine Buchungen ausgewählt.") if ids.empty?

    count = reconciliation.clear!(ids)
    redirect_back_to_list(notice: "#{count} Buchungen: sekundäre Kostenstelle gelöscht.")
  end

  private

  def reconciliation
    @reconciliation ||= Fin::UnitBookingReconciliation.new
  end

  def open_table_state = wsjrdp_expandable_table_state(OPEN_POLICY)

  def assigned_table_state = wsjrdp_expandable_table_state(ASSIGNED_POLICY)

  # The open bookings the user's filter leaves, with the resolved Unit-Budget
  # columns the table's cells read.
  def filtered_open
    @filtered_open ||= open_table_state.filter.scope(reconciliation.open(DatevBooking.with_unit_budget))
  end

  # The assigned bookings the frame's filter leaves.
  def assigned_scope
    @assigned_scope ||= assigned_table_state.filter.scope(reconciliation.assigned(DatevBooking.with_unit_budget))
  end

  def open_bookings
    @open_bookings ||= rows(open_table_state,
      reconciliation.with_atom(filtered_open, Fin::UnitBookingReconciliation::OPEN_ATOM_SQL))
  end

  def assigned_bookings
    @assigned_bookings ||= rows(assigned_table_state,
      reconciliation.with_atom(assigned_scope, Fin::UnitBookingReconciliation::ASSIGNED_ATOM_SQL))
  end

  def rows(state, relation)
    Wsjrdp::ExpandableTableRows.new(state, relation,
      sort: Fin::DatevBookingsColumns.sort_expressions,
      sum: :signed_base_amount, preload: Fin::DatevBookingsColumns::PRELOADS)
  end

  # The quick-selects: the open bookings the filter leaves by deciding account,
  # the assigned ones the frame's filter leaves by central cost center.
  def open_atoms
    @open_atoms ||= reconciliation.open_atoms(filtered_open)
  end

  def assigned_atoms
    @assigned_atoms ||= reconciliation.assigned_atoms(assigned_scope)
  end

  def filtered_open_figure
    @filtered_open_figure ||= reconciliation.figure(filtered_open)
  end

  def assigned_figure
    @assigned_figure ||= reconciliation.figure(assigned_scope)
  end

  # The selection a bulk action posts: every row of the scope (select_all=1),
  # the rows of the named atoms (select_all=<atoms>), else the posted ids.
  def selected_ids(scope, atom_sql)
    spec = params[:select_all].to_s
    return scope.pluck(:id) if spec == "1"
    return reconciliation.with_atoms(scope, atom_sql, spec.split(",")).pluck(:id) if spec.present?

    Array(params[:booking_ids]).map(&:to_i)
  end

  # Back to the page as it was: the URL-chosen params of both tables.
  def redirect_back_to_list(**flash)
    carry = open_table_state.wire_params.merge(assigned_table_state.wire_params)
    redirect_to reconciliation_unit_bookings_path(carry), **flash
  end

  def authorize_action
    authorize!(:show, DatevBooking)
  end

  def authorize_write
    authorize!(:update, DatevBooking)
  end

  # The same gate for the views: whoever may not assign gets neither the
  # checkboxes nor the forms; the lists stay a reading view.
  def may_assign? = can?(:update, DatevBooking)
end
