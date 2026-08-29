# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Shared plumbing of the Buchhaltung pages (Fin::LedgerAccountsController,
# Fin::CostCentersController, Fin::PersonalAccountsController,
# Fin::BookingBatchesController): the bookings table embedded in an item's
# detail and the shared full-page/turbo-frame rendering of the per-item detail
# pages.
#
# The three summary lists (Sachkonten, Kostenstellen, Kreditoren) are
# RELATION-BACKED: their totals are columns of the relation itself
# (WsjrdpLedgerAccount.with_booking_summary, WsjrdpCostCenter.with_booking_summary,
# WsjrdpPersonalAccount.with_booking_summary), so each page declares its own
# policy with a `filter:`, builds its Wsjrdp::ExpandableTableRows over
# state.filter.scope(...) and aggregates its footer totals in SQL. This concern
# serves the second table (the item's bookings) and #render_item_detail.
#
# WHAT AN INCLUDING CONTROLLER MUST PROVIDE. A Buchhaltung section has up to two
# tables and DECLARES them itself, so each controller's declarations are visible
# in the controller -- this concern only reads the resolved states:
#
#   SUMMARY_POLICY = wsjrdp_expandable_table_policy prefix: "",
#     columns: Fin::BookkeepingSummaryColumns::LEDGER_ACCOUNTS.codec,
#     ...
#     filter: {policy: :remember, schema: Fin::LedgerAccountsFilterSchema}
#   ITEM_BOOKINGS_POLICY = wsjrdp_expandable_table_policy(
#     **Fin::BookkeepingSummaries.item_bookings_policy_options(row_param: :number,
#       nested: true))
#
#   def summary_table_state = wsjrdp_expandable_table_state(SUMMARY_POLICY)
#   def item_bookings_table_state = wsjrdp_expandable_table_state(ITEM_BOOKINGS_POLICY)
#
# plus the `helper_method`s its views need. A section without a summary list of
# its own (Buchungsstapel) declares only the second one, omits `nested:`, and
# then nothing may call #summary_table_state.
module Fin::BookkeepingSummaries
  extend ActiveSupport::Concern

  # Default page size of the condensed bookings tables inside the detail views
  # (the full bookings list uses 50).
  CONDENSED_DEFAULT_PER = 25

  # Default page size of a summary list.
  SUMMARY_DEFAULT_PER = 50

  # The bookings table embedded in one item's detail (prefix "b"). It remembers
  # per ITEM (D2 -- two cost centers keep separate column/sort memory), which is
  # what `row_param` keys: the path segment identifying one item.
  #
  # `nested: true` says that this table sits inside a SUMMARY LIST's detail row:
  # it then inherits the nesting depth that list put into the detail's frame URL,
  # so a table inside a detail keeps counting up. Only a section that has a
  # summary list may ask for it -- the lambda reads #summary_table_state, which
  # is exactly what such a section declares. A section without one
  # (Buchungsstapel) leaves `nested:` alone and starts at level 0.
  def self.item_bookings_policy_options(row_param:, nested: false)
    options = {prefix: "b",
               columns: Fin::DatevBookingsColumns.codec,
               sort: {default: [["booking_date", "desc"]]},
               cols: {default: Fin::DatevBookingsColumns.default_keys},
               per_page: {default: CONDENSED_DEFAULT_PER},
               store_key: -> { "#{controller_path}##{action_name}:#{params[row_param]}" }}
    return options unless nested

    options.merge(level: {default: -> { summary_table_state.level }})
  end

  included do
    include Wsjrdp::TableStateful
  end

  private

  # The detail views are shown both as a full page (the "Detailseite" link of
  # the detail row's header line) and lazy-loaded into
  # an inline expandable row via a turbo frame; the latter is a frame request and
  # needs no layout (the frame partial carries its own markup).
  def render_item_detail
    render layout: false if request.headers["Turbo-Frame"].present?
  end

  # --- the item's bookings table ----------------------------------------------

  # THE condensed bookings table embedded in one item's detail, for an already
  # scoped bookings relation. The batch is LEFT JOINed because the
  # Primanota-Periode column sorts on it; what the page preloads is
  # Fin::DatevBookingsColumns::PRELOADS.
  # `sum:` is the column the shown total aggregates: the account-perspective
  # signed_leg_amount for a legs-backed list, the plain signed_base_amount
  # otherwise.
  def item_bookings(scope, sum: :signed_base_amount)
    Wsjrdp::ExpandableTableRows.new(item_bookings_table_state, scope.left_joins(:batch),
      sort: Fin::DatevBookingsColumns.sort_expressions, sum: sum,
      preload: Fin::DatevBookingsColumns::PRELOADS)
  end
end
