# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# "Abstimmung" (reconciliation) section: matching accounting entries with
# DATEV bookings. See doc/bookkeeping_schema_review.md §3c for the verified
# matching strategy; the actual matcher lands in a later step.
class Fin::ReconciliationController < Fin::FinController
  include Fin::BookingsFiltering

  before_action :authorize_action

  helper_method :matched_entries_count, :total_entries_count,
    :collection_entries_count, :match_proposals, :match_alternatives,
    :unmatched_entries_by_month, :unmatched_entries_page, :ae_open_keys,
    :excluded_entries_count, :unmatched_entries_count, :unmatched_entries_sum,
    :ae_per_page, :entry_match_proposals, :entry_match_alternatives,
    :proposal_atom_stats, :proposal_atom

  # Sortable columns of the unmatched-Beitragsbuchungen table (shared expandable
  # table). Maps the column sort_key to its SQL expression.
  AE_SORT_COLUMNS = {
    "date" => "COALESCE(accounting_entries.value_date, accounting_entries.booking_date)",
    "amount" => "accounting_entries.amount_cents",
    "description" => "accounting_entries.description"
  }.freeze

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
    sphere period cost_center secondary_cost_center konto offsetting_account
    any_account accounting_entry
  ].freeze

  # Übersicht at /reconciliation -- still empty.
  def overview
  end

  # TN-Beiträge (participant fees) at /reconciliation/participant_fees: the
  # match counts plus the list of not-yet-matched fee bookings (locked
  # conditions above; user filter on top).
  def participant_fees
    return if handle_clear

    query
  end

  def apply_participant_fees
    apply_filter_and_redirect(reconciliation_participant_fees_path)
  end

  # Connect proposed matches (DatevBookingMatcher) to their Beitragsbuchung:
  # sets accounting_entry_id, person_id AND camt_transaction_id (mirrored from
  # the entry) in one bulk statement. mode=all connects every proposal of the
  # current filter scope; otherwise only the posted booking_ids (the page
  # button and the per-row checkboxes both send ids).
  def connect_participant_fees
    only_ids = connect_only_ids(match_proposals, :booking_ids)
    connected = DatevBookingMatcher.connect!(match_proposals, only_ids: only_ids,
      linked_by_id: current_user&.id)
    redirect_back_to_list(notice: "#{connected} Buchungen mit ihrer Beitragsbuchung verknüpft.")
  end

  # Connect ONE booking to ONE explicitly chosen entry (alternatives list in
  # the detail view).
  def connect_single
    booking = DatevBooking.find(params[:booking_id])
    entry = AccountingEntry.find(params[:entry_id])
    if DatevBookingMatcher.connect_pair!(booking, entry, linked_by_id: current_user&.id)
      redirect_back_to_list(notice: "Buchung ##{booking.id} mit Beitragsbuchung ##{entry.id} verknüpft.")
    else
      redirect_back_to_list(alert: "Verknüpfung nicht möglich (Buchung oder Beitragsbuchung bereits verknüpft).")
    end
  end

  # REVERSE bulk connect: connect selected accounting entries to their proposed
  # DATEV booking (mirror of connect_participant_fees on the entries table).
  def connect_participant_entries
    only_ids = connect_only_ids(entry_match_proposals, :entry_ids)
    connected = DatevBookingMatcher.connect_reverse!(entry_match_proposals, only_ids: only_ids,
      linked_by_id: current_user&.id)
    redirect_back_to_list(notice: "#{connected} Beitragsbuchungen mit ihrer DATEV-Buchung verknüpft.")
  end

  # DEVELOPMENT ONLY -- wipe every DATEV booking's links (accounting_entry_id,
  # person_id, the mirrored camt_transaction_id AND the link provenance columns)
  # so the whole reconciliation can be replayed from scratch while testing the
  # matcher. The provenance columns MUST be cleared too, otherwise an orphaned
  # accounting_entry_link_type survives on a now-unlinked booking and later
  # mis-drives rate_pair's :automatic tier. Guarded three times: the route/view
  # only exist in development, and the action itself refuses to run anywhere else.
  # Returns to the BARE page: unlike the connect actions this deliberately drops
  # every query param (filter, sort, columns, paging, open rows) -- the whole
  # page starts from scratch. The client-side row selections are cleared by the
  # button's own JS (see the dev block in the participant_fees view).
  def reset_links
    raise ActionController::RoutingError, "not available" unless Rails.env.development?

    count = DatevBooking.where("person_id IS NOT NULL OR accounting_entry_id IS NOT NULL").count
    DatevBooking.update_all(person_id: nil, accounting_entry_id: nil, camt_transaction_id: nil,
      accounting_entry_link_type: nil, accounting_entry_linked_at: nil,
      accounting_entry_link_person_id: nil, updated_at: Time.zone.now)
    redirect_to reconciliation_participant_fees_path,
      alert: "Entwicklung: Verknüpfungen von #{count} DATEV-Buchungen zurückgesetzt " \
             "(Filter, Spalten, Seiten und Auswahl ebenfalls zurückgesetzt)."
  end

  # Connect ONE entry to ONE explicitly chosen DATEV booking (alternatives list
  # in the entry detail view).
  def connect_single_entry
    entry = AccountingEntry.find(params[:entry_id])
    booking = DatevBooking.find(params[:booking_id])
    if DatevBookingMatcher.connect_pair!(booking, entry, linked_by_id: current_user&.id)
      redirect_back_to_list(notice: "Beitragsbuchung ##{entry.id} mit Buchung ##{booking.id} verknüpft.")
    else
      redirect_back_to_list(alert: "Verknüpfung nicht möglich (Buchung oder Beitragsbuchung bereits verknüpft).")
    end
  end

  private

  def authorize_action
    authorize!(:fin_admin, DatevBooking)
  end

  # The bookings table on this page is namespaced "bk" so it pages/sorts/filters
  # independently of the entries table ("ae").
  def booking_param_prefix
    "bk"
  end

  # Params of BOTH tables (bookings bk_*, entries ae_*), kept across the connect
  # redirects so neither table's state is lost.
  RECON_LIST_PARAMS = %i[
    bk_filter bk_sort bk_sort_dir bk_per bk_cols bk_page bk_open
    ae_sort ae_sort_dir ae_per ae_cols ae_page ae_open
  ].freeze

  def recon_list_params
    params.slice(*RECON_LIST_PARAMS).permit!.to_h
  end

  def redirect_back_to_list(**flash)
    redirect_to reconciliation_participant_fees_path(recon_list_params), **flash
  end

  # --- filter hooks (Fin::BookingsFiltering) ---------------------------------

  def filter_excluded_attributes
    EXCLUDED_FILTER_ATTRIBUTES
  end

  def locked_filter_tree
    LOCKED_FILTER_TREE
  end

  # Fewer default columns than the main bookings list: Kostenstelle, Konto and
  # Gegenkonto are pinned by the locked filter anyway, and the injected
  # proposal column needs the room. (?cols= still allows any selection.)
  def booking_default_column_keys
    WsjrdpBookingsHelper::DEFAULT_BOOKING_COLUMN_KEYS -
      %w[cost_center_number account_number offsetting_account_number]
  end

  # Match result over the current (locked + user) filter scope. proposals
  # feed the injected column, counts and connect; alternatives feed the
  # detail-view candidate list.
  def match_result
    @match_result ||= DatevBookingMatcher.propose(filtered_scope)
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
    @entry_match_result ||= DatevBookingMatcher.propose_for_entries(unmatched_entries_relation)
  end

  def entry_match_proposals
    entry_match_result.proposals
  end

  def entry_match_alternatives
    entry_match_result.alternatives
  end

  # --- selection criteria (quick-select "confidence atoms") ------------------
  # The all-pages selection is a set of DISJOINT confidence atoms -- ONE per
  # rating tier (DatevBookingMatcher::Match#tier), so counts stay additive and
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

  # Entries matched to a DATEV booking. datev_bookings.accounting_entry_id is
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

  # The unmatched entries themselves (bottom table). Own paging params (ae_page /
  # ae_per) and sort params (ae_sort / ae_sort_dir) so they never collide with
  # the bookings table's; ae_open carries the expanded rows
  # (shared/_expandable_table). Default order: newest first.
  def unmatched_entries_page
    @unmatched_entries_page ||= begin
      rel = unmatched_entries_relation.includes(:subject)
      rel = params[:ae_sort].present? ? apply_ae_sort(rel) : order_proposals_first(rel)
      rel.page(params[:ae_page]).per(ae_per_page)
    end
  end

  # Default order: entries that HAVE a proposed DATEV booking come first, so the
  # actionable matches are on page 1. Otherwise the many entries whose DATEV
  # booking is not yet imported (e.g. the current month's SEPA collections /
  # returns) bury the handful with a suggestion, and the table looks like it has
  # no proposals at all. An explicit user sort (?ae_sort=) still takes over.
  def order_proposals_first(relation)
    ids = entry_match_proposals.keys.map(&:to_i)
    relation = relation.order(Arel.sql("CASE WHEN accounting_entries.id IN (#{ids.join(",")}) THEN 0 ELSE 1 END")) if ids.any?
    relation
      .order(Arel.sql("COALESCE(accounting_entries.value_date, accounting_entries.booking_date) DESC NULLS LAST"))
      .order(id: :desc)
  end

  # Page size of the unmatched-Beitragsbuchungen table (?ae_per=), default 50,
  # capped at 500 (an unbounded page would be a footgun on a large backlog).
  def ae_per_page
    per = params[:ae_per].to_i
    per.positive? ? [per, 500].min : 50
  end

  # Multi-column sort from the single RISON ae_sort param (ExpandableTableSort):
  # tokens are the ae_columns' keys, mapped to fixed SQL via the AE_SORT_COLUMNS
  # allow-list. Empty / unparseable -> the default (newest value/booking date).
  # id DESC stays the final tiebreaker.
  def apply_ae_sort(relation)
    list = ExpandableTableSort.decode(params[:ae_sort].to_s).filter_map do |token, dir|
      expr = AE_SORT_COLUMNS[token]
      expr ? [expr, dir] : nil
    end
    if list.empty?
      return relation
          .order(Arel.sql("COALESCE(accounting_entries.value_date, accounting_entries.booking_date) DESC NULLS LAST"))
          .order(id: :desc)
    end
    order = list.map { |expr, dir| Arel.sql("#{expr} #{dir.to_s.upcase} NULLS LAST") }
    relation.order(*order).order(id: :desc)
  end

  def ae_open_keys
    params[:ae_open].to_s.split(",").to_set
  end

  # The SEPA-collection subset (direct debit runs) -- the bulk of what the
  # matcher will link (Tier 1/2 in doc/bookkeeping_schema_review.md §3c).
  # NOTE: pre-notifications themselves are never part of the reconciliation
  # (they are announcements, not money movements); the FK here is used purely
  # as the marker/join key that identifies an entry as a SEPA collection.
  def collection_entries_count
    @collection_entries_count ||=
      monetary_entries.where.not(direct_debit_pre_notification_id: nil).count
  end
end
