# frozen_string_literal: true

#  Copyright (c) 2026, German Contingent for the Worldscoutjamboree 2027. This file is part of
#  hitobito_wsjrdp_2027 and licensed under the Affero General Public License version 3
#  or later. See the COPYING file at the top-level directory or at
#  https://github.com/hitobito/hitobito_wsjrdp_2027.

# ONE booking of a group, under the group's own route
# (/groups/:group_id/finance/bookkeeping/bookings/:id): the page a row of the
# Buchhaltung tab's table links to, and the pane that table lazy-loads into an
# open row. Both come from the central detail partial (fin/bookings/_detail) --
# this controller only says WHICH fields it shows and which of them a group may
# edit.
#
# THE SCOPE CHECK is the point of the route: the booking is looked up only among
# the bookings of the group's cost centers, so a booking id from elsewhere
# answers 404 instead of opening the contingent's bookkeeping through a group a
# unit leader happens to lead. A group without cost centers finds nothing at all.
class Group::BookingsController < ApplicationController
  include Wsjrdp::TableStateful
  include Fin::BookingDetailHost

  before_action :authorize_action
  prepend_before_action :group

  decorates :group

  # The fields of the detail, in the order fin/bookings/_detail declares them.
  # Left out: Leistungsdatum, Sphäre, the Buchungs-GUID, the raw DATEV block,
  # the Verknüpfungen block (it leads into /fin and to a participant's fee data)
  # and the internal `comment`.
  # The original amount carries its own currency, so there is no currency field
  # of its own; the Wechselkurs stands with it and, like it, only on a
  # foreign-currency booking.
  # The sub cost center stays off the group's pages altogether -- the list, the
  # pane and both pages -- it is the finance team's breakdown on /fin.
  FIELDS = %w[booking_date posting_text base_amount transaction_amount exchange_rate
    account_number offsetting_account_number
    cost_center_number secondary_cost_center_number is_unit_budget
    user_comment document_field_1 document_field_2].freeze

  # What :update_finance on the group may change here: the group's own note on
  # a booking. `is_unit_budget`, `secondary_cost_center_number` and
  # `sub_cost_center_number` move money between (sub) cost centers and stay
  # with the finance team (/fin), whatever a group may do to its own bookings.
  EDITABLE_FIELDS = %w[user_comment].freeze

  # This controller answers the lazy detail panes of the Buchhaltung page's
  # table, so the detail needs that table's NESTING LEVEL -- and nothing else of
  # its state (Fin::BookingDetailHost#booking_detail_context). `level` is the one
  # field whose param is not namespaced by the prefix
  # (Wsjrdp::TableStatePolicy::SHARED_PARAMS): the embedding table writes
  # ?expandable_table_level=N into the frame URL and every policy reads the same
  # value back. So the declaration carries the prefix of the table it serves and
  # nothing more -- repeating the columns, the pinned slot and the store key of
  # Group::BookkeepingController would be a second copy of a declaration this
  # page never reads.
  BOOKINGS_POLICY = wsjrdp_expandable_table_policy prefix: "gb"

  def show
    booking
    show_booking_detail(booking_table_state)
  end

  # The EDIT PAGE of one booking of the group; #show is the reading page it is
  # reached from and comes back to. Same scope check, and :update_finance on top
  # of the page's own :show_finance (#authorize_action).
  def edit
    booking
    @ctx = Fin::AttrFormatContext.regular
  end

  # The mini-forms of the detail post a field subset of datev_booking, like
  # Fin::BookingsController#update -- but a group may only edit EDITABLE_FIELDS,
  # and anything else in the payload is refused as a whole rather than silently
  # dropped by #permit: a form that submits a field this page does not offer is
  # a bug or an attempt, and in neither case should the rest be written as if
  # nothing had happened.
  def update
    booking # the scope check first: an id from outside the group is a 404, not a form error
    submitted = params.require(:datev_booking)
    allowed = allowed_update_fields
    foreign = submitted.keys.map(&:to_s) - allowed
    return refuse_foreign_fields(foreign) if foreign.any?

    update_fields(submitted.permit(*allowed).to_h)
  end

  def booking_table_state
    wsjrdp_expandable_table_state(BOOKINGS_POLICY)
  end

  private

  # THE scope check: only the bookings of the group's own cost centers exist on
  # this route, on either cost-center column -- the same set the table's fixed
  # filter slot pins. `find` therefore raises ActiveRecord::RecordNotFound for
  # every other booking, and for every booking at all when the group has no cost
  # centers.
  def booking
    @booking ||= group_bookings.find(params[:id])
  end

  def group_bookings
    numbers = Array(group.cost_center_numbers).compact_blank
    DatevBooking.where(cost_center_number: numbers)
      .or(DatevBooking.where(secondary_cost_center_number: numbers))
  end

  # Where THIS host keeps one booking, reading and editing
  # (Fin::BookingDetailHost).
  def booking_detail_path(booking) = group_finance_bookkeeping_booking_path(group, booking)

  def booking_edit_path(booking) = group_edit_finance_bookkeeping_booking_path(group, booking)

  # EDITABLE_FIELDS, plus the edit page's extra key -- a NEW sub cost center is
  # something this page may send only where it may set the sub cost center at
  # all, so the extra key follows that field in and out of the list.
  def allowed_update_fields
    return EDITABLE_FIELDS unless EDITABLE_FIELDS.include?("sub_cost_center_number")

    EDITABLE_FIELDS + [Fin::BookingDetailHost::NEW_SUB_COST_CENTER_FIELD]
  end

  def update_fields(attrs)
    attrs = resolve_new_sub_cost_center(booking, attrs)
    return redirect_after_update(booking, alert: NO_COST_CENTER_ALERT) if attrs.nil?

    # "nicht gesetzt" of the select posts the empty string; the column holds
    # NULL for a booking without a sub cost center, never "". The comment column
    # is NOT NULL with "" as its default, so a cleared comment stays "".
    attrs["sub_cost_center_number"] = nil if attrs["sub_cost_center_number"].blank?
    if booking.update(attrs)
      redirect_after_update booking, notice: "Buchung ##{booking.id} aktualisiert."
    else
      redirect_after_update booking, alert: "Fehler: #{booking.errors.full_messages.join(", ")}"
    end
  end

  def refuse_foreign_fields(foreign)
    redirect_after_update booking,
      alert: "#{foreign.sort.join(", ")} kann auf dieser Seite nicht geändert werden, " \
             "es wurde nichts gespeichert."
  end

  # Reading is the page's own gate; writing needs :update_finance on top of it --
  # the edit PAGE as much as the update itself, so the audit tier is turned away
  # at the page rather than at the save. Both are actions on the GROUP -- a unit
  # leader holds nothing on DatevBooking.
  def authorize_action
    authorize!(:show_finance, group)
    authorize!(:update_finance, group) if %w[edit update].include?(action_name)
  end

  def group
    @group ||= Group.find(params[:group_id])
  end
end
