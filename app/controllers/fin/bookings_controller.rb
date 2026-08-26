# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Buchungen" tab: a filterable, sortable, paged list of all DATEV bookings.
#
# Filtering uses the generic CNF filter builder (doc/generic_filter_builder.md):
# the ?filter= param carries the whole filter as Rison (short keys); the builder
# UI POSTs to #apply, which encodes and redirects (PRG). The filtered relation
# is then handed to DatevBookingsQuery, which keeps doing what it always did --
# sorting, pagination, column selection and the sum -- with its own per-field
# filters disabled (hidden_booking_filters below).
class Fin::BookingsController < Fin::FinController
  include WsjrdpNumberHelper
  include Fin::BookingsFiltering

  before_action :authorize_action

  SESSION_KEY = "datev_bookings_query"

  def index
    return if handle_clear
    return if restore_remembered_filter
    return if redirect_to_compact_url

    session[SESSION_KEY] = request.query_string.presence
    query
  end

  # Apply target of the filter builder (PRG, shared implementation in
  # Fin::BookingsFiltering). The page resets to 1.
  def apply
    apply_filter_and_redirect(bookings_path)
  end

  def show
    @booking = DatevBooking.find(params[:id])
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
      .where(amount_cents: DatevBookingMatcher.signed_cents(booking))
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
  #   datev_booking[person_id]           set / "" = clear the person link
  #   datev_booking[accounting_entry_id] set = connect / "" = unlink
  def update
    booking = DatevBooking.find(params[:id])
    attrs = params.require(:datev_booking).permit(:person_id, :accounting_entry_id)
    if attrs.key?(:accounting_entry_id)
      update_entry_link(booking, attrs[:accounting_entry_id])
    elsif attrs.key?(:person_id)
      update_person_link(booking, attrs[:person_id])
    else
      redirect_back fallback_location: booking_path(booking), alert: "Keine Änderung übermittelt."
    end
  end

  private

  # Manually link a person (feeds the matcher's person-already-linked rule);
  # blank clears the link.
  def update_person_link(booking, raw_id)
    person_id = raw_id.presence
    person = Person.find_by(id: person_id) if person_id
    if person_id && person.nil?
      redirect_back fallback_location: booking_path(booking),
        alert: "Person ##{person_id} nicht gefunden."
    else
      booking.update_columns(person_id: person&.id, updated_at: Time.zone.now)
      redirect_back fallback_location: booking_path(booking), notice: person ?
        "Buchung ##{booking.id} mit #{person.first_name} #{person.last_name} verknüpft." :
        "Personen-Verknüpfung von Buchung ##{booking.id} entfernt."
    end
  end

  # Connect ONE explicitly chosen Beitragsbuchung (guards + provenance + camt
  # mirror via the matcher); blank = unlink.
  def update_entry_link(booking, raw_id)
    return disconnect_entry(booking) if raw_id.blank?

    entry = AccountingEntry.find_by(id: raw_id)
    if entry.nil?
      redirect_back fallback_location: booking_path(booking),
        alert: "Keine Beitragsbuchung ausgewählt."
    elsif DatevBookingMatcher.connect_pair!(booking, entry, linked_by_id: current_user&.id)
      redirect_back fallback_location: booking_path(booking),
        notice: "Buchung ##{booking.id} mit Beitragsbuchung ##{entry.id} verknüpft."
    else
      redirect_back fallback_location: booking_path(booking),
        alert: "Verknüpfung nicht möglich (Buchung oder Beitragsbuchung bereits verknüpft)."
    end
  end

  # Remove the accounting-entry link: clears accounting_entry_id, the mirrored
  # camt_transaction_id and the link provenance columns. The person association
  # (person_id) is left untouched -- it may have been set on purpose. Confirmed
  # in the UI before submit.
  def disconnect_entry(booking)
    entry_id = booking.accounting_entry_id
    booking.update_columns(accounting_entry_id: nil, camt_transaction_id: nil,
      accounting_entry_link_type: nil, accounting_entry_linked_at: nil,
      accounting_entry_link_person_id: nil, updated_at: Time.zone.now)
    redirect_back fallback_location: booking_path(booking),
      notice: entry_id ?
        "Verknüpfung von Buchung ##{booking.id} mit Beitragsbuchung ##{entry_id} entfernt." :
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

  # --- generic CNF filter (doc/generic_filter_builder.md) --------------------

  # Attributes hidden on this page (they stay in the schema; other hosts may
  # expose them -- accounting_entry is used by the reconciliation pages).
  # Conditions on them in a URL are simply dropped.
  EXCLUDED_FILTER_ATTRIBUTES = %i[sphere period accounting_entry].freeze

  def filter_excluded_attributes
    EXCLUDED_FILTER_ATTRIBUTES
  end

  def authorize_action
    authorize!(:fin_admin, DatevBooking)
  end

  # "Zurücksetzen" also forgets the session-remembered filter, then falls back to
  # the shared clear handling (reload without the clear marker).
  def handle_clear
    session.delete(SESSION_KEY) if params.key?(:clear)
    super
  end

  # Returning to /fin/bookings without params (e.g. via the tab, or from
  # elsewhere in hitobito) restores the last filter/sort/columns of this session.
  def restore_remembered_filter
    return false if request.query_parameters.present?

    remembered = session[SESSION_KEY]
    return false if remembered.blank?

    redirect_to("#{bookings_path}?#{remembered}")
    true
  end

  # Redirect to the same page without any blank query parameters, keeping the
  # visible URL (and the generated sort / pagination links) free of empty params.
  def redirect_to_compact_url
    original = request.query_parameters.to_h
    compact = compact_params(original)
    return false if compact == original

    # Remember the *compacted* query, so restoring it later (and dropping cols
    # back to the default) is not overridden by a stale remembered selection.
    session[SESSION_KEY] = compact.to_query.presence
    redirect_to bookings_path(compact)
    true
  end

  def compact_params(query_parameters)
    result = query_parameters.each_with_object({}) do |(key, value), acc|
      value = value.reject { |v| v.to_s.strip.blank? } if value.is_a?(Array)
      blank = value.is_a?(Array) ? value.empty? : value.to_s.strip.blank?
      acc[key] = value unless blank
    end
    compact_cols_param(result)
  end

  # Encode columns concisely (single comma-separated `cols` of short
  # abbreviations, hidden ones marked with "~") and keep them out of the URL
  # entirely when the full order + shown/hidden state matches the default.
  def compact_cols_param(result)
    return result unless result.key?("cols")

    states = DatevBookingsQuery.decode_column_states(result["cols"])
    seen = states.map(&:first).to_set
    all = WsjrdpBookingsHelper::ALL_BOOKING_COLUMNS
    states += all.reject { |c| seen.include?(c.key) }.map { |c| [c.key, false] }
    default = all.map { |c| [c.key, WsjrdpBookingsHelper::DEFAULT_BOOKING_COLUMN_KEYS.include?(c.key)] }
    if states.empty? || states == default
      result.delete("cols")
    else
      result["cols"] = DatevBookingsQuery.encode_column_states(states)
    end
    result
  end
end
