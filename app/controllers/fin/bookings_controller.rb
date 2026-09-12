# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Buchungen" tab: a filterable, sortable, paged list of all DATEV bookings.
#
# Filtering uses the generic CNF filter builder (doc/wsjrdp/generic_filter_builder.md):
# the ?f= param carries the whole filter as Rison (short keys); the builder
# UI POSTs to #apply, which encodes and redirects (PRG). The filtered relation
# is then handed to Wsjrdp::ExpandableTableRows, which does the rest: sorting,
# pagination and the sum.
#
# The whole table state -- sort, columns, page size, page, the filter, the open
# rows and the filter pane -- is declared once below and resolved by
# Wsjrdp::TableStateful (doc/plans/2026-09_expandable-table-state.md). This page
# REMEMBERS its state in the session (that is what `policy: :remember` on the
# filter and the D6 defaults for the rest mean), so coming back through the tab
# lands on the last view; "Zurücksetzen" (?f=) clears the remembered filter and
# nothing else (the wholesale ?r=1 reset has no button in the UI).
class Fin::BookingsController < Fin::FinController
  include WsjrdpNumberHelper
  include Wsjrdp::TableStateful

  before_action :authorize_action
  # Note: #query_entries only feeds autocomplete in editing mode, so
  # it also requires writing authorization.
  before_action :authorize_write, only: %i[query_entries update]

  helper_method :bookings

  # Attributes hidden on this page (they stay in the schema; other hosts may
  # expose them -- accounting_entry is used by the reconciliation pages).
  # Conditions on them in a URL are simply dropped.
  EXCLUDED_FILTER_ATTRIBUTES = %i[sphere accounting_entry].freeze

  BOOKINGS_POLICY = wsjrdp_expandable_table_policy prefix: "",
    columns: Fin::DatevBookingsColumns.codec,
    sort: {default: [["booking_date", "desc"]]},
    cols: {default: Fin::DatevBookingsColumns.default_keys},
    per_page: {default: 50},
    filter: {policy: :remember, schema: Fin::DatevBookingsFilterSchema,
             exclude: EXCLUDED_FILTER_ATTRIBUTES},
    pane: {default: 1}

  # The resolved state of this page's bookings table.
  def booking_table_state
    wsjrdp_expandable_table_state(BOOKINGS_POLICY)
  end

  # The listing itself: the filtered relation handed to
  # Wsjrdp::ExpandableTableRows, which does sorting, pagination and the sum. The
  # way from the state to the relation is state.filter.scope -- nothing here
  # decodes, validates, compiles or joins by hand (the batch join the
  # batch-backed attributes and the Primanota-Periode sort need comes from the
  # schema's own base relation, see Wsjrdp::Filtering::FilterSchema#compile).
  def bookings
    @bookings ||= Wsjrdp::ExpandableTableRows.new(booking_table_state,
      booking_table_state.filter.scope(DatevBooking.all),
      sort: Fin::DatevBookingsColumns.sort_expressions,
      sum: :signed_base_amount, preload: Fin::DatevBookingsColumns::PRELOADS)
  end

  def index
    bookings
  end

  # Apply target of the filter builder (PRG, generic implementation in
  # Wsjrdp::TableStateful). The page resets to 1.
  def apply
    wsjrdp_apply_table_filter(booking_table_state, redirect_to: bookings_path)
  end

  def show
    @booking = DatevBooking.find(params[:id])
    @ctx = if turbo_frame_request?
      Fin::AttrFormatContext.embedded(
        Wsjrdp::TableContext.new(level: booking_table_state.level, lazy: true)
      )
    else
      Fin::AttrFormatContext.regular
    end
    render layout: false if turbo_frame_request?
  end

  # --- manual associations (booking detail view, all hosts) ------------------

  # JSON source of the entry autocomplete: unlinked Beitragsbuchungen whose
  # amount_cents EXACTLY equals the booking's signed fee-side amount, filtered
  # by the typed query. A purely NUMERIC query is treated as an accounting-entry
  # id search (id-prefix, the exact id first) so typing "5678" autocompletes
  # straight to Beitragsbuchung #5678; any other query searches id / person /
  # description as a substring.
  def query_entries
    booking = DatevBooking.find(params[:id])
    scope = AccountingEntry.where.missing(:datev_booking)
      .where(amount_cents: Fin::DatevBookingMatcher.signed_cents(booking))
      .where.not(amount_cents: 0)
      .where(subject_type: "Person")
    q = params[:q].to_s.strip
    entries =
      if q.match?(/\A\d+\z/)
        scope.where("CAST(accounting_entries.id AS TEXT) LIKE ?", "#{q}%")
          .includes(:subject)
          .order(Arel.sql("CASE WHEN accounting_entries.id = #{q.to_i} THEN 0 ELSE 1 END"))
          .order(id: :asc).limit(15)
      else
        if q.present?
          like = "%#{ActiveRecord::Base.sanitize_sql_like(q)}%"
          scope = scope.joins("LEFT JOIN people ON people.id = accounting_entries.subject_id")
            .where("CAST(accounting_entries.id AS TEXT) LIKE :q " \
                   "OR accounting_entries.description ILIKE :q " \
                   "OR people.first_name ILIKE :q OR people.last_name ILIKE :q", q: like)
        end
        scope.includes(:subject).order(value_date: :desc, id: :desc).limit(15)
      end
    render json: entries.map { |e| {id: e.id, label: entry_autocomplete_label(e)} }
  end

  # ONE RESTful endpoint for all manual associations (PATCH booking_path):
  # every mini-form of the detail view posts a field subset of datev_booking --
  # like a page-wide form with several submit buttons, each sending only its
  # part. Which key arrives decides the transition; the flash comes from the
  # transition. New actions need only a new permitted key + branch, no route.
  #
  #   datev_booking[accounting_entry_id] set = connect / "" = unlink
  #
  # A booking has no own person any more -- its person is the linked entry's
  # subject -- so there is no person mini-form.
  def update
    booking = DatevBooking.find(params[:id])
    attrs = params.require(:datev_booking).permit(:accounting_entry_id,
      :secondary_cost_center_number, :is_unit_budget, :sub_cost_center_number)
    editable_keys = attrs.keys & %w[secondary_cost_center_number is_unit_budget sub_cost_center_number]
    if editable_keys.any?
      # The field edits are the manage tier's -- the same gate the detail view
      # asks before it builds the form at all (fin/bookings/_detail).
      authorize!(:fin_admin, booking)
      update_fields(booking, attrs.slice(*editable_keys))
    elsif attrs.key?(:accounting_entry_id)
      update_entry_link(booking, attrs[:accounting_entry_id])
    else
      redirect_after_update booking, alert: "Keine Änderung übermittelt."
    end
  end

  private

  # Where a mini-form of the detail view goes after its update.
  #
  # Inside a turbo frame the answer has to RE-RENDER THE FRAME that submitted --
  # #show does exactly that -- so a frame request goes to the booking's own path.
  # `redirect_back` would land on the HOST page (the Kostenstellen list, a
  # Sachkonto detail, ...), and that page carries no frame of this row: Turbo then
  # renders "Content missing", or, on the Buchungen list, replaces the row with
  # the still-unloaded "Wird geladen ..." placeholder. Outside a frame the form
  # runs with data-turbo=false and `redirect_back` is right -- it keeps the user
  # on the list they came from.
  #
  # The flash is only seen on the non-frame path: a frame response renders
  # turbo-rails' minimal layout, which has no flash slot.
  def redirect_after_update(booking, **flash_args)
    if turbo_frame_request?
      redirect_to booking_path(booking), **flash_args
    else
      redirect_back fallback_location: booking_path(booking), **flash_args
    end
  end

  def turbo_frame_request? = request.headers["Turbo-Frame"].present?

  def update_fields(booking, attrs)
    coerce_nullable_boolean!(attrs, :is_unit_budget)
    blank_to_nil!(attrs, :secondary_cost_center_number)
    blank_to_nil!(attrs, :sub_cost_center_number)
    if booking.update(attrs)
      redirect_after_update booking,
        notice: "Buchung ##{booking.id} aktualisiert."
    else
      redirect_after_update booking,
        alert: "Fehler: #{booking.errors.full_messages.join(", ")}"
    end
  end

  # Connect ONE explicitly chosen Beitragsbuchung (guards + provenance + camt
  # mirror via the matcher); blank = unlink.
  def update_entry_link(booking, raw_id)
    return disconnect_entry(booking) if raw_id.blank?

    entry = AccountingEntry.find_by(id: raw_id)
    if entry.nil?
      redirect_after_update booking,
        alert: "Keine Beitragsbuchung ausgewählt."
    elsif Fin::DatevBookingMatcher.connect_pair!(booking, entry, linked_by_id: current_user&.id)
      redirect_after_update booking,
        notice: "Buchung ##{booking.id} mit Beitragsbuchung ##{entry.id} verknüpft."
    else
      redirect_after_update booking,
        alert: "Verknüpfung nicht möglich (Buchung oder Beitragsbuchung bereits verknüpft)."
    end
  end

  # Remove the accounting-entry link. The link + provenance live on the entry
  # now, and the bank transaction on the camt side -- clear all three. Confirmed
  # in the UI before submit.
  def disconnect_entry(booking)
    entry = booking.accounting_entry
    if entry
      camt_id = entry.camt_transaction_id
      entry.update_columns(datev_booking_id: nil, datev_booking_link_meta: {},
        updated_at: Time.zone.now)
      if camt_id
        WsjrdpCamtTransaction.where(id: camt_id, datev_booking_id: booking.id)
          .update_all(datev_booking_id: nil, updated_at: Time.zone.now)
      end
    end
    redirect_after_update booking,
      notice: entry ?
        "Verknüpfung von Buchung ##{booking.id} mit Beitragsbuchung ##{entry.id} entfernt." :
        "Buchung ##{booking.id} war nicht verknüpft."
  end

  # One line per autocomplete suggestion. The amount is omitted on purpose --
  # every suggestion carries exactly the booking's amount anyway.
  def entry_autocomplete_label(entry)
    date = entry.value_date || entry.booking_date
    person = entry.subject.is_a?(Person) ?
      "#{entry.subject.first_name} #{entry.subject.last_name}" : nil
    ["##{entry.id}", date&.strftime("%d.%m.%Y"), person,
      entry.description.to_s.truncate(60)].compact.join(" · ")
  end

  def blank_to_nil!(attrs, key)
    k = key.to_s
    attrs[k] = nil if attrs.key?(k) && attrs[k].blank?
  end

  def coerce_nullable_boolean!(attrs, key)
    return unless attrs.key?(key.to_s)
    attrs[key.to_s] = case attrs[key.to_s]
    when "true", true then true
    when "false", false then false
    end
  end

  def authorize_action
    authorize!(:show, DatevBooking)
  end

  def authorize_write
    authorize!(:update, DatevBooking)
  end
end
