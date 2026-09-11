# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Abstimmung" (reconciliation) section: matching accounting entries with
# DATEV bookings. See doc/fin/bookkeeping_schema_review.md §3c for the verified
# matching strategy; the actual matcher lands in a later step.
class Fin::ReconciliationController < Fin::FinController
  include Wsjrdp::TableStateful

  before_action :authorize_action

  helper_method :bookings, :entries, :matched_entries_count,
    :total_entries_count,
    :collection_entries_count, :match_proposals, :match_alternatives,
    :unmatched_entries_by_month,
    :excluded_entries_count, :unmatched_entries_count, :unmatched_entries_sum,
    :entry_match_proposals, :entry_match_alternatives,
    :proposal_atom_stats, :proposal_atom

  # The TN-Beiträge listing is pinned by three LOCKED conditions (shown as
  # read-only slots in the filter, enforced via the pinned scope): no linked
  # Beitragsbuchung yet, cost center 8010/9500/9510 OR no cost center at all
  # (bank-side fee bookings may carry none; 8010 = Rückzahlung Abmeldung),
  # and the (mapped) fee account 41030 on either side.
  LOCKED_FILTER_TREE = [
    [["accounting_entry", "blank"]],
    [["cost_center", "in", "8010", "9500", "9510"], ["cost_center", "blank"]],
    [["konto", "in", "41030"], ["offsetting_account", "in", "41030"]]
  ].freeze

  # Locked on this page: the scope is pinned, so further filtering by cost
  # center, (offsetting) account or the Beitragsbuchung link is disabled.
  EXCLUDED_FILTER_ATTRIBUTES = %i[
    sphere cost_center secondary_cost_center konto offsetting_account
    any_account accounting_entry
  ].freeze

  # This page hosts TWO independent tables: the DATEV bookings ("bk", the
  # reusable listing of fin/bookings/_browser) and the unmatched
  # Beitragsbuchungen ("ae"). Both are declared here; the resolved states drive
  # the queries, the widget and the links
  # (doc/plans/2026-09_expandable-table-state.md).
  #
  # The bookings table: its filter is pinned by LOCKED_FILTER_TREE, shown as
  # read-only slots and compiled into the scope -- and it stays a URL-only
  # filter, so the page always shows what its link says.
  BOOKINGS_POLICY = wsjrdp_expandable_table_policy prefix: "bk",
    columns: Fin::DatevBookingsColumns.codec,
    sort: {default: [["booking_date", "desc"]]},
    # Fewer default columns than the main bookings list: Kostenstelle, Konto and
    # Gegenkonto are pinned by the fixed filter anyway, and the injected proposal
    # column needs the room. (The column picker still offers every column.)
    cols: {default: Fin::DatevBookingsColumns.default_keys -
      %w[cost_center_number account_number offsetting_account_number]},
    per_page: {default: 50},
    filter: {policy: :url,
             schema: Fin::DatevBookingsFilterSchema,
             fixed: [{slots: LOCKED_FILTER_TREE, show: :readonly}],
             exclude: EXCLUDED_FILTER_ATTRIBUTES},
    pane: {default: 0}

  # The entries table: own prefix, own sort/paging, no filter. Deliberately NO
  # sort default: this table's natural order is "proposals first"
  # (order_proposals_first), which no column sort can express -- and declaring a
  # date default would put a "Datum ↓" arrow on a header the table is not
  # actually ordered by.
  ENTRIES_POLICY = wsjrdp_expandable_table_policy prefix: "ae",
    columns: Fin::AccountingEntriesColumns.codec,
    cols: {default: Fin::AccountingEntriesColumns.default_keys},
    per_page: {default: 50, max: 500}

  # The resolved state of the bookings table (the entries one is
  # #entries_table_state).
  def booking_table_state
    wsjrdp_expandable_table_state(BOOKINGS_POLICY)
  end

  # The bookings listing of this page: the pinned page scope (this page shows
  # every DATEV booking, the narrowing is entirely in the policy's fixed slots)
  # filtered through the state and handed to Wsjrdp::ExpandableTableRows for
  # sorting, pagination and the sum.
  def bookings
    @bookings ||= Wsjrdp::ExpandableTableRows.new(booking_table_state, filtered_scope,
      sort: Fin::DatevBookingsColumns.sort_expressions,
      sum: :signed_base_amount, preload: Fin::DatevBookingsColumns::PRELOADS)
  end

  # The unmatched entries themselves (bottom table). Its own state ("ae"), so
  # its paging, sorting and open rows never collide with the bookings table's.
  # With NOTHING sorted the natural order is "proposals first"
  # (#order_proposals_first), which no column sort can express.
  def entries
    @entries ||= Wsjrdp::ExpandableTableRows.new(entries_table_state,
      unmatched_entries_relation,
      sort: Fin::AccountingEntriesColumns.sort_expressions,
      preload: :subject,
      tiebreaker: "accounting_entries.id DESC",
      natural_order: method(:order_proposals_first))
  end

  # Übersicht at /reconciliation -- still empty.
  def overview
  end

  # TN-Beiträge (participant fees) at /reconciliation/participant_fees: the
  # match counts plus the list of not-yet-matched fee bookings (locked
  # conditions above; user filter on top).
  def participant_fees
    bookings
  end

  def apply_participant_fees
    wsjrdp_apply_table_filter(booking_table_state,
      redirect_to: reconciliation_participant_fees_path)
  end

  # Connect proposed matches (Fin::DatevBookingMatcher) to their Beitragsbuchung:
  # sets the entry's datev_booking_id + provenance and mirrors the camt link (from
  # the entry) in one bulk statement. mode=all connects every proposal of the
  # current filter scope; otherwise only the posted booking_ids (the page
  # button and the per-row checkboxes both send ids).
  def connect_participant_fees
    only_ids = connect_only_ids(match_proposals, :booking_ids)
    connected = Fin::DatevBookingMatcher.connect!(match_proposals, only_ids: only_ids,
      linked_by_id: current_user&.id)
    redirect_back_to_list(notice: "#{connected} Buchungen mit ihrer Beitragsbuchung verknüpft.")
  end

  # Connect ONE booking to ONE explicitly chosen entry (alternatives list in
  # the detail view).
  def connect_single
    booking = DatevBooking.find(params[:booking_id])
    entry = AccountingEntry.find(params[:entry_id])
    if Fin::DatevBookingMatcher.connect_pair!(booking, entry, linked_by_id: current_user&.id)
      redirect_back_to_list(notice: "Buchung ##{booking.id} mit Beitragsbuchung ##{entry.id} verknüpft.")
    else
      redirect_back_to_list(alert: "Verknüpfung nicht möglich (Buchung oder Beitragsbuchung bereits verknüpft).")
    end
  end

  # REVERSE bulk connect: connect selected accounting entries to their proposed
  # DATEV booking (mirror of connect_participant_fees on the entries table).
  def connect_participant_entries
    only_ids = connect_only_ids(entry_match_proposals, :entry_ids)
    connected = Fin::DatevBookingMatcher.connect_reverse!(entry_match_proposals, only_ids: only_ids,
      linked_by_id: current_user&.id)
    redirect_back_to_list(notice: "#{connected} Beitragsbuchungen mit ihrer DATEV-Buchung verknüpft.")
  end

  # DEVELOPMENT ONLY -- wipe every booking<->entry link (the entry's
  # datev_booking_id + provenance and the camt side's datev_booking_id) so the
  # whole reconciliation can be replayed from scratch while testing the matcher.
  # The provenance meta MUST be cleared too, otherwise an orphaned
  # classification_string survives on a now-unlinked entry and later
  # mis-drives rate_pair's :automatic tier. Guarded three times: the route/view
  # only exist in development, and the action itself refuses to run anywhere else.
  # Returns to the BARE page: unlike the connect actions this deliberately drops
  # every query param (filter, sort, columns, paging, open rows) -- the whole
  # page starts from scratch. The client-side row selections are cleared by the
  # button's own JS (see the dev block in the participant_fees view).
  def reset_links
    raise ActionController::RoutingError, "not available" unless Rails.env.development?

    count = AccountingEntry.where.not(datev_booking_id: nil).count
    AccountingEntry.where.not(datev_booking_id: nil).update_all(datev_booking_id: nil,
      datev_booking_link_meta: {}, updated_at: Time.zone.now)
    WsjrdpCamtTransaction.where.not(datev_booking_id: nil)
      .update_all(datev_booking_id: nil, updated_at: Time.zone.now)
    redirect_to reconciliation_participant_fees_path,
      alert: "Entwicklung: Verknüpfungen von #{count} DATEV-Buchungen zurückgesetzt " \
             "(Filter, Spalten, Seiten und Auswahl ebenfalls zurückgesetzt)."
  end

  # Connect ONE entry to ONE explicitly chosen DATEV booking (alternatives list
  # in the entry detail view).
  def connect_single_entry
    entry = AccountingEntry.find(params[:entry_id])
    booking = DatevBooking.find(params[:booking_id])
    if Fin::DatevBookingMatcher.connect_pair!(booking, entry, linked_by_id: current_user&.id)
      redirect_back_to_list(notice: "Beitragsbuchung ##{entry.id} mit Buchung ##{booking.id} verknüpft.")
    else
      redirect_back_to_list(alert: "Verknüpfung nicht möglich (Buchung oder Beitragsbuchung bereits verknüpft).")
    end
  end

  private

  def authorize_action
    authorize!(:show, DatevBooking)
  end

  # The resolved state of the entries table (the bookings one is
  # #booking_table_state).
  def entries_table_state
    wsjrdp_expandable_table_state(ENTRIES_POLICY)
  end

  # THE way from the bookings table's state to a relation: the policy's fixed
  # slots (LOCKED_FILTER_TREE) compiled with the full schema, the user's filter
  # with the exclude:-reduced schema on top. Nothing here decodes, validates,
  # compiles or joins by hand -- the batch join the batch-backed attributes need
  # comes from the schema's own base relation
  # (Wsjrdp::Filtering::FilterSchema#compile).
  def filtered_scope
    @filtered_scope ||= booking_table_state.filter.scope(DatevBooking.all)
  end

  # Both tables' URL-chosen params, so a connect redirect returns to the same
  # view. Remembered fields restore themselves from the store, so only what the
  # URL actually carries has to be re-emitted (see Wsjrdp::TableState#wire_params).
  def redirect_back_to_list(**flash)
    carry = booking_table_state.wire_params.merge(entries_table_state.wire_params)
    redirect_to reconciliation_participant_fees_path(carry), **flash
  end

  # Match result over the current (locked + user) filter scope. proposals
  # feed the injected column, counts and connect; alternatives feed the
  # detail-view candidate list.
  def match_result
    @match_result ||= Fin::DatevBookingMatcher.propose(filtered_scope)
  end

  def match_proposals
    match_result.proposals
  end

  def match_alternatives
    match_result.alternatives
  end

  # Reverse match (entry -> booking) over ALL unmatched entries, for the entries
  # table's proposal column, its candidate lists and the bulk connect.
  def entry_match_result
    @entry_match_result ||= Fin::DatevBookingMatcher.propose_for_entries(unmatched_entries_relation)
  end

  def entry_match_proposals
    entry_match_result.proposals
  end

  def entry_match_alternatives
    entry_match_result.alternatives
  end

  # --- selection criteria (quick-select "confidence atoms") ------------------
  # The all-pages selection is a set of DISJOINT confidence atoms -- ONE per
  # rating tier (Fin::DatevBookingMatcher::Match#tier), so counts stay additive and
  # the 50 % middle/low boundary lives ONLY in Match#tier, never here:
  #   auto  => :automatic        (Ende-zu-Ende / 2025-Import-Regel)
  #   hhigh => :heuristic_high   (heuristisch 100 %)
  #   hmid  => :heuristic_middle (heuristisch über 50 %)
  #   hlow  => :heuristic_low    (heuristisch bis 50 %)
  # Atom keys are single tokens so the JS dataset camel-casing (atom + "Count")
  # lines up. select_all carries them comma-joined ("1" = all). See
  # fin/reconciliation/_connect_controls + shared/_table_selection_js.
  ATOM_TIERS = {"auto" => :automatic, "hhigh" => :heuristic_high,
                "hmid" => :heuristic_middle, "hlow" => :heuristic_low}.freeze
  TIER_ATOMS = ATOM_TIERS.invert.freeze

  # The quick-select atom key for a proposal (its rating tier), or nil.
  def proposal_atom(match)
    match && TIER_ATOMS[match.tier]
  end

  def connect_only_ids(proposals, id_param)
    spec = params[:select_all].to_s
    return nil if spec == "1"           # every proposal
    return atom_keys(proposals, spec) if spec.present?
    Array(params[id_param])             # the posted (individual) ids
  end

  def atom_keys(proposals, spec)
    tiers = spec.split(",").filter_map { |a| ATOM_TIERS[a] }
    proposals.select { |_, m| tiers.include?(m.tier) }.keys
  end

  # {atom => {count:, sum:}} over a proposal map (sum = the entry's amount),
  # for the connect controls' button labels and the confirm dialog.
  def proposal_atom_stats(proposals)
    stats = ATOM_TIERS.keys.to_h { |atom| [atom, {count: 0, sum: 0}] }
    proposals.each_value do |m|
      next unless (atom = proposal_atom(m))
      stats[atom][:count] += 1
      stats[atom][:sum] += m.entry.amount_cents
    end
    stats
  end

  # Only entries that move money AND are not flagged as
  # excluded_from_fee_reconciliation take part: zero-amount entries (e.g.
  # "Finanzstatus auf OK gesetzt" notes) have no booking by nature, and
  # flagged entries ("von der Beitrags-Abstimmung ausgenommen") are left out of
  # every count, list and match on this page.
  def monetary_entries
    AccountingEntry.where.not(amount_cents: 0).fee_reconciliation_relevant
  end

  # Shown as a small note when > 0.
  def excluded_entries_count
    @excluded_entries_count ||=
      AccountingEntry.where.not(amount_cents: 0).excluded_from_fee_reconciliation.count
  end

  # Entries matched to a DATEV booking. accounting_entries.datev_booking_id is
  # 1:1 (unique index), so this counts entries as well as bookings.
  def matched_entries_count
    @matched_entries_count ||= monetary_entries.joins(:datev_booking).count
  end

  def total_entries_count
    @total_entries_count ||= monetary_entries.count
  end

  # Beitragsbuchungen (money-moving, reconciliation-relevant) still WITHOUT a
  # linked DATEV booking -- their number and the summed amount (in cents). The
  # sum is the net of the still-open entries (refunds are negative), shown next
  # to the count so the size of the open reconciliation work is visible.
  def unmatched_entries_relation
    @unmatched_entries_relation ||= monetary_entries.where.missing(:datev_booking)
  end

  def unmatched_entries_count
    @unmatched_entries_count ||= unmatched_entries_relation.count
  end

  def unmatched_entries_sum
    @unmatched_entries_sum ||= unmatched_entries_relation.sum(:amount_cents)
  end

  # Month histogram of the entries WITHOUT a linked DATEV booking (usually:
  # months whose Primanota is not yet imported). Keyed by the first of the
  # month (value date, falling back to the booking date), sorted ascending;
  # months in between without any unmatched entry appear with count 0.
  def unmatched_entries_by_month
    @unmatched_entries_by_month ||= begin
      counts = monetary_entries
        .where.missing(:datev_booking)
        .group(Arel.sql("date_trunc('month', COALESCE(accounting_entries.value_date, accounting_entries.booking_date))"))
        .count
        .transform_keys { |month| month&.to_date }
      dated = counts.except(nil)
      months = if dated.any?
        (dated.keys.min..dated.keys.max).select { |d| d.day == 1 }.map { |m| [m, dated[m] || 0] }
      else
        []
      end
      months += [[nil, counts[nil]]] if counts.key?(nil)
      months
    end
  end

  # The table's NATURAL order (nothing sorted): entries that HAVE a proposed DATEV
  # booking come first, so the actionable matches are on page 1. Otherwise the
  # many entries whose DATEV booking is not yet imported (e.g. the current month's
  # SEPA collections / returns) bury the handful with a suggestion, and the table
  # looks like it has no proposals at all. A sort the user picks takes over
  # (Wsjrdp::ExpandableTableRows only asks for this order while the sort list is
  # empty), which is why the table declares no sort default.
  def order_proposals_first(relation)
    ids = entry_match_proposals.keys.map(&:to_i)
    relation = relation.order(Arel.sql("CASE WHEN accounting_entries.id IN (#{ids.join(",")}) THEN 0 ELSE 1 END")) if ids.any?
    relation
      .order(Arel.sql("COALESCE(accounting_entries.value_date, accounting_entries.booking_date) DESC NULLS LAST"))
      .order(id: :desc)
  end

  # The SEPA-collection subset (direct debit runs) -- the bulk of what the
  # matcher will link (Tier 1/2 in doc/fin/bookkeeping_schema_review.md §3c).
  # NOTE: pre-notifications themselves are never part of the reconciliation
  # (they are announcements, not money movements); the FK here is used purely
  # as the marker/join key that identifies an entry as a SEPA collection.
  def collection_entries_count
    @collection_entries_count ||=
      monetary_entries.where.not(direct_debit_pre_notification_id: nil).count
  end
end
