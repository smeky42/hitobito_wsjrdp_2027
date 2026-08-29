# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The RESOLVED per-request state of one expandable table (sort, columns, filter,
# page size, page, open rows, filter pane, nesting level) -- see
# doc/plans/2026-09_expandable-table-state.md and doc/wsjrdp/expandable_table.md.
#
# Built ONCE per request in the controller (Wsjrdp::TableStateful), frozen, and
# handed to the query object and to the view. The widget, the builder and the
# helpers only READ it; they never look at params, session or cookies (D8.4), so
# a hand-edited URL can change neither the rows nor their order beyond what the
# controller's policy allows.
#
# Readers use LONG names (D2b): sort_list is [[column_key, dir], ...], column
# states are column keys -- the one-letter param names and the short column
# abbreviations exist only on the wire (#param_name / #wire).
#
#   state.sort_list            # => [["booking_date", "desc"]]
#   state.visible_column_keys  # => ["booking_date", "signed_base_amount", ...]
#   state.column_configs(cols) # => this table's columns, with its own labels
#   state.per_page             # => 50, or the symbol :all
#   state.page                 # => 2
#   state.paginate(scope)      # => the current page of a relation or an Array
#   state.open_keys            # => #<Set: {"1234"}>
#   state.filter.user_query    # => the parsed, allow-listed user filter
#   state.filter.readonly_slots# => the fixed slots the builder shows locked
#   state.filter.presets       # => the table's quick-select filter presets
#   state.filter.scope(base)   # => THE filtered relation
#   state.fixed?(:filter)      # => true when the whole field is controller-given
#   state.param_name(:sort)    # => "bks"
#   state.wire(:sort)          # => "bdt~"
class Wsjrdp::TableState
  # ONE BUTTON of a table's filter "Schnellauswahl": the host offers it above the
  # filter pane as a one-click toggle. Two declaration forms -- a slot preset and
  # one member of a group -- end up in this one object, and these readers mean
  # the same in both:
  #
  #   key          the button's own name, unique within the table
  #   label        what the toggle button says
  #   active?      is what the button stands for present in the APPLIED user
  #                filter?
  #   toggle_wire  the wire form of the user filter after clicking the toggle.
  #                "" means "no conditions", which is a present-but-blank filter
  #                param, not an absent one.
  #   icon         OPTIONAL FontAwesome 5 name WITHOUT the "fa-" prefix
  #                ("credit-card"); the bar renders it as <i class="fas fa-...">
  #                ahead of the label. nil = no icon.
  #   css_class    OPTIONAL extra class, added verbatim to the toggle link, so a
  #                host can colour its buttons ("moss-kind-card_transaction").
  #                nil = nothing added.
  #
  # A SLOT PRESET is a named list of slots, and #group? is false:
  #
  #   slots        the preset's slots, strictly parsed (long keys)
  #   active?      is EVERY preset slot present in the user filter? (exact slot
  #                equality -- Wsjrdp::Filtering::SlotEquality, which reads a
  #                sign-invariant condition on either member of a sign pair as
  #                one and the same)
  #   toggle_wire  the user filter without the preset's slots when it is active,
  #                with the missing ones added when it is not
  #
  # A GROUP MEMBER is one of several buttons that SHARE one slot -- the group's
  # `attribute in (values)`, one value per member -- and #group? is true:
  #
  #   group        the group's own name
  #   attribute    the attribute every member of the group speaks about
  #   value        THIS member's value
  #   group_values every member value of the group, in declaration order
  #   slots        nil: a member owns no slot of its own
  #   active?      does a slot of the user filter that is exactly one
  #                `attribute in (...)` condition carry this member's value?
  #   toggle_wire  the user filter with the value added to (taken out of) every
  #                such slot; selecting with no such slot there appends a new
  #                one, and a slot left without a value goes altogether
  #
  # icon and css_class are display only -- they never influence the slots, the
  # active state or the toggle URL, and a button that declares neither renders
  # exactly as it does without them.
  #
  # The active state is computed on the SERVER from the applied filter, never
  # from the builder's unapplied draft -- see doc/wsjrdp/expandable_table.md,
  # "Presets".
  FilterPreset = Data.define(:key, :label, :slots, :active, :toggle_wire, :icon, :css_class,
    :group, :attribute, :value, :group_values) do
    # Data has no per-member defaults; this override gives the display members
    # and the group ones theirs, so a slot preset is constructed by naming
    # neither.
    def initialize(key:, label:, slots:, active:, toggle_wire:, icon: nil, css_class: nil,
      group: nil, attribute: nil, value: nil, group_values: nil)
      super
    end

    def active? = active

    # Is this button one member of a group sharing a slot, rather than a preset
    # owning its own slots?
    def group? = !group.nil?
  end

  # The filter is the one field with partially-fixed semantics (D2e): the
  # effective filter is `fixed slots AND user slots`; the URL param and the store
  # only ever hold the USER part, which is why a user can never remove or widen a
  # fixed slot.
  #
  # EVERYTHING IS ALREADY PARSED when this object exists. The resolver binds the
  # dataset's schema twice per request -- the FULL one for the fixed slots, the
  # one reduced by `exclude:` for the user part -- and runs both halves through
  # the table's filter SCHEMA (Wsjrdp::Filtering::FilterSchema, named by the
  # policy's `schema:` and by nothing else):
  #
  #   fixed slots  -> schema.parse_fixed!  STRICT: a typo raises instead of
  #                                        silently dropping the pin
  #   user part    -> schema.decode        TOLERANT, and applied to the URL value
  #                                        AND the store value alike, so
  #                                        `exclude:` cannot be bypassed through
  #                                        either
  #
  # #scope is therefore the ONLY way from a filter to a relation: fixed slots
  # first (full schema), the user query on top (reduced schema). Nothing hands
  # the compiler an unparsed tree any more.
  #
  # A table that declares no filter: at all gets an INERT filter (no schema): no
  # param is read, there is no user query, and #scope returns its argument.
  #
  # PRESETS (`presets:`) are the third kind of host-authored slots: the filter's
  # "Schnellauswahl", which the user toggles on and off in one click. Unlike
  # fixed slots they are not enforced -- they are shortcuts INTO the user part,
  # so they are parsed against the reduced (user) schema and end up in the `f`
  # param like any other user slot. A declaration is either a SLOT PRESET
  # (`{key:, label:, slots:}`), one button carrying its own slots, or a GROUP
  # (`{group:, attribute:, operator:, members:}`), several buttons that share one
  # `attribute in (values)` slot -- one FilterPreset per member, so `#presets` is
  # one flat list of buttons in declaration order either way.
  class Filter
    EMPTY_CATALOG = {attributes: [].freeze}.freeze

    # The operator a group's members share their slot under: each of them is one
    # value of the set.
    GROUP_OPERATOR = "in"
    GROUP_KEYS = %i[group attribute operator members].freeze
    MEMBER_KEYS = %i[key label value icon css_class].freeze
    MEMBER_REQUIRED_KEYS = %i[key label value].freeze

    # `schema` is the dataset's filter schema module and is nil for an inert
    # filter; `user_query` is nil when there is no user part at all (an inert
    # filter, or `policy: :fixed`). `presets` are the policy's quick-select
    # buttons, already built and flat -- a group contributes one per member (a
    # view-declared declaration is built on demand by #preset).
    attr_reader :schema, :fixed_entries, :user_query, :exclude, :presets

    def initialize(schema:, exclude:, bound: nil, user_bound: nil,
      fixed_entries: [], fixed_query: nil, user_query: nil, default_tree: nil,
      presets: [])
      @schema = schema
      @exclude = exclude.freeze
      @bound = bound           # bound schema, FULL -- fixed slots + full_catalog
      @user_bound = user_bound # bound schema, reduced by exclude: -- user part + catalog
      @fixed_entries = fixed_entries.freeze
      @fixed_query = fixed_query
      @user_query = user_query
      @default_tree = default_tree # the policy's `default:` user tree, if any
      @presets = Array(presets).flat_map { |declaration| Array(build_declaration(declaration)) }
        .freeze
      freeze
    end

    # Every fixed slot, whatever its visibility (D8.3: display visibility never
    # influences enforcement).
    def fixed_slots = @fixed_entries.flat_map { |entry| entry[:slots] }

    # Fixed slots the builder renders as locked chips.
    def readonly_slots = slots_with(:readonly)

    # Fixed slots that never reach the view.
    def hidden_slots = slots_with(:hidden)

    def fixed? = @fixed_entries.any?

    # The user's own slots as a tree (what the builder edits).
    def user_slots = @user_query ? @user_query.as_json : []

    # What actually filters the rows, as one tree: fixed slots ahead of the
    # user's (CNF, so the user part can only narrow).
    def effective_slots = fixed_slots + user_slots

    # The catalog the picker renders from (reduced by exclude:), and the wider
    # one that labels fixed conditions using attributes the picker hides.
    def catalog = @user_bound ? @user_bound.catalog : EMPTY_CATALOG

    def full_catalog = @bound ? @bound.catalog : EMPTY_CATALOG

    # THE filtered relation. Fixed slots are compiled with the FULL schema (a
    # pinned condition may legitimately use an excluded attribute), the user
    # query with the reduced one on top; both compiles merge the schema's own
    # base relation, which is where the required joins live.
    def scope(base)
      return base unless @schema

      @schema.compile(@user_query, schema: @user_bound,
        relation: @schema.compile(@fixed_query, schema: @bound, relation: base))
    end

    # The wire form of the USER part (canonical, short keys), "" when empty.
    def wire
      return "" unless @schema && @user_query

      @schema.encode(@user_query, schema: @user_bound).to_s
    end

    # The filter builder's posted JSON tree -> wire form (nil when nothing
    # survives the schema), for the apply redirect.
    def encode_tree(tree)
      @schema&.encode_tree(tree, schema: @user_bound)
    end

    # The wire form of the policy's `default:` tree, "" when the table has no
    # default user filter. This is what the builder's "Filter zurücksetzen"
    # link emits (present, so it beats a remembered filter), so a reset lands
    # on the declared default rather than on "nothing".
    def default_wire
      return "" unless @schema && @default_tree.present?

      @schema.encode_tree(@default_tree, schema: @user_bound).to_s
    end

    # What ONE declaration of the VIEW's (`t.filter presets: [...]`, instead of
    # the policy's) stands for: the Wsjrdp::TableState::FilterPreset of a slot
    # preset, the Array of member ones of a group. Same implementation as the
    # policy's own presets, so both declaration sites parse strictly and compute
    # `active?` / `toggle_wire` by the same rule.
    def preset(**declaration)
      build_declaration(declaration)
    end

    private

    # ONE declaration -> the button(s) it stands for. `group:` is what tells the
    # two forms apart.
    def build_declaration(declaration)
      options = declaration.transform_keys(&:to_sym)
      options.key?(:group) ? build_preset_group(options) : build_preset(**options)
    end

    def slots_with(show)
      @fixed_entries.select { |entry| entry[:show] == show }.flat_map { |entry| entry[:slots] }
    end

    # Preset slots are HOST-authored, exactly like fixed slots, and are therefore
    # parsed STRICTLY -- against the USER-bound schema, because they become user
    # slots and have to be editable in the builder. A typo raises here, which
    # spec/controllers/fin/table_policies_spec.rb turns into a CI failure. The
    # keyword list is the declaration's contract: an unknown key raises here too
    # (ArgumentError, "unknown keyword"), whichever site declared the preset.
    def build_preset(key:, label:, slots:, icon: nil, css_class: nil)
      raise ArgumentError, "filter preset #{key}: the table declares no filter schema" unless @schema

      parsed = @schema.parse_fixed!(slots, schema: @user_bound, what: "filter preset #{key}").as_json
      active = parsed.all? { |slot|
        Wsjrdp::Filtering::SlotEquality.include_slot?(user_slots, slot, aliases: sign_aliases)
      }
      Wsjrdp::TableState::FilterPreset.new(key: key.to_s, label: label.to_s, slots: parsed.freeze,
        active: active, toggle_wire: preset_toggle_wire(parsed, active),
        icon: icon&.to_s, css_class: css_class&.to_s)
    end

    # Turning a preset ON adds the slots the user filter is missing; turning it
    # OFF removes exactly the preset's slots and leaves every other slot alone.
    def preset_toggle_wire(slots, active)
      tree = if active
        Wsjrdp::Filtering::SlotEquality.remove_slots(user_slots, slots, aliases: sign_aliases)
      else
        user_slots +
          Wsjrdp::Filtering::SlotEquality.missing_slots(user_slots, slots, aliases: sign_aliases)
      end
      @schema.encode_tree(tree, schema: @user_bound).to_s
    end

    # A GROUP is host-authored exactly like a slot preset and checked just as
    # strictly, only by hand rather than by Ruby's keywords, so that every
    # message names the group: the attribute must be one the USER-bound schema
    # offers with the GROUP_OPERATOR, and every member value one of that
    # attribute's option values. A typo raises here, which
    # spec/controllers/fin/table_policies_spec.rb turns into a CI failure.
    def build_preset_group(declaration)
      what = "filter preset group #{declaration[:group]}"
      raise ArgumentError, "#{what}: the table declares no filter schema" unless @schema

      check_keys!(what, declaration, GROUP_KEYS, GROUP_KEYS)
      attribute = declaration[:attribute].to_s
      offered = attribute_values!(what, attribute, declaration[:operator])
      members = group_members(what, declaration[:members], offered)
      values = members.map { |member| member[:value].to_s }.freeze
      members.map { |member| build_group_member(declaration[:group], attribute, member, values) }
    end

    # The option values the group's members may name, or a raised ArgumentError:
    # a group shares ONE `attribute in (values)` slot, so any other operator is a
    # declaration mistake, as is an attribute the user's schema does not carry or
    # does not offer the operator on.
    def attribute_values!(what, attribute, operator)
      unless operator.to_s == GROUP_OPERATOR
        raise ArgumentError, "#{what}: operator #{operator.to_s.inspect} -- the members of a " \
                             "group share one #{GROUP_OPERATOR.inspect} slot"
      end

      values = @user_bound&.preset_group_values(attribute)
      return values if values

      raise ArgumentError, "#{what}: attribute #{attribute.inspect} is unknown or does not " \
                           "accept the #{GROUP_OPERATOR.inspect} operator"
    end

    # The members as symbol-keyed Hashes, each checked against the declaration's
    # contract: its keys, its value, and both its key and its value unique within
    # the group -- two buttons standing for the same thing is a mistake, and the
    # two would toggle each other.
    def group_members(what, members, offered)
      parsed = Array(members).map { |member| member.transform_keys(&:to_sym) }
      parsed.each do |member|
        check_keys!(what, member, MEMBER_KEYS, MEMBER_REQUIRED_KEYS)
        next if offered.include?(member[:value].to_s)

        raise ArgumentError, "#{what}: member #{member[:key]} has the value " \
                             "#{member[:value].to_s.inspect}, which the attribute does not offer"
      end
      check_unique!(what, parsed)
      parsed
    end

    def check_keys!(what, declaration, allowed, required)
      unknown = declaration.keys - allowed
      raise ArgumentError, "#{what}: unknown keyword: #{unknown.first.inspect}" if unknown.any?

      missing = required - declaration.keys
      raise ArgumentError, "#{what}: missing keyword: #{missing.first.inspect}" if missing.any?
    end

    def check_unique!(what, members)
      %i[key value].each do |field|
        taken = members.map { |member| member[field].to_s }
        duplicate = taken.find { |value| taken.count(value) > 1 }
        next unless duplicate

        raise ArgumentError, "#{what}: duplicate member #{field} #{duplicate.inspect}"
      end
    end

    def build_group_member(group, attribute, member, values)
      value = member[:value].to_s
      active = group_slots(attribute).any? { |slot| group_slot_values(slot).include?(value) }
      Wsjrdp::TableState::FilterPreset.new(key: member[:key].to_s, label: member[:label].to_s,
        slots: nil, active: active,
        toggle_wire: group_member_toggle_wire(attribute, value, active),
        icon: member[:icon]&.to_s, css_class: member[:css_class]&.to_s,
        group: group.to_s, attribute: attribute, value: value, group_values: values)
    end

    # THE slots a group speaks for: a user slot of EXACTLY ONE condition, on the
    # group's attribute and under the GROUP_OPERATOR. A slot with a further OR
    # condition asks a wider question and another operator a different one --
    # neither is ever read as the group's, and neither is ever changed by a
    # member's toggle. Fixed slots are out of reach anyway: `user_slots` is the
    # user half alone.
    def group_slots(attribute)
      user_slots.select { |slot| group_slot?(slot, attribute) }
    end

    def group_slot?(slot, attribute)
      conditions = Array(slot)
      return false unless conditions.size == 1

      key, operator, * = Array(conditions.first)
      key.to_s == attribute && operator.to_s == GROUP_OPERATOR
    end

    # The operand set of such a slot, as Strings -- a wire operand may well be a
    # number, a declared value is text.
    def group_slot_values(slot) = Array(Array(slot).first).drop(2).map(&:to_s)

    # Selecting a member adds its value to every slot of the group that lacks it,
    # last and leaving the other values alone, and appends `attribute in (value)`
    # as a new slot when the filter carries no slot of the group at all.
    # Deselecting takes the value out of every slot of the group; a slot left
    # without a value goes altogether.
    def group_member_toggle_wire(attribute, value, active)
      tree = active ? group_slots_without(attribute, value) : group_slots_with(attribute, value)
      @schema.encode_tree(tree, schema: @user_bound).to_s
    end

    def group_slots_with(attribute, value)
      found = false
      tree = user_slots.map { |slot|
        next slot unless group_slot?(slot, attribute)

        found = true
        group_slot_values(slot).include?(value) ? slot : [Array(Array(slot).first) + [value]]
      }
      found ? tree : tree + [[[attribute, GROUP_OPERATOR, value]]]
    end

    def group_slots_without(attribute, value)
      user_slots.filter_map { |slot|
        next slot unless group_slot?(slot, attribute)

        condition = Array(Array(slot).first)
        kept = condition.drop(2).reject { |operand| operand.to_s == value }
        [condition.first(2) + kept] if kept.any?
      }
    end

    # The user schema's sign pairs, {signed key => absolute key}: by these a
    # preset on a magnitude counts a sign-invariant condition on the signed twin
    # as its own -- `Saldo ≠ 0` IS `|Saldo| ≠ 0` (Wsjrdp::Filtering::SlotEquality).
    # Computed per call, because a view-declared preset is built after #freeze.
    def sign_aliases = @user_bound&.sign_aliases || {}
  end

  # The column set of THIS table (D2b): the dataset's column description -- the
  # policy's codec, one per dataset however many tables show it -- minus the
  # columns this table does not have (`cols: {exclude:}`), plus the names it
  # gives some of the rest (`cols: {labels:}`).
  #
  # Both may be lambdas (the Moss list serves five routes, and each kind tab has
  # other columns), so this is a per-REQUEST value: the resolver builds it, the
  # state carries it, and the widget reads it from there like every other piece
  # of the state (D8.4). An excluded column is out of the ALLOW-LIST too, so a
  # hand-written ?c= / ?s= or a stale store entry naming one is dropped exactly
  # like an unknown token (D8.5) -- it is not a column of this table.
  class ColumnSet
    attr_reader :keys, :excluded, :labels

    def initialize(policy, excluded:, labels:)
      @policy = policy
      @excluded = excluded.freeze
      @labels = labels.freeze
      @keys = policy.column_keys.reject { |key| @excluded.include?(key) }.freeze
      freeze
    end

    # A wire token (an abbreviation or the long key) -> the long key of a column
    # this table HAS, or nil.
    def key_for(token)
      key = @policy.key_for(token)
      key unless key.nil? || excluded?(key)
    end

    def key?(key) = @keys.include?(key.to_s)

    def excluded?(key) = @excluded.include?(key.to_s)

    # The name this table gives a column, or nil when the description's own
    # label stands.
    def label(key) = @labels[key.to_s]
  end

  attr_reader :policy, :sort_list, :column_states, :per_page, :per_value, :page,
    :open_keys, :filter, :pane, :level, :store_key, :sources

  def initialize(policy:, store_key:, columns:, sort_list:, column_states:, per_page:, per_value:,
    page:, open_keys:, filter:, pane:, level:, sources:)
    @policy = policy
    @store_key = store_key
    @columns = columns
    @sort_list = sort_list.map { |pair| pair.map(&:to_s).freeze }.freeze
    @column_states = column_states.map { |key, active| [key.to_s, !!active].freeze }.freeze
    @per_page = per_page
    @per_value = per_value.to_s
    @page = page
    @open_keys = open_keys.to_set.freeze
    @filter = filter
    @pane = pane
    @level = level
    @sources = sources.freeze
    freeze
  end

  def self.resolve(policy, params:, stores: {}, controller: nil)
    Resolver.new(policy, params: params, stores: stores, controller: controller).state
  end

  def prefix = @policy.prefix

  def visible_column_keys = @column_states.filter_map { |key, active| key if active }

  # --- the column set of THIS table (the policy's `cols: exclude:` / `labels:`)
  #
  # A dataset's columns are described ONCE (Wsjrdp::ExpandableTableColumns), and
  # the view keeps handing the widget that full description. What a table makes
  # of it -- which of the columns it has, and what it calls them -- is part of
  # the controller's declaration and is therefore read from the STATE, like every
  # other piece of it (D8.4). See ColumnSet above.

  # The label this table gives a column: its `cols: {labels:}` override, else
  # `fallback` (normally the column description's own label).
  def column_label(key, fallback = nil) = @columns.label(key) || fallback

  # The widget's column config Hashes, shaped for this table: the columns it
  # excludes dropped -- they are neither rendered nor offered in the picker --
  # and its own labels applied to the header, the condensed header and the picker
  # alike. An excluded column cannot come back through a param or a store entry
  # either (ColumnSet#key_for).
  def column_configs(configs)
    configs.filter_map do |config|
      key = config[:key].to_s
      next if @columns.excluded?(key)

      label = column_label(key)
      next config unless label

      config.merge(label: label, condensed_label: (label if config[:condensed_label]))
    end
  end

  # The concrete query-param name of a field: param_name(:sort) => "bks".
  def param_name(field) = @policy.param_name(field)

  def reset_param = @policy.reset_param

  # Where the value came from: :fixed, :url, :store or :default. One user left:
  # #wire_params, which re-emits exactly the :url fields. (The filter's
  # "nobody chose anything yet" case is the resolver's own business now -- the
  # policy's `default:` tree applies on the :default path and nowhere else.) The
  # widget never asks: what it renders must not depend on where a value came from.
  def source(field) = @sources[field.to_sym]

  def fixed?(field) = @policy.field(field).fixed?

  # The wire (URL / store) form of a resolved field, "" when the field is empty.
  def wire(field)
    case field.to_sym
    when :sort then Wsjrdp::ExpandableTableSort.encode(sort_list.map { |key, dir| [@policy.abbr_for(key), dir] }).to_s
    when :cols then encode_column_states(@column_states)
    when :filter then @filter.wire
    when :per_page then @per_value
    when :page then @page.to_s
    when :open then @open_keys.to_a.join(",")
    when :pane then @pane ? "1" : "0"
    when :level then @level.to_s
    else raise ArgumentError, "unknown table state field #{field.inspect}"
    end
  end

  # {param_name => wire} for every field the USER chose in this URL -- what a
  # redirect (a connect action, a "back to the list" link) must re-emit to
  # reproduce this table's view. Fixed fields need no carrying (the controller
  # fixes them again), remembered ones restore themselves from the store, and
  # `level` belongs to one lazy detail's frame URL, never to a page link.
  def wire_params(except: [])
    skip = Array(except).map(&:to_sym) + [:level]
    Wsjrdp::TableStatePolicy::FIELDS.each_with_object({}) do |field, params|
      next if skip.include?(field) || source(field) != :url
      value = wire(field)
      params[param_name(field)] = value unless value.empty?
    end
  end

  # The wire token of a column key (its abbreviation), for the sort/cols params.
  def column_token(key) = @policy.abbr_for(key)

  # The long column key of a wire token, or nil when this table has no such
  # column (an unknown token, or one this table excludes).
  def column_key(token) = @columns.key_for(token)

  def encode_sort_list(list)
    Wsjrdp::ExpandableTableSort.encode(list.map { |key, dir| [@policy.abbr_for(key), dir] }).to_s
  end

  def encode_column_states(states)
    states.map { |key, active| "#{active ? "" : "~"}#{@policy.abbr_for(key)}" }.join(",")
  end

  # The cookie a JS-written field (D2d: only `pane` today) lives in. The widget
  # hands the name to the JS as a data- attribute; the controller reads it back
  # through the same resolver and allow-list as any other input.
  def cookie_name(field)
    Wsjrdp::TableStateStore::Cookie.cookie_name(@store_key, @policy.field(field).short)
  end

  # The internal limit behind `per_page == :all`. A PRIVATE detail of #paginate:
  # code and policies speak of :all, and the wire form is "all" -- the big number
  # never leaves this class.
  ALL_PER = 1_000_000
  private_constant :ALL_PER

  # THE paging of a table: the current page of `source` -- an ActiveRecord
  # relation or a plain Array -- at this table's resolved page size.
  #
  # One method, because both special cases belong together: `per_page == :all`
  # (one page holding everything) and D4's clamp -- a remembered page beyond the
  # last one falls back to page 1, so coming back through a tab never lands on an
  # empty table. Kaminari answers the clamp for both kinds of source, since
  # #page/#per on a paginated Array behave like they do on a relation.
  def paginate(source)
    scope = source.is_a?(Array) ? Kaminari.paginate_array(source) : source
    per = (@per_page == :all) ? ALL_PER : @per_page
    paged = scope.page(@page).per(per)
    paged.out_of_range? ? scope.page(1).per(per) : paged
  end

  # Turns params + store + declaration into the frozen state, in ONE place and in
  # ONE order (D8.1): fixed > URL > store > default. For a :fixed field the value
  # comes from the policy and neither the param nor the store is looked at, so
  # there is no code path from user input to a fixed field.
  class Resolver
    def initialize(policy, params:, stores:, controller: nil)
      @policy = policy
      @params = params
      @stores = stores || {}
      @controller = controller
      @store_key = policy.store_key_for(controller) if controller
      @store_key ||= policy.prefix
      @columns = build_column_set
      @sources = {}
      @stored = {}
    end

    def state
      resolved = build(Wsjrdp::TableStatePolicy::FIELDS.to_h { |field| [field, resolve(field)] })
      write_back(resolved)
      resolved
    end

    private

    # The columns THIS table has, and its names for them (D2b). `cols:
    # {exclude:, labels:}` may be lambdas -- one declaration can serve several
    # routes -- so they are evaluated here, per request, and checked exactly like
    # the plain declaration the policy checks at load time.
    def build_column_set
      options = @policy.field(:cols).options
      Wsjrdp::TableState::ColumnSet.new(@policy,
        excluded: @policy.excluded_columns(@policy.evaluate(options[:exclude], @controller)),
        labels: @policy.column_labels(@policy.evaluate(options[:labels], @controller)))
    end

    def build(values)
      Wsjrdp::TableState.new(policy: @policy, store_key: @store_key, columns: @columns,
        sort_list: values[:sort], column_states: values[:cols],
        per_page: values[:per_page][0], per_value: values[:per_page][1],
        page: values[:page], open_keys: values[:open], filter: values[:filter],
        pane: values[:pane], level: values[:level], sources: @sources)
    end

    # fixed > URL > store > default (D1). A param that is PRESENT but blank is an
    # explicit "empty" (the column picker's "Standard-Spalten" link, a sort
    # clicked off) and therefore beats the store; only an ABSENT param falls
    # through to the remembered value.
    def resolve(field)
      policy_field = @policy.field(field)
      return fixed_value(field, policy_field) if policy_field.fixed?

      name = @policy.param_name(field)
      if @params.key?(name)
        @sources[field] = :url
        return parse(field, @params[name].to_s, policy_field)
      end
      if policy_field.remember? && (raw = stored_value(policy_field))
        @sources[field] = :store
        return parse(field, raw.to_s, policy_field)
      end
      @sources[field] = :default
      default_value(field, policy_field)
    end

    def fixed_value(field, policy_field)
      @sources[field] = :fixed
      default_value(field, policy_field)
    end

    def stored_value(policy_field)
      store = @stores[@policy.store_for(policy_field.name)]
      return nil unless store
      @stored[policy_field.name] = store
      (store.read(@store_key) || {})[policy_field.short]
    end

    # Only :remember, non-fixed fields are written back, with the RESOLVED (and
    # therefore allow-listed) value (D8.6). A value equal to the field's default
    # is dropped instead of stored, so the session stays small and "remembered"
    # means "differs from the default".
    def write_back(resolved)
      per_store = Hash.new { |hash, key| hash[key] = {} }
      Wsjrdp::TableStatePolicy::FIELDS.each do |field|
        policy_field = @policy.field(field)
        next unless policy_field.remember? && !policy_field.fixed?
        store = @stores[@policy.store_for(field)]
        next unless store
        per_store[store] # touch: a store is written even when nothing differs from
        #   the defaults, so an explicit "back to default" (?f=) REPLACES a
        #   remembered entry instead of leaving it behind
        value = resolved.wire(field)
        per_store[store][policy_field.short] = value unless value == default_state.wire(field)
      end
      per_store.each { |store, hash| store.write(@store_key, hash) }
    end

    # The same table with nothing chosen -- the yardstick for "is this value
    # worth remembering?".
    def default_state
      @default_state ||= build(Wsjrdp::TableStatePolicy::FIELDS.to_h { |field|
        [field, default_value(field, @policy.field(field))]
      })
    end

    # --- per-field parsing (the allow-lists of D8.5) ---------------------------

    def parse(field, raw, policy_field)
      send(:"parse_#{field}", raw, policy_field)
    end

    def default_value(field, policy_field)
      send(:"default_#{field}", @policy.evaluate(policy_field.default, @controller), policy_field)
    end

    # The column allow-list is the table's OWN column set: a column this table
    # does not have cannot be sorted by or shown, whether the token arrived in
    # the URL, from the store or (for a sort) from the policy's default.
    def parse_sort(raw, _policy_field)
      Wsjrdp::ExpandableTableSort.decode(raw).filter_map do |token, dir|
        key = @columns.key_for(token)
        key ? [key, dir] : nil
      end
    end

    def default_sort(value, _policy_field)
      Array(value).filter_map do |key, dir|
        @columns.key?(key) ? [key.to_s, (dir.presence || "asc").to_s] : nil
      end
    end

    # Ordered [key, active] pairs over the policy's columns: the param decides
    # order + visibility, anything it does not mention is appended hidden
    # (forward-compatible with newly added columns).
    def parse_cols(raw, policy_field)
      return default_cols(@policy.evaluate(policy_field.default, @controller), policy_field) if raw.strip.empty?

      decoded = raw.split(",").filter_map do |token|
        token = token.strip
        next if token.empty?
        active = !token.start_with?("~")
        key = @columns.key_for(active ? token : token[1..])
        key ? [key, active] : nil
      end
      seen = decoded.map(&:first).to_set
      decoded + @columns.keys.reject { |key| seen.include?(key) }.map { |key| [key, false] }
    end

    def default_cols(value, _policy_field)
      shown = value.nil? ? nil : Array(value).map(&:to_s)
      return @columns.keys.map { |key| [key, true] } if shown.nil?

      # Host-authored like the exclusion itself, so the two are held to the same
      # rule here as a plain declaration is at load time.
      @policy.validate_cols_default!(shown, @columns.excluded)
      # The declared order IS the column order (a kind tab may want its own
      # column first); every other column of the set follows, hidden.
      shown = shown.select { |key| @columns.key?(key) }
      shown.map { |key| [key, true] } + (@columns.keys - shown).map { |key| [key, false] }
    end

    # [per_page, per_value]: the SYMBOL :all lifts the limit (what
    # Wsjrdp::TableState#paginate turns into one page with everything), anything
    # else is a capped Integer. The wire form of :all stays the string "all",
    # both in the URL and in the select.
    def parse_per_page(raw, policy_field)
      return [:all, "all"] if raw.strip == "all"
      per = raw.to_i
      return default_per_page(@policy.evaluate(policy_field.default, @controller), policy_field) if per <= 0
      per = [per, max_per(policy_field)].min
      [per, per.to_s]
    end

    def default_per_page(value, policy_field)
      return [:all, "all"] if value.to_s == "all"
      per = value.to_i
      per = DEFAULT_PER unless per.positive?
      per = [per, max_per(policy_field)].min
      [per, per.to_s]
    end

    def max_per(policy_field) = policy_field.options[:max] || DEFAULT_MAX_PER

    def parse_page(raw, policy_field)
      page = raw.to_i
      page.positive? ? page : default_page(@policy.evaluate(policy_field.default, @controller), policy_field)
    end

    def default_page(value, _policy_field)
      page = value.to_i
      page.positive? ? page : 1
    end

    # Row keys are opaque tokens; "," is their separator, so a key can never
    # contain one. The count is bounded so a hand-written URL cannot grow without
    # limit.
    def parse_open(raw, _policy_field)
      raw.split(",").map(&:strip).reject(&:empty?).uniq.first(MAX_OPEN_KEYS).to_set
    end

    def default_open(value, _policy_field)
      Array(value).map(&:to_s).to_set
    end

    def parse_level(raw, policy_field)
      level = raw.to_i
      level.positive? ? [level, MAX_LEVEL].min : default_level(@policy.evaluate(policy_field.default, @controller), policy_field)
    end

    def default_level(value, _policy_field)
      value.to_i.clamp(0, MAX_LEVEL)
    end

    def parse_pane(raw, policy_field)
      case raw.strip
      when "1", "true" then true
      when "0", "false" then false
      else default_pane(@policy.evaluate(policy_field.default, @controller), policy_field)
      end
    end

    def default_pane(value, _policy_field)
      %w[1 true].include?(value.to_s)
    end

    # D2e: the fixed slots always come from the policy; the user part only from
    # the param / store, and only when the field is not entirely :fixed. `raw` is
    # the param / store value (a String, possibly blank).
    def parse_filter(raw, policy_field)
      build_filter(policy_field, user: raw)
    end

    # `value` is the policy's `default:`: the user TREE shown when neither the
    # param nor the store provided one.
    def default_filter(value, policy_field)
      build_filter(policy_field, default_tree: value)
    end

    def build_filter(policy_field, user: nil, default_tree: nil)
      # The dataset comes from the DECLARATION only -- never from params, the
      # store or a cookie (Wsjrdp::TableStatePolicy#validate_filter_schema!).
      schema = policy_field.options[:schema]
      exclude = filter_exclude(policy_field)
      return Wsjrdp::TableState::Filter.new(schema: nil, exclude: exclude) unless schema

      # Bound here, once per resolve -- never at class load, so a schema can
      # depend on the request and the strict check below runs per request.
      bound = filter_bound(schema)
      user_bound = exclude.empty? ? bound : filter_bound(schema, exclude)
      entries, fixed_query = filter_fixed(policy_field, schema, bound)
      Wsjrdp::TableState::Filter.new(schema: schema, exclude: exclude,
        bound: bound, user_bound: user_bound,
        fixed_entries: entries, fixed_query: fixed_query,
        user_query: filter_user_query(policy_field, schema, user_bound, user, default_tree),
        default_tree: @policy.evaluate(policy_field.default, @controller),
        presets: Array(@policy.evaluate(policy_field.options[:presets], @controller)))
    end

    def filter_bound(schema, except = nil)
      @filter_bounds ||= {}
      @filter_bounds[except] ||= schema.bound(except: except)
    end

    # The policy's fixed entries plus the ONE strictly parsed query over all
    # their slots. Parsed against the FULL bound schema: a pinned condition may
    # legitimately use an attribute the user's picker does not offer.
    def filter_fixed(policy_field, schema, bound)
      entries = Array(@policy.evaluate(policy_field.options[:fixed], @controller)).map { |entry|
        slots = Array(@policy.evaluate(entry[:slots], @controller))
        {slots: slots.freeze, show: (entry[:show] || :readonly).to_sym}.freeze
      }.freeze
      slots = entries.flat_map { |entry| entry[:slots] }
      [entries, slots.empty? ? nil : schema.parse_fixed!(slots, schema: bound)]
    end

    # The user's half. `:fixed` means "fixed slots only": no user query at all.
    # A param / store value is decoded TOLERANTLY against the reduced schema, so
    # an excluded attribute is dropped whichever path it came in through. The
    # `default:` tree is host-authored like a fixed slot and therefore parsed
    # STRICTLY -- against the reduced schema, because it IS the user part and has
    # to be editable in the builder.
    def filter_user_query(policy_field, schema, user_bound, raw, default_tree)
      return nil if policy_field.fixed?
      return schema.decode(raw, schema: user_bound) unless raw.nil?
      return nil if default_tree.blank?

      schema.parse_fixed!(default_tree, schema: user_bound, what: "filter default tree")
    end

    def filter_exclude(policy_field)
      Array(@policy.evaluate(policy_field.options[:exclude], @controller)).map(&:to_sym).freeze
    end

    DEFAULT_PER = 50
    DEFAULT_MAX_PER = 500
    MAX_OPEN_KEYS = 200
    MAX_LEVEL = 10
  end
end
