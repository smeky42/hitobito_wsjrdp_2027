# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Shared plumbing for any page that renders the reusable DATEV bookings listing
# (shared/filtering/_builder + fin/bookings/_columns + _listing): the generic
# CNF filter (doc/generic_filter_builder.md) compiled to a scope, handed to
# DatevBookingsQuery for sorting/pagination/columns/sum, plus the
# "Zurücksetzen" clear handling.
#
# A host controller customises the listing by overriding:
#   * filter_excluded_attributes -- schema attributes not usable on this page
#   * filter_pinned_scope        -- the fixed base relation (page scope the
#                                   user cannot change or widen)
#   * filter_hidden_conditions   -- hidden CNF slots (default: status=active)
#   * default_filter_tree        -- filter shown when no ?filter param is given
# and runs its apply action via apply_filter_and_redirect(<get path>).
module Fin::BookingsFiltering
  extend ActiveSupport::Concern

  included do
    helper_method :query, :filter_catalog, :filter_value,
      :filter_locked_value, :filter_full_catalog,
      :account_filter_options, :offsetting_account_filter_options,
      :cost_center_filter_options, :period_filter_options
  end

  def query
    @query ||= DatevBookingsQuery.new(params,
      base: booking_base_scope, hidden_filters: hidden_booking_filters,
      default_column_keys: booking_default_column_keys, prefix: booking_param_prefix)
  end

  # Query-param namespace for this page's bookings listing ("" -> page/sort/...,
  # "bk" -> bk_page/bk_sort/...). A page hosting a SECOND independent table
  # (e.g. the reconciliation entries table) overrides this so the two page/sort/
  # filter independently. See ExpandableTableHelper / doc/expandable_table.md.
  def booking_param_prefix
    ""
  end

  # The concrete filter param name for this page (<prefix>_filter, or "filter").
  def booking_filter_param
    booking_param_prefix.empty? ? "filter" : "#{booking_param_prefix}_filter"
  end

  # Shown columns while no <prefix>_cols param is set (nil -> global default).
  def booking_default_column_keys
    nil
  end

  # --- overridable configuration -------------------------------------------

  def filter_excluded_attributes
    []
  end

  # Host-pinned conditions as a CNF tree: shown in the builder as read-only
  # slots AND compiled (against the full schema, which may contain attributes
  # the user picker excludes) into the pinned scope -- one source for display
  # and enforcement.
  def locked_filter_tree
    []
  end

  def filter_pinned_scope
    return DatevBooking.all if locked_filter_tree.empty?

    Filtering::Compiler.new(DatevBookingsFilter.bound)
      .apply(Filtering::Query.parse(locked_filter_tree))
  end

  def filter_hidden_conditions
    DatevBookingsFilter::HIDDEN
  end

  def default_filter_tree
    nil
  end

  # --- generic CNF filter plumbing ------------------------------------------

  def filter_bound_schema
    @filter_bound_schema ||=
      DatevBookingsFilter.bound(except: filter_excluded_attributes.presence)
  end

  def filter_query
    @filter_query ||= if params[booking_filter_param].blank? && default_filter_tree
      Filtering::Query.parse(default_filter_tree)
    else
      Filtering::UrlCodec.decode(params[booking_filter_param], schema: filter_bound_schema)
    end
  end

  # User filter + hidden conditions, compiled over the pinned page scope.
  def filtered_scope
    @filtered_scope ||= Filtering::Compiler.new(filter_bound_schema)
      .apply(filter_query, relation: filter_pinned_scope,
        hidden: filter_hidden_conditions)
  end

  def filter_catalog
    filter_bound_schema.catalog
  end

  def filter_value
    filter_query.as_json
  end

  def filter_locked_value
    locked_filter_tree
  end

  # Catalog over the FULL schema, used to label locked conditions whose
  # attributes the user picker does not offer.
  def filter_full_catalog
    @filter_full_catalog ||= DatevBookingsFilter.bound.catalog
  end

  # Shared PRG apply: parse the posted value tree, encode it to Rison and
  # redirect to the shareable GET URL (sort/columns/page-size carried along).
  # All params are namespaced by booking_param_prefix so a second table's state
  # (and the entries table's) is preserved.
  def apply_filter_and_redirect(target_path)
    tree = begin
      JSON.parse(params[:filter_json].to_s)
    rescue JSON::ParserError
      []
    end
    rison = Filtering::UrlCodec.encode(Filtering::Query.parse(tree),
      schema: filter_bound_schema)
    page_param = booking_param_prefix.empty? ? "page" : "#{booking_param_prefix}_page"
    # The builder posts the state to carry (this table's sort/cols/per + any
    # sibling table's params) as hidden fields; keep all of them, drop this
    # table's old filter + page, then set the new filter.
    drop = %w[filter_json controller action authenticity_token commit utf8 _method] +
      [booking_filter_param, page_param]
    kept = params.to_unsafe_h.except(*drop)
    parts = kept.to_query.split("&").compact_blank
    parts << "#{booking_filter_param}=#{Filtering::UrlCodec.escape_for_query(rison)}" if rison
    target = parts.any? ? "#{target_path}?#{parts.join("&")}" : target_path
    redirect_to target, status: :see_other
  end

  # DatevBookingsQuery draws from the compiled filter scope; its legacy
  # per-field filters are disabled (the CNF filter owns filtering).
  def booking_base_scope
    filtered_scope
  end

  def hidden_booking_filters
    DatevBookingsQuery::ALL_FILTERS
  end

  # --- "Zurücksetzen": drop the clear marker (and any session memory) --------

  # Reloads the current page without the `clear` marker. Controllers that keep a
  # remembered filter in the session override this to also forget it.
  def handle_clear
    return false unless params.key?(:clear)

    redirect_to "#{request.path}?#{request.query_parameters.except("clear").to_query}"
    true
  end

  # --- filter dropdown options (whole dataset, independent of the page) ------

  # [label, value] pairs of the account numbers actually used, with their name.
  def account_filter_options
    @account_filter_options ||= account_options(:account_number)
  end

  def offsetting_account_filter_options
    @offsetting_account_filter_options ||= account_options(:offsetting_account_number)
  end

  # Names cover both real accounts and suppliers (700xxx personal accounts);
  # their number ranges are disjoint, so one merged lookup labels either kind.
  def account_options(column)
    used = DatevBooking.where.not(column => nil).distinct.pluck(column).sort
    names = WsjrdpLedgerAccount.where(number: used).pluck(:number, :name).to_h
      .merge(WsjrdpPersonalAccount.where(number: used).pluck(:number, :name).to_h)
    used.map { |number| [names[number] ? "#{number} #{names[number]}" : number, number] }
  end

  # [label, value] pairs of the cost centers actually used, with their name so
  # they can be found by typing the name in the filter control.
  def cost_center_filter_options
    @cost_center_filter_options ||= begin
      used = DatevBooking.where.not(cost_center_number: nil).distinct.pluck(:cost_center_number).sort
      names = WsjrdpCostCenter.where(number: used).pluck(:number, :name).to_h
      used.map { |code| [names[code] ? "#{code} #{names[code]}" : code, code] }
    end
  end

  def period_filter_options
    @period_filter_options ||=
      DatevBooking.where.not(primanota_period: nil).distinct.order(primanota_period: :desc)
        .pluck(:primanota_period)
  end
end
