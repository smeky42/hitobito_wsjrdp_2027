# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Controller side of the expandable table's state (D2c of
# doc/plans/2026-09_expandable-table-state.md): the class-level declaration
# DECLARES a table's policy and RETURNS it, the instance method RESOLVES that
# policy object for the current request.
#
#   class Fin::BookingsController < Fin::FinController
#     include Wsjrdp::TableStateful
#
#     BOOKINGS_POLICY = wsjrdp_expandable_table_policy prefix: "",
#       columns:  Fin::DatevBookingsColumns.codec,
#       sort:     {default: [["booking_date", "desc"]]},
#       per_page: {default: 50},
#       filter:   {policy: :remember, schema: Fin::DatevBookingsFilterSchema}
#
#     def booking_table_state = wsjrdp_expandable_table_state(BOOKINGS_POLICY)
#   end
#
# The POLICY OBJECT is the link between the two halves, so a table's prefix is
# written exactly once. A host keeps its policies in constants and names the
# constant wherever it needs the state; nothing looks a table up by its prefix
# string, and resolving a policy that is not declared on this controller raises.
#
# The declaration lives at class level (like before_action, layout or Kaminari's
# paginates_per) because the reset before_action must know every table of the
# page BEFORE the action runs; request-dependent values are given as lambdas and
# evaluated on the controller instance.
#
# The resolved state is memoised per request and frozen. Views never resolve one
# themselves -- each host exposes the states its templates need through its own
# helper_method (`booking_table_state`, `summary_table_state`, ...), so the view,
# the widget and the builder only ever READ a state and never touch params,
# session or cookies (D8.4).
module Wsjrdp::TableStateful
  extend ActiveSupport::Concern

  # Params of the filter-apply POST itself, never of the table (see
  # #wsjrdp_apply_table_filter).
  APPLY_DROPPED_PARAMS = %w[filter_json controller action authenticity_token commit utf8 _method]
    .freeze

  included do
    # The prefix-keyed registry of this page's tables. PRIVATE to the concern:
    # it exists for the page-wide reset (which must know every declared table)
    # and for the smoke spec that resolves them all; hosts address a table by
    # its policy OBJECT, never by its prefix.
    class_attribute :wsjrdp_expandable_table_policies, default: {}.freeze
    before_action :wsjrdp_handle_table_state_reset
  end

  class_methods do
    # Declares one table of this controller's pages and RETURNS its policy --
    # the object the host keeps in a constant and hands to
    # #wsjrdp_expandable_table_state. See Wsjrdp::TableStatePolicy for the
    # available options.
    def wsjrdp_expandable_table_policy(prefix:, **options)
      policy = Wsjrdp::TableStatePolicy.new(prefix: prefix, **options)
      self.wsjrdp_expandable_table_policies =
        wsjrdp_expandable_table_policies.merge(policy.prefix => policy).freeze
      policy
    end
  end

  # The resolved, frozen state of one DECLARED table, addressed by its policy
  # object (a constant of this controller). Identity is checked against the
  # registry, so a policy of another controller -- or one that was declared and
  # then overwritten by a later declaration of the same prefix -- raises instead
  # of silently resolving against the wrong table.
  def wsjrdp_expandable_table_state(policy)
    unless policy.is_a?(Wsjrdp::TableStatePolicy) &&
        self.class.wsjrdp_expandable_table_policies[policy.prefix].equal?(policy)
      raise ArgumentError, "#{policy.inspect} is not a table declared on #{self.class.name} -- " \
                           "pass one of its wsjrdp_expandable_table_policy constants"
    end

    @wsjrdp_expandable_table_states ||= {}
    @wsjrdp_expandable_table_states[policy] ||=
      Wsjrdp::TableState.resolve(policy, params: params,
        stores: wsjrdp_table_state_stores, controller: self)
  end

  # THE apply action of a filter builder (PRG), for every table alike: the posted
  # tree becomes this table's filter param and the browser is redirected to the
  # shareable GET URL.
  #
  #   def apply = wsjrdp_apply_table_filter(booking_table_state, redirect_to: bookings_path)
  #
  # Encoding runs through the STATE (state.filter.encode_tree), so the posted
  # tree passes the same schema allow-list as any URL value -- an attribute the
  # table excludes cannot be smuggled in through the form. This table's old
  # filter, its page and its open rows are dropped (a new filter starts on page 1
  # with everything collapsed, D4); everything else is carried along: this
  # table's sort / columns / page size, any sibling table's state and non-table
  # params.
  #
  # The filter param is ALWAYS emitted, BLANK when nothing survives: a
  # present-but-blank param is the explicit "no conditions" that beats a
  # remembered filter, while an absent one would fall through to the store and
  # bring the just-cleared filter straight back.
  def wsjrdp_apply_table_filter(state, redirect_to:)
    target = redirect_to # a local of that name shadows the redirect_to METHOD below
    wire = state.filter.encode_tree(wsjrdp_posted_filter_tree)
    drop = APPLY_DROPPED_PARAMS + %i[filter page open].map { |field| state.param_name(field) }
    # Path parameters (an :id, a route default such as the Moss kind) travel in
    # the redirect target itself, never in its query string.
    drop += request.path_parameters.keys.map(&:to_s)
    parts = params.to_unsafe_h.except(*drop).to_query.split("&").compact_blank
    parts << "#{state.param_name(:filter)}=" \
             "#{wire ? Wsjrdp::Filtering::UrlCodec.escape_for_query(wire) : ""}"
    self.redirect_to("#{target}?#{parts.join("&")}", status: :see_other)
  end

  private

  def wsjrdp_posted_filter_tree
    JSON.parse(params[:filter_json].to_s)
  rescue JSON::ParserError
    []
  end

  def wsjrdp_table_state_stores
    @wsjrdp_table_state_stores ||= {
      session: Wsjrdp::TableStateStore::Session.new(session),
      cookie: Wsjrdp::TableStateStore::Cookie.new(cookies)
    }
  end

  # D3 -- reset:
  #   ?<prefix>r=1        forgets THAT table and reloads without its params
  #   ?table_state_reset  does the same for every table declared on this page
  # Fixed fields are unaffected (they are never stored and are re-fixed by the
  # policy on the next render).
  def wsjrdp_handle_table_state_reset
    policies = wsjrdp_requested_reset_policies
    return if policies.empty?

    policies.each { |policy| wsjrdp_forget_table_state(policy) }
    redirect_to wsjrdp_url_without_table_params(policies)
  end

  def wsjrdp_requested_reset_policies
    all = self.class.wsjrdp_expandable_table_policies.values
    return all if params.key?(Wsjrdp::TableStatePolicy::PAGE_RESET_PARAM)
    all.select { |policy| params.key?(policy.reset_param) }
  end

  def wsjrdp_forget_table_state(policy)
    key = policy.store_key_for(self)
    wsjrdp_table_state_stores.each_value { |store| store.delete(key) }
  end

  def wsjrdp_url_without_table_params(policies)
    drop = policies.flat_map { |policy|
      Wsjrdp::TableStatePolicy::FIELDS.map { |field| policy.param_name(field) } << policy.reset_param
    } + [Wsjrdp::TableStatePolicy::PAGE_RESET_PARAM]
    query = request.query_parameters.except(*drop)
    return request.path if query.empty?
    # Wsjrdp::RelaxedUrlQuery keeps "," and "~" literal -- doc/wsjrdp/url_encoding.md.
    "#{request.path}?#{Wsjrdp::RelaxedUrlQuery.to_query(query)}"
  end
end
