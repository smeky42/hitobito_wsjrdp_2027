# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# DECLARATION of one expandable table's state (doc/plans/2026-09_expandable-table-state.md,
# D2c): which query-param namespace it uses, where each field is stored, what the
# defaults are and what the controller fixes. Written ONCE at class level through
# Wsjrdp::TableStateful.wsjrdp_expandable_table_policy; the per-request counterpart
# is the resolved Wsjrdp::TableState.
#
#   wsjrdp_expandable_table_policy prefix: "bk",
#     columns:  Fin::DatevBookingsColumns.codec,                # key => abbr codec
#     sort:     {default: [["booking_date", "desc"]]},          # LONG names (D2b)
#     cols:     {default: %w[booking_date signed_base_amount],   # declared order = column order
#                exclude: %w[kind],                     # columns THIS table lacks
#                labels:  {"party" => "Karteninhaber"}},   # ... and its own names
#     per_page: {default: 50, max: 500},                    # or {default: :all}
#     filter:   {policy: :url,
#                schema: Fin::DatevBookingsFilterSchema,          # the dataset (mandatory)
#                fixed: [{slots: LOCKED_TREE, show: :readonly},
#                        {slots: HIDDEN_TREE, show: :hidden}],
#                exclude: %i[sphere],
#                default: [[["konto", "in", "41030"]]],     # user tree, if nothing chosen
#                presets: [{key: "with_bookings", label: "Nur mit Buchungen",
#                           slots: [[["booking_count", "gt", 0]]]}]},
#     pane:     {default: 1}
#
# Every field option takes either a bare policy symbol (`filter: :remember`) or a
# Hash {policy:, default:, store:, ...}. Values that depend on the request (a
# nested store key from params[:id], a fixed filter value from the path) are given
# as lambdas and evaluated on the controller instance at resolve time.
#
# The FIELD-SPECIFIC options:
#   cols:     exclude: columns of the codec that THIS table does not have, and
#             labels: {key => "..."} the names it gives some of them -- a dataset
#             is described ONCE (Wsjrdp::ExpandableTableColumns) and each table
#             shapes that description (D2b). Both take LONG column keys; a key
#             that is not in the codec, or a default column that is also
#             excluded, raises at declaration time -- or, for a lambda, when it
#             is evaluated.
#   per_page: max: the cap on a hand-written ?z=
#   filter:   schema: (mandatory), fixed:, exclude:, default:, presets: (D2e).
#             A preset may additionally carry icon: (a FontAwesome 5 name
#             WITHOUT the "fa-" prefix) and css_class: (added verbatim to its
#             toggle link) -- display only, see doc/wsjrdp/expandable_table.md.
#
# THREE POLICIES (D1):
#   :url       the value lives in the URL only, nothing is remembered
#   :remember  the URL carries it, the store mirrors the last value and restores
#              it when the param is absent
#   :fixed     the controller gives the value; params and store are NOT consulted
#              and the widget renders it read-only (D8.1)
class Wsjrdp::TableStatePolicy
  # Page-wide reset (D3): clears every registered table's store. Its value is
  # ignored. A bare "r" is the per-table reset (`<prefix>r=1`), which is why the
  # page-wide one needs a name of its own.
  PAGE_RESET_PARAM = "table_state_reset"
  RESET_SHORT = "r"

  # THE field table (D2a). A query param is `<prefix><short>` -- the prefix
  # followed directly by a ONE-character field name, so param names can never
  # collide across prefixes (P1 + x == P2 + y forces P1 == P2). Adding a field
  # means adding one row here; the letter must stay unique.
  #
  #   field     short  wire form                     default policy
  #   sort      s      RISON list "bez,nr~"          :remember
  #   cols      c      "nr,~bez,sum" (~ = hidden)    :remember
  #   filter    f      Rison CNF tree                :url
  #   per_page  z      integer or "all" (=> :all)    :remember
  #   page      p      integer                       :remember
  #   open      o      comma list of row keys        :url  (never remembered, D4)
  #   level     l      integer (nesting depth)       :url
  #   pane      e      "1" / "0"                     :remember, store :cookie
  FIELD_DEFINITIONS = {
    sort: {short: "s", policy: :remember},
    cols: {short: "c", policy: :remember},
    filter: {short: "f", policy: :url},
    per_page: {short: "z", policy: :remember},
    page: {short: "p", policy: :remember},
    open: {short: "o", policy: :url},
    level: {short: "l", policy: :url},
    pane: {short: "e", policy: :remember, store: :cookie}
  }.freeze

  FIELDS = FIELD_DEFINITIONS.keys.freeze
  POLICIES = %i[url remember fixed].freeze
  # open/level are transient by nature (D4: open never survives leaving the page;
  # level belongs to the frame URL of one lazy detail).
  NEVER_REMEMBERED = %i[open level].freeze

  # Column keys and their abbreviations are list-param tokens ("," and "~" are the
  # separators of the sort / cols params), so they must not contain either --
  # see doc/wsjrdp/url_encoding.md §7.
  TOKEN_FORMAT = /\A[a-z0-9_]+\z/
  # Letters only, so `<prefix><short>` stays unambiguous.
  PREFIX_FORMAT = /\A[a-z]*\z/

  # One field's declaration. `options` carries the field-specific extras
  # (filter: fixed/exclude, per_page: max).
  Field = Data.define(:name, :short, :policy, :default, :store, :options) do
    def fixed? = policy == :fixed

    def remember? = policy == :remember
  end

  attr_reader :prefix, :columns, :fields, :store, :raw_store_key

  def initialize(prefix:, columns: {}, store: :session, store_key: nil, **field_options)
    @prefix = prefix.to_s
    raise ArgumentError, "invalid table prefix #{@prefix.inspect}" unless PREFIX_FORMAT.match?(@prefix)

    @columns = build_columns(columns)
    @store = store.to_sym
    @raw_store_key = store_key
    @fields = build_fields(field_options)
    validate_static_column_shaping!
    freeze
  end

  # THE rule for a column token, in one place: the codec's keys and
  # abbreviations end up in the ?c= / ?s= params, whose separators are "," and
  # "~". Wsjrdp::ExpandableTableColumns validates its declarations through this
  # very method, so a column description and a hand-written codec are held to
  # the same rule with the same message.
  def self.validate_token!(token)
    return token if TOKEN_FORMAT.match?(token)

    raise ArgumentError, "column token #{token.inspect} must match #{TOKEN_FORMAT.source}"
  end

  def field(name) = @fields.fetch(name.to_sym)

  def field?(name) = @fields.key?(name.to_sym)

  # The concrete query-param name of a field, e.g. param_name(:sort) => "bks".
  def param_name(name) = "#{@prefix}#{field(name).short}"

  # Per-table reset param (D3): "?<prefix>r=1".
  def reset_param = "#{@prefix}#{RESET_SHORT}"

  # --- the column codec, which doubles as the allow-list (D8.5) ---------------
  #
  # The codec describes the DATASET -- one Wsjrdp::ExpandableTableColumns per
  # dataset, whatever the table. Which of those columns a single TABLE has, and
  # what it calls them, is the `cols: {exclude:, labels:}` shaping below.

  def column_keys = @columns.keys

  def abbr_for(key) = @columns[key.to_s] || key.to_s

  # A wire token (an abbreviation, or the long key itself) -> the long column
  # key, or nil when the token is not a column of the dataset.
  def key_for(token)
    token = token.to_s
    return token if @columns.key?(token)
    @abbr_to_key[token]
  end

  def column?(key) = @columns.key?(key.to_s)

  # --- the per-table column shaping (`cols: {exclude:, labels:}`) -------------
  #
  # Both options may be LAMBDAS (the Moss list serves its five routes from one
  # declaration, and each kind tab has other columns), so the shaped set is a
  # per-REQUEST value and lives on the resolved Wsjrdp::TableState::ColumnSet --
  # never on this frozen object, which is one shared class-level constant.
  #
  # What lives here is the RULE: it is applied to a plain declaration when the
  # controller class loads and to an evaluated lambda at resolve time, so a typo
  # raises the same error whichever form the host chose.

  # The long keys of the columns THIS table does not have, as a Set.
  def excluded_columns(raw)
    keys = Array(raw).map(&:to_s)
    validate_column_keys!(keys, "cols: exclude:")
    keys.to_set
  end

  # key => the name THIS table gives that column, overriding the description's.
  def column_labels(raw)
    labels = (raw || {}).to_h { |key, label| [key.to_s, label.to_s] }
    validate_column_keys!(labels.keys, "cols: labels:")
    labels
  end

  # A column this table does not have cannot be one of its default columns: the
  # two options would contradict each other and the table would silently start
  # with fewer columns than the host declared.
  def validate_cols_default!(keys, excluded)
    clash = Array(keys).map(&:to_s).select { |key| excluded.include?(key) }
    return if clash.empty?

    raise ArgumentError, "cols: default column(s) #{clash.join(", ")} are excluded from this table"
  end

  # --- store -----------------------------------------------------------------

  # Default: "<controller_path>#<action>" plus the prefix, so two tables on one
  # page never share memory. An explicit store_key: (String or lambda) lets
  # several actions share -- or a nested table key its memory per parent row (D2).
  def store_key_for(controller)
    key = evaluate(@raw_store_key, controller)
    key ||= "#{controller.controller_path}##{controller.action_name}"
    @prefix.empty? ? key.to_s : "#{key}|#{@prefix}"
  end

  # The store a field lives in (its own `store:` overriding the table's).
  def store_for(name) = field(name).store || @store

  # Evaluate a possibly request-dependent declaration value on the controller.
  def evaluate(value, controller)
    return value unless value.is_a?(Proc)
    controller ? controller.instance_exec(&value) : value.call
  end

  private

  def build_columns(columns)
    map = columns.is_a?(Hash) ? columns : Array(columns).to_h { |k| [k, k] }
    map = map.to_h { |key, abbr| [key.to_s, abbr.to_s] }.freeze
    map.each { |key, abbr| [key, abbr].each { |token| self.class.validate_token!(token) } }
    @abbr_to_key = map.invert.freeze
    map
  end

  def validate_column_keys!(keys, what)
    keys.each do |key|
      next if @columns.key?(key)

      raise ArgumentError, "#{what} #{key.inspect} is not a column of this table's codec " \
                           "(#{@columns.keys.join(", ")})"
    end
  end

  # A `cols:` shaping given as a plain value is checked when the controller class
  # is loaded, so a typo -- or a column renamed in the dataset's description --
  # fails at boot like every other declaration error. A LAMBDA cannot be checked
  # here: it is evaluated per request and passes the very same checks in
  # Wsjrdp::TableState::Resolver.
  def validate_static_column_shaping!
    options = field(:cols).options
    column_labels(options[:labels]) unless options[:labels].is_a?(Proc)
    return if options[:exclude].is_a?(Proc)

    excluded = excluded_columns(options[:exclude])
    default = field(:cols).default
    validate_cols_default!(Array(default), excluded) unless default.nil? || default.is_a?(Proc)
  end

  def build_fields(field_options)
    unknown = field_options.keys.map(&:to_sym) - FIELDS
    raise ArgumentError, "unknown table state field(s): #{unknown.join(", ")}" if unknown.any?

    FIELD_DEFINITIONS.to_h { |name, definition| [name, build_field(name, definition, field_options[name])] }
      .freeze
  end

  def build_field(name, definition, given)
    options = normalize_options(given)
    validate_filter_schema!(name, given, options)
    policy = (options.delete(:policy) || definition[:policy]).to_sym
    raise ArgumentError, "unknown policy #{policy.inspect} for #{name}" unless POLICIES.include?(policy)
    if policy == :remember && NEVER_REMEMBERED.include?(name)
      raise ArgumentError, "the #{name} field cannot be remembered (see D4)"
    end

    Field.new(name: name, short: definition[:short], policy: policy,
      default: options.delete(:default), store: (options.delete(:store) || definition[:store])&.to_sym,
      options: options.freeze)
  end

  # The filter's dataset comes ONLY from this class-level declaration -- never
  # from a param, the store or a cookie, so no request can point a table at
  # another dataset's schema. Declaring any filter option without it would leave
  # the resolver with a filter it cannot decode, validate or compile, so it fails
  # loudly here rather than silently rendering an unfiltered page.
  #
  # A table that declares NO filter: at all gets an inert filter field instead:
  # the filter param is ignored and state.filter carries nothing (no catalog, no
  # user query, and #scope hands its argument straight back).
  def validate_filter_schema!(name, given, options)
    return unless name == :filter
    return if given.nil? || options[:schema]

    raise ArgumentError, "filter: needs a schema: -- the dataset module extending " \
                         "Wsjrdp::Filtering::FilterSchema (e.g. Fin::DatevBookingsFilterSchema). " \
                         "Declare no filter: at all for a table without a filter."
  end

  # A bare symbol (`filter: :remember`) is shorthand for {policy: :remember}.
  def normalize_options(given)
    case given
    when nil then {}
    when Symbol, String then {policy: given}
    when Hash then given.transform_keys(&:to_sym)
    else raise ArgumentError, "table state field options must be a Symbol or a Hash, got #{given.class}"
    end
  end
end
