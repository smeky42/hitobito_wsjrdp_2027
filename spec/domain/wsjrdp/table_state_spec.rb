# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Deliberately standalone (no rails spec_helper): the table state is pure value
# logic over a params Hash and a store object -- the spec needs neither the app
# nor a database. Runs from the wagon root:
#
#   bundle exec rspec spec/domain/wsjrdp/table_state_spec.rb
require "json"
require "active_support"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/numeric/time"
require "active_support/core_ext/enumerable"

module Wsjrdp; end
require_relative "../../../app/domain/wsjrdp/filtering/slot_equality"
require_relative "../../../app/domain/wsjrdp/expandable_table_sort"
require_relative "../../../app/domain/wsjrdp/table_state_policy"
require_relative "../../../app/domain/wsjrdp/table_state_store"
require_relative "../../../app/domain/wsjrdp/table_state_store/session"
require_relative "../../../app/domain/wsjrdp/table_state_store/cookie"
require_relative "../../../app/domain/wsjrdp/table_state"

# A minimal stand-in for the controller: the resolver only needs the two names
# that make up the default store key, plus instance_exec for lambdas.
FakeController = Struct.new(:controller_path, :action_name)

# Cookie jar double: behaves like ActionDispatch's jar for the three things the
# cookie store uses (to_h, []=, delete).
class FakeCookieJar
  def initialize(values = {}) = @values = values.transform_keys(&:to_s)

  def to_h = @values.dup

  def [](name) = @values[name.to_s]

  def []=(name, value)
    @values[name.to_s] = value.is_a?(Hash) ? value[:value].to_s : value.to_s
  end

  def delete(name, **) = @values.delete(name.to_s)
end

# Minimal stand-ins for Kaminari, the only thing #paginate talks to: a paged
# scope that remembers what .page / .per were called with and answers
# #out_of_range? from the row count, plus the array paginator that wraps a plain
# Array in one.
class FakePagedScope
  attr_reader :page_number, :per_size

  def initialize(total, page_number: nil, per_size: nil)
    @total = total
    @page_number = page_number
    @per_size = per_size
  end

  def page(number) = self.class.new(@total, page_number: number, per_size: @per_size)

  def per(size) = self.class.new(@total, page_number: @page_number, per_size: size)

  def out_of_range? = page_number.to_i > 1 && ((page_number.to_i - 1) * per_size.to_i) >= @total
end

FakeKaminari = Module.new do
  def self.paginate_array(array) = FakePagedScope.new(array.size)
end

COLUMNS = {
  "booking_date" => "bdt",
  "signed_base_amount" => "amt",
  "posting_text" => "posting_text",
  "cost_center_number" => "cc"
}.freeze

# A stand-in for a dataset filter schema module (Wsjrdp::Filtering::FilterSchema),
# so the filter half of the state stays testable without a schema, a database or
# Arel.
# It reproduces the property that matters -- the SAME tolerant/strict split as
# the real protocol -- and records every #compile call with the schema it was
# given, which is how the spec proves the order and the two schemas of #scope.
#
# Its wire form is simply the JSON of the tree; `known` is its "schema".
class FakeFilterSchema
  Query = Struct.new(:slots) do
    def as_json(*) = slots
  end

  # `sign_aliases` is the bound schema's sign PAIRS, {signed key => absolute
  # key} -- what the preset code hands Wsjrdp::Filtering::SlotEquality.
  # `options` are the attributes a preset GROUP can be declared on, with their
  # option values.
  Schema = Struct.new(:name, :known, :sign_aliases, :options) do
    def catalog = {attributes: known.map { |key| {key: key} }}

    # Wsjrdp::Filtering::BoundSchema#preset_group_values: the values a preset
    # group may name on this attribute, nil when this binding does not carry the
    # attribute or the attribute does not accept the `in` operator -- which here
    # is every attribute the OPTIONS Hash does not name.
    def preset_group_values(key)
      options[key.to_s] if known.include?(key.to_s)
    end
  end

  KNOWN = %w[konto booking_date cost_center accounting_entry sphere
    balance balance_abs kind].freeze

  SIGN_ALIASES = {"balance" => "balance_abs"}.freeze

  OPTIONS = {"kind" => %w[card invoice refund], "sphere" => %w[one two]}.freeze

  attr_reader :compiled

  def initialize(known: KNOWN)
    @known = known.map(&:to_s)
    @compiled = []
  end

  def bound(except: nil)
    dropped = Array(except).map(&:to_s)
    kept = @known - dropped
    aliases = SIGN_ALIASES.select { |signed, absolute| kept.include?(signed) && kept.include?(absolute) }
    Schema.new(dropped.any? ? "reduced" : "full", kept, aliases, OPTIONS)
  end

  # TOLERANT: unknown attributes are dropped, garbage yields the empty query.
  def decode(raw, schema:)
    Query.new(keep_known(parse_json(raw), schema))
  end

  def encode(query, schema:)
    slots = keep_known(query.slots, schema)
    slots.empty? ? nil : JSON.generate(slots)
  end

  def encode_tree(tree, schema:) = encode(Query.new(Array(tree)), schema: schema)

  # STRICT: anything the schema does not know raises, naming attribute,
  # operator and slot index -- like the real parse_fixed!.
  def parse_fixed!(tree, schema:, what: "fixed slot")
    slots = Array(tree)
    raise ArgumentError, "#{what}: empty filter tree" if slots.empty?

    slots.each_with_index do |slot, index|
      raise ArgumentError, "#{what} #{index}: slot without conditions" if Array(slot).empty?

      Array(slot).each do |attribute, operator, *|
        next if schema.known.include?(attribute.to_s)

        raise ArgumentError, "#{what} #{index}: unknown attribute #{attribute.inspect} " \
                             "(operator #{operator.inspect})"
      end
    end
    Query.new(slots)
  end

  # The "relation" is a String, so the spec can read the whole chain back.
  def compile(query, schema:, relation:)
    @compiled << {slots: query&.slots, schema: schema.name, relation: relation}
    return "#{relation}+#{schema.name}base" if query.nil?

    "#{relation}|#{schema.name}:#{JSON.generate(query.slots)}"
  end

  private

  def parse_json(raw)
    Array(JSON.parse(raw.to_s))
  rescue JSON::ParserError
    []
  end

  def keep_known(slots, schema)
    Array(slots).filter_map do |slot|
      Array(slot).select { |condition| schema.known.include?(condition.first.to_s) }.presence
    end
  end
end

# One user condition and its wire form in the fake schema's dialect.
KONTO_TREE = [[["konto", "in", "41030"]]].freeze
KONTO_WIRE = JSON.generate(KONTO_TREE)

describe Wsjrdp::TableStatePolicy do
  it "names params as <prefix><short>" do
    policy = described_class.new(prefix: "bk")
    expect(policy.param_name(:sort)).to eq("bks")
    expect(policy.param_name(:cols)).to eq("bkc")
    expect(policy.param_name(:filter)).to eq("bkf")
    expect(policy.param_name(:per_page)).to eq("bkz")
    expect(policy.param_name(:page)).to eq("bkp")
    expect(policy.param_name(:open)).to eq("bko")
    expect(policy.param_name(:level)).to eq("expandable_table_level") # SHARED_PARAMS
    expect(policy.param_name(:pane)).to eq("bke")
    expect(policy.reset_param).to eq("bkr")
  end

  it "gives bare letters for the empty prefix" do
    policy = described_class.new(prefix: "")
    expect(policy.param_name(:sort)).to eq("s")
    expect(policy.reset_param).to eq("r")
  end

  # A namespaced param is <prefix><short>, so its short has to stay ONE unique
  # letter: that is what makes P1 + x == P2 + y force P1 == P2.
  it "uses one letter per namespaced field, uniquely" do
    namespaced = described_class::FIELD_DEFINITIONS.except(*described_class::SHARED_PARAMS)
    shorts = namespaced.values.pluck(:short)

    expect(shorts.map(&:length).uniq).to eq([1])
    expect(shorts.uniq.size).to eq(shorts.size)
    expect(shorts).not_to include(described_class::RESET_SHORT)
  end

  # A SHARED_PARAMS field is never concatenated with a prefix, so the one-letter
  # argument does not apply to it -- but it must not be mistakable for a param
  # that IS namespaced. A prefix is [a-z]* and a short one letter, so every
  # namespaced param matches /\A[a-z]+\z/; staying outside that shape settles it.
  it "keeps a shared param out of the <prefix><short> namespace" do
    namespaced_shape = /\A[a-z]+\z/

    described_class::SHARED_PARAMS.each do |name|
      short = described_class::FIELD_DEFINITIONS.fetch(name)[:short]

      expect(short).not_to match(namespaced_shape)
      expect(short.length).to be > 1
    end
  end

  it "applies the D6 default policies" do
    policy = described_class.new(prefix: "")
    expect(policy.field(:sort).policy).to eq(:remember)
    expect(policy.field(:cols).policy).to eq(:remember)
    expect(policy.field(:per_page).policy).to eq(:remember)
    expect(policy.field(:page).policy).to eq(:remember)
    expect(policy.field(:filter).policy).to eq(:url)
    expect(policy.field(:open).policy).to eq(:url)
  end

  it "accepts a bare symbol as the policy shorthand" do
    policy = described_class.new(prefix: "", sort: :url)
    expect(policy.field(:sort).policy).to eq(:url)
  end

  it "insists on a filter schema: as soon as any filter option is declared" do
    expect { described_class.new(prefix: "", filter: :remember) }
      .to raise_error(ArgumentError, /needs a schema:/)
    expect { described_class.new(prefix: "", filter: {exclude: %i[sphere]}) }
      .to raise_error(ArgumentError, /needs a schema:/)
    expect { described_class.new(prefix: "", filter: {policy: :remember, schema: FakeFilterSchema.new}) }
      .not_to raise_error
  end

  it "stores the pane in the cookie store by default" do
    policy = described_class.new(prefix: "")
    expect(policy.store_for(:pane)).to eq(:cookie)
    expect(policy.store_for(:sort)).to eq(:session)
  end

  it "rejects unknown fields" do
    expect { described_class.new(prefix: "", sortt: {}) }.to raise_error(ArgumentError, /sortt/)
  end

  it "rejects a remembered open field (D4)" do
    expect { described_class.new(prefix: "", open: :remember) }.to raise_error(ArgumentError, /cannot be remembered/)
  end

  it "rejects an unknown policy" do
    expect { described_class.new(prefix: "", sort: {policy: :magic}) }.to raise_error(ArgumentError, /magic/)
  end

  it "rejects a prefix that is not plain letters" do
    expect { described_class.new(prefix: "bk_") }.to raise_error(ArgumentError, /prefix/)
  end

  it "rejects column tokens containing a list separator" do
    expect { described_class.new(prefix: "", columns: {"a" => "b,c"}) }.to raise_error(ArgumentError, /token/)
  end

  it "maps column keys and abbreviations both ways" do
    policy = described_class.new(prefix: "", columns: COLUMNS)
    expect(policy.abbr_for("booking_date")).to eq("bdt")
    expect(policy.key_for("bdt")).to eq("booking_date")
    expect(policy.key_for("booking_date")).to eq("booking_date")
    expect(policy.key_for("nope")).to be_nil
  end

  # One dataset, one column description -- but a table may not HAVE every column
  # of it, and may call one of them something else (`cols: {exclude:, labels:}`).
  # A PLAIN declaration is checked here, when the class loads; a lambda one is
  # checked in the resolver (below), which is where it is evaluated.
  describe "the table's own column set (cols: exclude: / labels:)" do
    it "raises for an excluded key that is not a column of the codec" do
      expect { described_class.new(prefix: "", columns: COLUMNS, cols: {exclude: %w[booking_date typo]}) }
        .to raise_error(ArgumentError, /cols: exclude: "typo" is not a column/)
    end

    it "raises for a relabelled key that is not a column of the codec" do
      expect { described_class.new(prefix: "", columns: COLUMNS, cols: {labels: {"typo" => "X"}}) }
        .to raise_error(ArgumentError, /cols: labels: "typo" is not a column/)
    end

    it "raises when a default column is excluded as well" do
      expect {
        described_class.new(prefix: "", columns: COLUMNS,
          cols: {default: %w[booking_date posting_text], exclude: %w[posting_text]})
      }.to raise_error(ArgumentError, /default column\(s\) posting_text are excluded/)
    end

    it "leaves a request-dependent shaping to the resolver" do
      expect { described_class.new(prefix: "", columns: COLUMNS, cols: {exclude: -> { %w[typo] }}) }
        .not_to raise_error
    end
  end

  it "builds the default store key from controller, action and prefix" do
    controller = FakeController.new("fin/bookings", "index")
    expect(described_class.new(prefix: "").store_key_for(controller)).to eq("fin/bookings#index")
    expect(described_class.new(prefix: "bk").store_key_for(controller)).to eq("fin/bookings#index|bk")
  end

  it "evaluates a lambda store key on the controller" do
    controller = FakeController.new("fin/cost_centers", "show")
    policy = described_class.new(prefix: "", store_key: -> { "#{controller_path}##{action_name}:42" })
    expect(policy.store_key_for(controller)).to eq("fin/cost_centers#show:42")
  end
end

describe Wsjrdp::TableState do
  let(:controller) { FakeController.new("fin/bookings", "index") }
  let(:session) { {} }
  let(:cookies) { FakeCookieJar.new }
  let(:stores) do
    {session: Wsjrdp::TableStateStore::Session.new(session),
     cookie: Wsjrdp::TableStateStore::Cookie.new(cookies)}
  end

  let(:filter_schema) { FakeFilterSchema.new }

  def policy(**options)
    Wsjrdp::TableStatePolicy.new(prefix: "", columns: COLUMNS, **options)
  end

  # The same table with a filter on the fake dataset (remembered by default, so
  # the store path is exercised as readily as the URL one).
  def filter_policy(policy: :remember, **options)
    self.policy(filter: {policy: policy, schema: filter_schema, **options})
  end

  def resolve(policy, params = {})
    described_class.resolve(policy, params: params, stores: stores, controller: controller)
  end

  describe "defaults" do
    it "resolves the declared defaults with long names" do
      state = resolve(policy(sort: {default: [["booking_date", "desc"]]},
        cols: {default: %w[booking_date posting_text]}, per_page: {default: 25}))
      expect(state.sort_list).to eq([["booking_date", "desc"]])
      expect(state.visible_column_keys).to eq(%w[booking_date posting_text])
      expect(state.per_page).to eq(25)
      expect(state.page).to eq(1)
      expect(state.open_keys).to be_empty
      expect(state.source(:sort)).to eq(:default)
    end

    it "shows every column when no cols default is given" do
      expect(resolve(policy).visible_column_keys).to eq(COLUMNS.keys)
    end

    # A kind tab may want its own column first, so the declared order is the
    # column order -- not the order of the dataset's description.
    it "orders the columns as the cols default declares them, the rest hidden" do
      state = resolve(policy(cols: {default: %w[posting_text booking_date]}))
      expect(state.visible_column_keys).to eq(%w[posting_text booking_date])
      expect(state.column_states.map(&:first)).to eq(%w[posting_text booking_date] + (COLUMNS.keys - %w[posting_text booking_date]))
      expect(state.column_states.drop(2).map(&:last)).to all(be(false))
    end

    it "falls back to 50 per page" do
      expect(resolve(policy).per_page).to eq(50)
      expect(resolve(policy).per_value).to eq("50")
    end

    it "takes :all as a declared page size, in code and on the wire" do
      state = resolve(policy(per_page: {default: :all}))
      expect(state.per_page).to eq(:all)
      expect(state.per_value).to eq("all")
      expect(state.wire(:per_page)).to eq("all")
    end

    it "ignores the retired all_value: option" do
      expect(resolve(policy(per_page: {default: :all, all_value: 42})).per_page).to eq(:all)
    end
  end

  describe "the URL layer" do
    it "reads the sort from <prefix>s, mapping abbreviations to column keys" do
      state = resolve(policy, {"s" => "amt~,bdt"})
      expect(state.sort_list).to eq([["signed_base_amount", "desc"], ["booking_date", "asc"]])
      expect(state.source(:sort)).to eq(:url)
      expect(state.wire(:sort)).to eq("amt~,bdt")
    end

    it "reads the column order and visibility from <prefix>c" do
      state = resolve(policy, {"c" => "cc,~bdt"})
      expect(state.column_states.first(2)).to eq([["cost_center_number", true], ["booking_date", false]])
      expect(state.visible_column_keys).to eq(["cost_center_number"])
    end

    it "appends columns the param does not mention as hidden" do
      state = resolve(policy, {"c" => "cc"})
      expect(state.column_states.map(&:first)).to match_array(COLUMNS.keys)
      expect(state.visible_column_keys).to eq(["cost_center_number"])
    end

    it "reads page, page size and open rows" do
      state = resolve(policy, {"p" => "3", "z" => "100", "o" => "7,9,7, ,8"})
      expect(state.page).to eq(3)
      expect(state.per_page).to eq(100)
      expect(state.open_keys).to eq(Set["7", "9", "8"])
    end

    it "understands per_page=all, as the SYMBOL :all" do
      state = resolve(policy, {"z" => "all"})
      expect(state.per_page).to eq(:all)
      expect(state.per_value).to eq("all")
      expect(state.wire(:per_page)).to eq("all")
    end

    it "caps per_page" do
      expect(resolve(policy, {"z" => "99999"}).per_page).to eq(500)
      expect(resolve(policy, {"z" => "99999", "c" => ""}).per_page).to eq(500)
    end

    it "treats a present but blank param as an explicit empty value" do
      state = resolve(policy(sort: {default: [["booking_date", "desc"]]}), {"s" => ""})
      expect(state.sort_list).to eq([])
    end

    it "keeps a blank cols param on the default columns" do
      state = resolve(policy(cols: {default: %w[booking_date]}), {"c" => ""})
      expect(state.visible_column_keys).to eq(%w[booking_date])
    end
  end

  describe "allow-listing (D8.5)" do
    it "drops unknown sort tokens from the URL" do
      expect(resolve(policy, {"s" => "evil,bdt~"}).sort_list).to eq([["booking_date", "desc"]])
    end

    it "drops unknown column tokens from the URL" do
      state = resolve(policy, {"c" => "evil,cc"})
      expect(state.visible_column_keys).to eq(["cost_center_number"])
    end

    it "drops unknown sort tokens coming from the STORE, exactly like the URL" do
      session["wsjrdp_table_state"] = {"fin/bookings#index" => {"s" => "evil,cc"}}
      expect(resolve(policy).sort_list).to eq([["cost_center_number", "asc"]])
    end

    it "drops unknown column tokens coming from the STORE" do
      session["wsjrdp_table_state"] = {"fin/bookings#index" => {"c" => "evil,~cc"}}
      expect(resolve(policy).visible_column_keys).to eq([])
    end

    it "ignores a negative page" do
      expect(resolve(policy, {"p" => "-5"}).page).to eq(1)
    end

    it "bounds the number of open keys" do
      expect(resolve(policy, {"o" => (1..500).to_a.join(",")}).open_keys.size).to eq(200)
    end
  end

  # The column DESCRIPTION belongs to the dataset; which of its columns a table
  # has, and what it calls them, belongs to the table (D2b). An excluded column
  # is dropped like an unknown one -- from the param, from the store, from the
  # wire value and from the configs the widget renders and offers in the picker.
  describe "the table's own column set (cols: exclude: / labels:)" do
    let(:trimmed) { policy(cols: {default: %w[booking_date cost_center_number], exclude: %w[posting_text]}) }
    let(:configs) do
      [
        {key: "booking_date", label: "Datum"},
        {key: "posting_text", label: "Buchungstext"},
        {key: "cost_center_number", label: "Kostenstelle", condensed_label: "KOST"}
      ]
    end

    it "never shows an excluded column, whatever the URL asks for" do
      expect(resolve(trimmed).visible_column_keys).to eq(%w[booking_date cost_center_number])
      state = resolve(trimmed, {"c" => "posting_text,cc"})
      expect(state.visible_column_keys).to eq(%w[cost_center_number])
      expect(state.column_states.map(&:first)).not_to include("posting_text")
    end

    it "drops an excluded column coming from the STORE, exactly like the URL" do
      session["wsjrdp_table_state"] = {"fin/bookings#index" => {"c" => "posting_text,~cc"}}
      state = resolve(trimmed)
      expect(state.visible_column_keys).to eq([])
      expect(state.column_states.map(&:first)).not_to include("posting_text")
    end

    it "keeps an excluded column out of the cols wire value" do
      expect(resolve(trimmed, {"c" => "posting_text,cc"}).wire(:cols)).to eq("cc,~bdt,~amt")
    end

    it "cannot be sorted by an excluded column either" do
      expect(resolve(trimmed, {"s" => "posting_text,cc~"}).sort_list).to eq([["cost_center_number", "desc"]])
    end

    it "shapes the widget's column configs: excluded dropped, labels applied" do
      state = resolve(policy(cols: {exclude: %w[posting_text],
                                    labels: {"cost_center_number" => "Karteninhaber"}}))
      shaped = state.column_configs(configs)
      expect(shaped.pluck(:key)).to eq(%w[booking_date cost_center_number])
      expect(shaped.pluck(:label)).to eq(["Datum", "Karteninhaber"])
      # The condensed header follows the table's label as well.
      expect(shaped.last[:condensed_label]).to eq("Karteninhaber")
      # A column this table neither hides nor renames is passed through untouched.
      expect(shaped.first).to equal(configs.first)
    end

    it "gives no condensed label to a column that had none" do
      shaped = resolve(policy(cols: {labels: {"booking_date" => "Buchungsdatum"}})).column_configs(configs)
      expect(shaped.first[:label]).to eq("Buchungsdatum")
      expect(shaped.first[:condensed_label]).to be_nil
    end

    it "answers one column's label, falling back to the description's own" do
      state = resolve(policy(cols: {labels: {"booking_date" => "Buchungsdatum"}}))
      expect(state.column_label("booking_date", "Datum")).to eq("Buchungsdatum")
      expect(state.column_label("cost_center_number", "Kostenstelle")).to eq("Kostenstelle")
      expect(state.column_label("cost_center_number")).to be_nil
    end

    # One declaration can serve several routes (the Moss list and its kind tabs),
    # so both options may be lambdas -- evaluated on the controller, and held to
    # the same rules as a plain declaration.
    describe "declared as a lambda" do
      it "evaluates the shaping on the controller" do
        state = resolve(policy(cols: {
          exclude: -> { (action_name == "index") ? %w[posting_text] : [] },
          labels: -> { {"cost_center_number" => action_name.capitalize} }
        }))
        expect(state.visible_column_keys).not_to include("posting_text")
        expect(state.column_label("cost_center_number")).to eq("Index")
      end

      it "raises for an unknown key, exactly like the plain declaration" do
        expect { resolve(policy(cols: {exclude: -> { %w[typo] }})) }
          .to raise_error(ArgumentError, /cols: exclude: "typo" is not a column/)
        expect { resolve(policy(cols: {labels: -> { {"typo" => "X"} }})) }
          .to raise_error(ArgumentError, /cols: labels: "typo" is not a column/)
      end

      it "raises when it excludes one of the default columns" do
        expect {
          resolve(policy(cols: {default: -> { %w[booking_date posting_text] },
                                exclude: -> { %w[posting_text] }}))
        }.to raise_error(ArgumentError, /default column\(s\) posting_text are excluded/)
      end
    end
  end

  describe "the store layer" do
    it "restores a remembered value when the param is absent" do
      session["wsjrdp_table_state"] = {"fin/bookings#index" => {"s" => "cc~", "p" => "4"}}
      state = resolve(policy)
      expect(state.sort_list).to eq([["cost_center_number", "desc"]])
      expect(state.page).to eq(4)
      expect(state.source(:sort)).to eq(:store)
    end

    it "lets the URL win over the store" do
      session["wsjrdp_table_state"] = {"fin/bookings#index" => {"s" => "cc~"}}
      expect(resolve(policy, {"s" => "bdt"}).sort_list).to eq([["booking_date", "asc"]])
    end

    it "does not remember a :url field" do
      session["wsjrdp_table_state"] = {"fin/bookings#index" => {"f" => KONTO_WIRE}}
      expect(resolve(filter_policy(policy: :url)).filter.user_slots).to eq([])
    end

    it "writes the resolved value back for :remember fields" do
      resolve(policy, {"s" => "cc~", "p" => "2"})
      expect(session["wsjrdp_table_state"]["fin/bookings#index"]).to eq({"s" => "cc~", "p" => "2"})
    end

    it "does not write values that equal the defaults" do
      resolve(policy(sort: {default: [["booking_date", "desc"]]}), {"s" => "bdt~"})
      expect(session["wsjrdp_table_state"]).to be_blank
    end

    it "does not write a :url field" do
      resolve(filter_policy(policy: :url), {"f" => KONTO_WIRE})
      expect(session["wsjrdp_table_state"]).to be_blank
    end

    it "replaces a remembered entry when every field is back at its default" do
      resolve(filter_policy, {"f" => KONTO_WIRE})
      resolve(filter_policy, {"f" => ""})
      expect(session["wsjrdp_table_state"]).to be_blank
      expect(resolve(filter_policy).filter.user_slots).to eq([])
    end

    it "remembers the filter when the host opts in" do
      resolve(filter_policy, {"f" => KONTO_WIRE})
      expect(session["wsjrdp_table_state"]["fin/bookings#index"]).to eq({"f" => KONTO_WIRE})
      expect(resolve(filter_policy).filter.user_slots).to eq(KONTO_TREE)
    end

    it "keys the store per prefix" do
      described_class.resolve(Wsjrdp::TableStatePolicy.new(prefix: "bk", columns: COLUMNS),
        params: {"bks" => "cc~"}, stores: stores, controller: controller)
      expect(session["wsjrdp_table_state"].keys).to eq(["fin/bookings#index|bk"])
    end
  end

  describe "fixed fields (D8.1 / D8.9)" do
    it "takes a fixed value from the policy even when a param AND a store entry disagree" do
      session["wsjrdp_table_state"] = {"fin/bookings#index" => {"s" => "cc~", "z" => "500"}}
      state = resolve(policy(sort: {policy: :fixed, default: [["booking_date", "desc"]]},
        per_page: {policy: :fixed, default: 10}), {"s" => "amt", "z" => "all"})
      expect(state.sort_list).to eq([["booking_date", "desc"]])
      expect(state.per_page).to eq(10)
      expect(state.fixed?(:sort)).to be true
      expect(state.source(:sort)).to eq(:fixed)
    end

    it "never writes a fixed field to the store" do
      resolve(policy(sort: {policy: :fixed, default: [["cost_center_number", "asc"]]}), {"s" => "amt"})
      expect(session["wsjrdp_table_state"]).to be_blank
    end

    it "evaluates a fixed value given as a lambda on the controller" do
      state = resolve(policy(sort: {policy: :fixed,
                                    default: -> { [[(action_name == "index") ? "cost_center_number" : "booking_date", "asc"]] }}))
      expect(state.sort_list).to eq([["cost_center_number", "asc"]])
    end
  end

  describe "the filter (D2e)" do
    let(:locked) { [[["accounting_entry", "blank"]]] }
    let(:hidden) { [[["cost_center", "in", "8010"]]] }
    let(:user_tree) { [[["booking_date", "gte", "2026-01-01"]]] }
    let(:pinned_policy) do
      filter_policy(policy: :url,
        fixed: [{slots: locked, show: :readonly}, {slots: hidden, show: :hidden}],
        exclude: %i[sphere accounting_entry])
    end

    it "keeps the fixed slots and the user part apart" do
      state = resolve(pinned_policy, {"f" => JSON.generate(user_tree)})
      expect(state.filter.user_slots).to eq(user_tree)
      expect(state.filter.readonly_slots).to eq(locked)
      expect(state.filter.hidden_slots).to eq(hidden)
      expect(state.filter.fixed_slots).to eq(locked + hidden)
      expect(state.filter.effective_slots).to eq(locked + hidden + user_tree)
      expect(state.filter.exclude).to eq(%i[sphere accounting_entry])
      expect(state.filter.fixed?).to be true
    end

    it "cannot have a fixed slot removed or widened by the user part" do
      state = resolve(pinned_policy, {"f" => ""})
      expect(state.filter.user_slots).to eq([])
      expect(state.filter.fixed_slots).to eq(locked + hidden)
    end

    it "drops the user part entirely when the whole field is fixed" do
      state = resolve(filter_policy(policy: :fixed, fixed: [{slots: locked, show: :readonly}]),
        {"f" => JSON.generate(user_tree)})
      expect(state.filter.user_query).to be_nil
      expect(state.filter.user_slots).to eq([])
      expect(state.filter.fixed_slots).to eq(locked)
      expect(state.fixed?(:filter)).to be true
    end

    it "evaluates fixed slots given as a lambda" do
      state = resolve(filter_policy(
        fixed: -> { [{slots: [[["konto", "in", action_name]]], show: :readonly}] }
      ))
      expect(state.filter.readonly_slots).to eq([[["konto", "in", "index"]]])
    end

    it "is inert when the table declares no filter at all" do
      state = resolve(policy, {"f" => KONTO_WIRE})
      expect(state.filter.schema).to be_nil
      expect(state.filter.user_query).to be_nil
      expect(state.filter.user_slots).to eq([])
      expect(state.filter.effective_slots).to eq([])
      expect(state.filter.catalog).to eq({attributes: []})
      expect(state.wire(:filter)).to eq("")
      expect(state.filter.scope("rows")).to eq("rows")
      expect(filter_schema.compiled).to be_empty
    end

    describe "exclude: (enforced by construction, both read paths)" do
      let(:excluding_policy) { filter_policy(exclude: %i[sphere]) }
      let(:sphere_wire) { JSON.generate([[["sphere", "in", "x"]], *KONTO_TREE]) }

      it "drops an excluded attribute that arrives in the URL" do
        state = resolve(excluding_policy, {"f" => sphere_wire})
        expect(state.filter.user_slots).to eq(KONTO_TREE)
        expect(state.wire(:filter)).to eq(KONTO_WIRE)
      end

      it "drops an excluded attribute that arrives from the STORE" do
        session["wsjrdp_table_state"] = {"fin/bookings#index" => {"f" => sphere_wire}}
        expect(resolve(excluding_policy).filter.user_slots).to eq(KONTO_TREE)
      end

      it "offers the reduced catalog to the picker and the full one for labels" do
        state = resolve(excluding_policy)
        expect(state.filter.catalog[:attributes].pluck(:key)).not_to include("sphere")
        expect(state.filter.full_catalog[:attributes].pluck(:key)).to include("sphere")
      end
    end

    describe "fixed slots are parsed STRICTLY" do
      it "raises for an attribute the schema does not know, naming it and its slot" do
        expect {
          resolve(filter_policy(fixed: [{slots: [[["konto", "in", "41030"]],
            [["typo_attribute", "in", "x"]]], show: :readonly}]))
        }.to raise_error(ArgumentError, /fixed slot 1: unknown attribute "typo_attribute"/)
      end

      it "raises for an attribute the schema knew but no longer offers" do
        expect { resolve(filter_policy(fixed: [{slots: [[["gone", "blank"]]], show: :hidden}])) }
          .to raise_error(ArgumentError, /unknown attribute "gone"/)
      end

      it "raises for a blank fixed tree instead of silently pinning nothing" do
        expect { resolve(filter_policy(fixed: [{slots: [], show: :readonly}, {slots: [[]], show: :readonly}])) }
          .to raise_error(ArgumentError, /slot without conditions/)
      end
    end

    describe "#scope" do
      it "compiles the fixed slots with the FULL schema and the user query on top" do
        state = resolve(pinned_policy, {"f" => JSON.generate(user_tree)})
        result = state.filter.scope("BASE")

        expect(filter_schema.compiled.pluck(:schema)).to eq(%w[full reduced])
        expect(filter_schema.compiled.first).to include(slots: locked + hidden, relation: "BASE")
        expect(filter_schema.compiled.last[:slots]).to eq(user_tree)
        expect(result).to end_with(%(|reduced:[[["booking_date","gte","2026-01-01"]]]))
      end

      it "still compiles both halves when neither has conditions (the schema's joins)" do
        state = resolve(filter_policy)
        expect(state.filter.scope("BASE")).to eq("BASE+fullbase+fullbase")
      end
    end

    describe "default: (the user tree when nothing was chosen)" do
      let(:defaulting_policy) { filter_policy(default: KONTO_TREE) }

      it "applies when neither the param nor the store provides one" do
        expect(resolve(defaulting_policy).filter.user_slots).to eq(KONTO_TREE)
        expect(resolve(defaulting_policy).source(:filter)).to eq(:default)
      end

      it "does NOT apply to a present-but-blank param (the user cleared it)" do
        state = resolve(defaulting_policy, {"f" => ""})
        expect(state.filter.user_slots).to eq([])
        expect(state.wire(:filter)).to eq("")
      end

      it "does NOT apply once the store has a value" do
        other = JSON.generate([[["booking_date", "gte", "2026-01-01"]]])
        session["wsjrdp_table_state"] = {"fin/bookings#index" => {"f" => other}}
        expect(resolve(defaulting_policy).filter.user_slots)
          .to eq([[["booking_date", "gte", "2026-01-01"]]])
      end

      it "is host-authored, so a typo raises like a fixed slot" do
        expect { resolve(filter_policy(default: [[["typo_attribute", "in", "x"]]])) }
          .to raise_error(ArgumentError, /filter default tree 0: unknown attribute/)
      end

      it "exposes its wire form for the reset link, whatever the current value" do
        other = JSON.generate([[["booking_date", "gte", "2026-01-01"]]])
        expect(resolve(defaulting_policy, {"f" => other}).filter.default_wire).to eq(KONTO_WIRE)
        expect(resolve(filter_policy, {"f" => other}).filter.default_wire).to eq("")
      end
    end

    # A preset is a named list of slots the host offers as a one-click toggle.
    # It is ACTIVE when every one of its slots is present in the APPLIED user
    # filter under exact slot equality (Wsjrdp::Filtering::SlotEquality), and its
    # toggle_wire is the user filter after clicking it. The other declaration
    # form, a group of buttons sharing one slot, follows at the end.
    describe "presets" do
      let(:count_slot) { [["cost_center", "gte", 0]] }
      let(:konto_slot) { KONTO_TREE.first }
      let(:with_bookings) { {key: "with_bookings", label: "Nur mit Buchungen", slots: [count_slot]} }
      let(:konto_and_count) do
        {key: "both", label: "Konto und Buchungen", slots: [konto_slot, count_slot]}
      end

      def presets_of(state) = state.filter.presets.index_by(&:key)

      it "exposes the declared presets as frozen FilterPreset objects" do
        state = resolve(filter_policy(presets: [with_bookings]))
        preset = state.filter.presets.first
        expect(state.filter.presets).to be_frozen
        expect(preset).to be_a(Wsjrdp::TableState::FilterPreset)
        expect([preset.key, preset.label, preset.slots])
          .to eq(["with_bookings", "Nur mit Buchungen", [count_slot]])
      end

      it "is inactive with an empty filter and toggles the slot on" do
        preset = resolve(filter_policy(presets: [with_bookings])).filter.presets.first
        expect(preset.active?).to be false
        expect(preset.toggle_wire).to eq(JSON.generate([count_slot]))
      end

      it "is active once its slot is applied and toggles it off again" do
        state = resolve(filter_policy(presets: [with_bookings]),
          {"f" => JSON.generate([konto_slot, count_slot])})
        preset = state.filter.presets.first
        expect(preset.active?).to be true
        # Only the preset's own slot goes; every other slot stays.
        expect(preset.toggle_wire).to eq(JSON.generate([konto_slot]))
      end

      it "leaves nothing behind when the preset was the only slot (a blank param)" do
        state = resolve(filter_policy(presets: [with_bookings]), {"f" => JSON.generate([count_slot])})
        expect(state.filter.presets.first.toggle_wire).to eq("")
      end

      it "ignores the order of the conditions inside a slot" do
        or_slot = [["konto", "in", "41030"], ["cost_center", "gte", 0]]
        preset = {key: "or", label: "Oder", slots: [or_slot.reverse]}
        state = resolve(filter_policy(presets: [preset]), {"f" => JSON.generate([or_slot])})
        expect(state.filter.presets.first.active?).to be true
      end

      it "does NOT count a slot that OR-widens the preset's condition" do
        widened = [count_slot.first, ["konto", "in", "41030"]]
        state = resolve(filter_policy(presets: [with_bookings]), {"f" => JSON.generate([widened])})
        preset = state.filter.presets.first
        expect(preset.active?).to be false
        # Turning it on ADDS the exact slot next to the widened one.
        expect(preset.toggle_wire).to eq(JSON.generate([widened, count_slot]))
      end

      it "compares operands canonically, so 0 and \"0\" are one value" do
        state = resolve(filter_policy(presets: [with_bookings]),
          {"f" => JSON.generate([[["cost_center", "gte", "0"]]])})
        expect(state.filter.presets.first.active?).to be true
      end

      # A preset on the MAGNITUDE of a sign pair recognises the signed twin of a
      # sign-invariant condition -- `Saldo ≠ 0` IS `|Saldo| ≠ 0`, so a user who
      # builds it by hand sees the preset switched on, and its toggle removes
      # exactly that slot (Wsjrdp::Filtering::SlotEquality, `aliases:`).
      describe "a sign pair" do
        let(:absolute_slot) { [["balance_abs", "nonzero"]] }
        let(:signed_slot) { [["balance", "nonzero"]] }
        let(:with_balance) { {key: "with_balance", label: "Nur mit Saldo", slots: [absolute_slot]} }

        def preset_for(filter)
          resolve(filter_policy(presets: [with_balance]), {"f" => JSON.generate(filter)})
            .filter.presets.first
        end

        it "is active on the signed twin of its sign-invariant condition" do
          expect(preset_for([signed_slot]).active?).to be true
          expect(preset_for([absolute_slot]).active?).to be true
        end

        it "removes exactly that twin when switched off, keeping every other slot" do
          preset = preset_for([konto_slot, signed_slot])
          expect(preset.active?).to be true
          expect(preset.toggle_wire).to eq(JSON.generate([konto_slot]))
        end

        it "adds nothing when switched on while the twin is already there" do
          expect(preset_for([signed_slot]).toggle_wire).to eq("")
        end

        # A comparison asks about the sign, so the two members stay apart.
        it "leaves a comparison member-specific" do
          comparing = {key: "big", label: "Groß", slots: [[["balance_abs", "gte", 100]]]}
          state = resolve(filter_policy(presets: [comparing]),
            {"f" => JSON.generate([[["balance", "gte", 100]]])})
          expect(state.filter.presets.first.active?).to be false
        end
      end

      it "needs EVERY slot of a multi-slot preset to be present" do
        one = resolve(filter_policy(presets: [konto_and_count]), {"f" => JSON.generate([konto_slot])})
        expect(one.filter.presets.first.active?).to be false
        # ... and adds only the missing one.
        expect(one.filter.presets.first.toggle_wire).to eq(JSON.generate([konto_slot, count_slot]))

        both = resolve(filter_policy(presets: [konto_and_count]),
          {"f" => JSON.generate([konto_slot, count_slot])})
        expect(both.filter.presets.first.active?).to be true
      end

      it "lets overlapping presets share a slot, so switching one off deactivates the other" do
        state = resolve(filter_policy(presets: [with_bookings, konto_and_count]),
          {"f" => JSON.generate([konto_slot, count_slot])})
        presets = presets_of(state)
        expect(presets.values.map(&:active?)).to eq([true, true])

        after = resolve(filter_policy(presets: [with_bookings, konto_and_count]),
          {"f" => presets["with_bookings"].toggle_wire})
        expect(presets_of(after).values.map(&:active?)).to eq([false, false])
        expect(after.filter.user_slots).to eq([konto_slot])
      end

      it "builds a VIEW-declared preset through the same implementation" do
        state = resolve(filter_policy, {"f" => JSON.generate([count_slot])})
        preset = state.filter.preset(**with_bookings)
        expect(state.filter.presets).to eq([])
        expect(preset.active?).to be true
        expect(preset.toggle_wire).to eq("")
      end

      it "is host-authored, so a typo raises, naming the preset" do
        typo = {key: "oops", label: "Ups", slots: [[["typo_attribute", "in", "x"]]]}
        expect { resolve(filter_policy(presets: [typo])) }
          .to raise_error(ArgumentError, /filter preset oops 0: unknown attribute "typo_attribute"/)
      end

      it "is parsed against the REDUCED schema, so an excluded attribute raises too" do
        excluded = {key: "s", label: "S", slots: [[["sphere", "in", "x"]]]}
        expect { resolve(filter_policy(exclude: %i[sphere], presets: [excluded])) }
          .to raise_error(ArgumentError, /filter preset s 0: unknown attribute "sphere"/)
      end

      it "has none when the table declares no filter at all" do
        expect(resolve(policy).filter.presets).to eq([])
      end

      # icon (a FontAwesome 5 name WITHOUT the "fa-" prefix) and css_class are
      # OPTIONAL display extras -- the bar renders the icon before the label and
      # puts the class on the toggle link. They never touch the slots, the
      # active state or the toggle URL.
      describe "icon and css_class" do
        let(:decorated) { with_bookings.merge(icon: "credit-card", css_class: "moss-kind-card_transaction") }

        it "exposes what the policy declared" do
          preset = resolve(filter_policy(presets: [decorated])).filter.presets.first
          expect([preset.icon, preset.css_class]).to eq(["credit-card", "moss-kind-card_transaction"])
        end

        it "leaves the slots, the active state and the toggle URL untouched" do
          plain = resolve(filter_policy(presets: [with_bookings])).filter.presets.first
          fancy = resolve(filter_policy(presets: [decorated])).filter.presets.first
          expect([fancy.slots, fancy.active?, fancy.toggle_wire])
            .to eq([plain.slots, plain.active?, plain.toggle_wire])
        end

        it "is nil on both counts for a preset that declares neither" do
          preset = resolve(filter_policy(presets: [with_bookings])).filter.presets.first
          expect([preset.icon, preset.css_class]).to eq([nil, nil])
        end

        it "reaches a VIEW-declared preset the same way, and defaults to nil there too" do
          state = resolve(filter_policy)
          expect([state.filter.preset(**decorated).icon, state.filter.preset(**decorated).css_class])
            .to eq(["credit-card", "moss-kind-card_transaction"])
          plain = state.filter.preset(**with_bookings)
          expect([plain.icon, plain.css_class]).to eq([nil, nil])
        end

        it "still rejects a key that is neither, at both declaration sites" do
          stray = with_bookings.merge(colour: "blue")
          expect { resolve(filter_policy(presets: [stray])) }
            .to raise_error(ArgumentError, /unknown keyword: :colour/)
          expect { resolve(filter_policy).filter.preset(**stray) }
            .to raise_error(ArgumentError, /unknown keyword: :colour/)
        end
      end

      # The second declaration form: a GROUP of buttons that share ONE slot,
      # `attribute in (values)`, each member standing for one value of that set.
      # A member is ACTIVE when a slot of that shape carries its value, and its
      # toggle puts the value into every such slot or takes it out of them.
      describe "a group" do
        let(:kind_group) do
          {group: "kind", attribute: "kind", operator: "in",
           members: [{key: "card", label: "Karte", value: "card",
                      icon: "credit-card", css_class: "kind-card"},
             {key: "invoice", label: "Rechnung", value: "invoice"},
             {key: "refund", label: "Erstattung", value: "refund"}]}
        end
        let(:card_slot) { [["kind", "in", "card"]] }

        def resolve_group(declaration = kind_group, filter: nil)
          resolve(filter_policy(presets: [declaration]),
            filter ? {"f" => JSON.generate(filter)} : {})
        end

        def members_of(declaration = kind_group, filter: nil)
          resolve_group(declaration, filter: filter).filter.presets.index_by(&:key)
        end

        it "contributes one FilterPreset per member, in declaration order" do
          presets = resolve_group.filter.presets
          expect(presets.map(&:key)).to eq(%w[card invoice refund])
          expect(presets.map(&:group?)).to eq([true, true, true])
          expect(presets.map(&:slots)).to eq([nil, nil, nil])
          card = presets.first
          expect([card.group, card.attribute, card.value, card.label])
            .to eq(["kind", "kind", "card", "Karte"])
          expect([card.icon, card.css_class]).to eq(["credit-card", "kind-card"])
          expect([presets.last.icon, presets.last.css_class]).to eq([nil, nil])
          expect(card.group_values).to eq(%w[card invoice refund])
          expect(card.group_values).to be_frozen
        end

        it "is pressed by nobody without a filter, and each toggle adds its own value" do
          members = members_of
          expect(members.values.map(&:active?)).to eq([false, false, false])
          expect(members["card"].toggle_wire).to eq(JSON.generate([card_slot]))
          expect(members["invoice"].toggle_wire).to eq(JSON.generate([[["kind", "in", "invoice"]]]))
        end

        it "reads a matching slot, and adds to it instead of next to it" do
          members = members_of(filter: [card_slot])
          expect(members.values.map(&:active?)).to eq([true, false, false])
          expect(members["invoice"].toggle_wire)
            .to eq(JSON.generate([[["kind", "in", "card", "invoice"]]]))
        end

        it "drops the whole slot when its last value goes, keeping every other slot" do
          members = members_of(filter: [konto_slot, card_slot])
          expect(members["card"].toggle_wire).to eq(JSON.generate([konto_slot]))
          expect(members_of(filter: [card_slot])["card"].toggle_wire).to eq("")
        end

        it "acts on EVERY matching slot at once" do
          both = [card_slot, [["kind", "in", "card", "invoice"]]]
          members = members_of(filter: both)

          expect(members["refund"].toggle_wire)
            .to eq(JSON.generate([[["kind", "in", "card", "refund"]],
              [["kind", "in", "card", "invoice", "refund"]]]))
          expect(members["card"].toggle_wire)
            .to eq(JSON.generate([[["kind", "in", "invoice"]]]))
        end

        it "never reads or touches a slot with a second condition or another operator" do
          untouched = [[["kind", "in", "card"], ["konto", "in", "41030"]],
            [["kind", "not_in", "card"]]]
          members = members_of(filter: untouched)

          expect(members.values.map(&:active?)).to eq([false, false, false])
          expect(members["card"].toggle_wire).to eq(JSON.generate(untouched + [card_slot]))
        end

        it "is host-authored, so a mistake raises, naming the group" do
          # "konto" is known but takes no group: it offers no `in` with options.
          expect { resolve_group(kind_group.merge(attribute: "typo_attribute")) }
            .to raise_error(ArgumentError,
              /filter preset group kind: attribute "typo_attribute" is unknown/)
          expect { resolve_group(kind_group.merge(attribute: "konto")) }
            .to raise_error(ArgumentError, /filter preset group kind: attribute "konto" is unknown/)
          expect { resolve_group(kind_group.merge(operator: "not_in")) }
            .to raise_error(ArgumentError, /filter preset group kind: operator "not_in"/)
          expect { resolve_group(kind_group.except(:members)) }
            .to raise_error(ArgumentError, /filter preset group kind: missing keyword: :members/)
          expect { resolve_group(kind_group.merge(colour: "blue")) }
            .to raise_error(ArgumentError, /filter preset group kind: unknown keyword: :colour/)
        end

        it "checks every member: its value, its keys, and that neither repeats" do
          with_members = ->(*members) { kind_group.merge(members: members) }
          card = kind_group[:members].first

          expect { resolve_group(with_members.call(card.merge(value: "typo_value"))) }
            .to raise_error(ArgumentError,
              /filter preset group kind: member card has the value "typo_value"/)
          expect { resolve_group(with_members.call(card.merge(colour: "blue"))) }
            .to raise_error(ArgumentError, /filter preset group kind: unknown keyword: :colour/)
          expect { resolve_group(with_members.call(card.except(:value))) }
            .to raise_error(ArgumentError, /filter preset group kind: missing keyword: :value/)
          expect { resolve_group(with_members.call(card, card.merge(key: "second"))) }
            .to raise_error(ArgumentError, /filter preset group kind: duplicate member value "card"/)
          expect { resolve_group(with_members.call(card, card.merge(value: "invoice"))) }
            .to raise_error(ArgumentError, /filter preset group kind: duplicate member key "card"/)
        end

        it "is parsed against the REDUCED schema, so an excluded attribute raises too" do
          expect { resolve(filter_policy(exclude: %i[kind], presets: [kind_group])) }
            .to raise_error(ArgumentError, /filter preset group kind: attribute "kind" is unknown/)
        end

        it "is built by a VIEW declaration through the same implementation" do
          state = resolve(filter_policy, {"f" => JSON.generate([card_slot])})
          members = state.filter.preset(**kind_group)

          expect(state.filter.presets).to eq([])
          expect(members.map(&:key)).to eq(%w[card invoice refund])
          expect(members.map(&:active?)).to eq([true, false, false])
          expect(members.first.toggle_wire).to eq("")
        end

        it "keeps its place among slot presets, which are unaffected" do
          state = resolve(filter_policy(presets: [with_bookings, kind_group, konto_and_count]),
            {"f" => JSON.generate([count_slot])})
          presets = state.filter.presets

          expect(presets.map(&:key)).to eq(%w[with_bookings card invoice refund both])
          expect(presets.map(&:group?)).to eq([false, true, true, true, false])
          expect(presets.map(&:active?)).to eq([true, false, false, false, false])
          expect(presets.first.slots).to eq([count_slot])
          expect(presets.first.toggle_wire).to eq("")
          expect(presets[1].toggle_wire).to eq(JSON.generate([count_slot, card_slot]))
        end
      end
    end

    it "round-trips a user filter through the wire form" do
      state = resolve(filter_policy, {"f" => KONTO_WIRE})
      expect(state.wire(:filter)).to eq(KONTO_WIRE)
      expect(state.filter.encode_tree(KONTO_TREE)).to eq(KONTO_WIRE)
      expect(state.filter.encode_tree([[["typo_attribute", "in", "x"]]])).to be_nil
      expect(resolve(filter_policy(policy: :url), {"f" => state.wire(:filter)}).filter.user_slots)
        .to eq(KONTO_TREE)
    end
  end

  describe "the pane (D2d, cookie store)" do
    it "reads the pane from its cookie" do
      cookies["wsjrdp_ts_fin_bookings_index_e"] = "0"
      expect(resolve(policy(pane: {default: 1})).pane).to be false
    end

    it "falls back to the declared default" do
      expect(resolve(policy(pane: {default: 1})).pane).to be true
      expect(resolve(policy).pane).to be false
    end

    it "exposes the cookie name for the JS" do
      expect(resolve(policy).cookie_name(:pane)).to eq("wsjrdp_ts_fin_bookings_index_e")
    end
  end

  describe "#paginate (D4 and the :all page size)" do
    let(:scope) { FakePagedScope.new(120) }
    let(:rows) { (1..120).to_a }

    it "pages a relation at the resolved page and size" do
      paged = resolve(policy, {"p" => "2", "z" => "25"}).paginate(scope)
      expect([paged.page_number, paged.per_size]).to eq([2, 25])
    end

    it "falls back to page 1 beyond the last page" do
      expect(resolve(policy, {"p" => "7", "z" => "25"}).paginate(scope).page_number).to eq(1)
    end

    it "asks for ONE page holding everything when the size is :all" do
      paged = resolve(policy, {"z" => "all"}).paginate(scope)
      expect(paged.page_number).to eq(1)
      expect(paged.per_size).to be > rows.size
    end

    it "pages a plain Array through Kaminari" do
      stub_const("Kaminari", FakeKaminari)
      paged = resolve(policy, {"p" => "3", "z" => "10"}).paginate(rows)
      expect([paged.page_number, paged.per_size]).to eq([3, 10])
    end

    it "clamps an array-backed table to page 1 as well" do
      stub_const("Kaminari", FakeKaminari)
      expect(resolve(policy, {"p" => "7", "z" => "50"}).paginate(rows).page_number).to eq(1)
    end

    it "does not expose the internal limit behind :all" do
      expect { Wsjrdp::TableState::ALL_PER }.to raise_error(NameError)
    end
  end

  describe "#wire_params" do
    it "carries what the URL chose, but not defaults, stored values or the level" do
      session["wsjrdp_table_state"] = {"fin/bookings#index" => {"z" => "100"}}
      state = resolve(policy, {"s" => "cc~", "p" => "2", "o" => "5", "expandable_table_level" => "1"})
      expect(state.wire_params).to eq({"s" => "cc~", "p" => "2", "o" => "5"})
    end

    it "skips fixed fields" do
      state = resolve(policy(sort: {policy: :fixed, default: [["cost_center_number", "asc"]]}),
        {"s" => "bdt", "p" => "2"})
      expect(state.wire_params).to eq({"p" => "2"})
    end
  end

  it "is frozen" do
    state = resolve(policy)
    expect(state).to be_frozen
    expect(state.sort_list).to be_frozen
    expect(state.open_keys).to be_frozen
  end
end

# The D7 store contract, run against every store: `write` REPLACES the entry
# (a missing field is forgotten, an empty hash removes it), keys are isolated
# from siblings that extend them, and delete_all works by key prefix. Values
# are single tokens so the cookie store accepts them too.
RSpec.shared_examples "a table state store" do
  it "round-trips an entry" do
    store.write("a#b", {"s" => "1", "z" => "2"})
    expect(store.read("a#b")).to eq({"s" => "1", "z" => "2"})
  end

  it "forgets a field that a later write leaves out" do
    store.write("a#b", {"s" => "1", "z" => "2"})
    store.write("a#b", {"z" => "2"})
    expect(store.read("a#b")).to eq({"z" => "2"})
  end

  it "removes the entry on an empty write" do
    store.write("a#b", {"s" => "1"})
    store.write("a#b", {})
    expect(store.read("a#b")).to be_blank
  end

  it "deletes one key and leaves the others" do
    store.write("a#b", {"s" => "1"})
    store.write("a#c", {"s" => "2"})
    store.delete("a#b")
    expect(store.read("a#b")).to be_blank
    expect(store.read("a#c")).to eq({"s" => "2"})
  end

  it "keeps a sibling table whose key extends this key apart" do
    store.write("fin/x#index", {"e" => "1"})
    store.write("fin/x#index|bk", {"e" => "0"})
    expect(store.read("fin/x#index")).to eq({"e" => "1"})
    store.write("fin/x#index", {})
    expect(store.read("fin/x#index|bk")).to eq({"e" => "0"})
    store.delete("fin/x#index")
    expect(store.read("fin/x#index|bk")).to eq({"e" => "0"})
  end

  it "deletes a whole key prefix" do
    store.write("fin/x#index", {"s" => "1"})
    store.write("fin/x#index|bk", {"s" => "2"})
    store.write("fin/y#index", {"s" => "3"})
    store.delete_all("fin/x#index")
    expect(store.read("fin/x#index")).to be_blank
    expect(store.read("fin/x#index|bk")).to be_blank
    expect(store.read("fin/y#index")).to eq({"s" => "3"})
  end
end

describe Wsjrdp::TableStateStore::Session do
  let(:session) { {} }
  let(:store) { described_class.new(session) }

  it_behaves_like "a table state store"

  it "keeps multi-token values" do
    store.write("a#b", {"s" => "cc~,bdt"})
    expect(store.read("a#b")).to eq({"s" => "cc~,bdt"})
  end

  it "does not touch the session when nothing changed" do
    store.write("a#b", {"s" => "cc~"})
    written = session["wsjrdp_table_state"]
    store.write("a#b", {"s" => "cc~"})
    expect(session["wsjrdp_table_state"]).to equal(written)
  end

  it "caps the keys per controller and drops the oldest" do
    (1..60).each { |i| store.write("fin/x#show:#{i}", {"s" => i.to_s}) }
    keys = session["wsjrdp_table_state"].keys
    expect(keys.size).to eq(described_class::MAX_KEYS_PER_CONTROLLER)
    expect(keys.first).to eq("fin/x#show:11")
    expect(keys.last).to eq("fin/x#show:60")
  end

  it "counts the cap per controller, not globally" do
    (1..60).each { |i| store.write("fin/x#show:#{i}", {"s" => i.to_s}) }
    store.write("fin/y#index", {"s" => "1"})
    expect(store.read("fin/y#index")).to eq({"s" => "1"})
    expect(session["wsjrdp_table_state"].size).to eq(described_class::MAX_KEYS_PER_CONTROLLER + 1)
  end
end

describe Wsjrdp::TableStateStore::Cookie do
  let(:cookies) { FakeCookieJar.new }
  let(:store) { described_class.new(cookies) }

  it_behaves_like "a table state store"

  it "derives one cookie name per table and field" do
    expect(described_class.cookie_name("fin/bookings#index|bk", "e")).to eq("wsjrdp_ts_fin_bookings_index_bk_e")
  end

  it "round-trips a single-token value" do
    store.write("fin/bookings#index", {"e" => "1"})
    expect(store.read("fin/bookings#index")).to eq({"e" => "1"})
  end

  it "refuses anything but a single token" do
    store.write("fin/bookings#index", {"e" => "a,b~c"})
    expect(store.read("fin/bookings#index")).to eq({})
  end

  it "ignores a hand-edited multi-token cookie on read" do
    cookies["wsjrdp_ts_fin_bookings_index_e"] = "bdt,~amt"
    expect(store.read("fin/bookings#index")).to eq({})
  end

  it "does not re-set a cookie the browser already wrote" do
    cookies["wsjrdp_ts_fin_bookings_index_e"] = "0"
    jar = cookies.to_h
    store.write("fin/bookings#index", {"e" => "0"})
    expect(cookies.to_h).to eq(jar)
  end

  it "removes a lingering cookie once the value is back at its default (empty write)" do
    cookies["wsjrdp_ts_fin_bookings_index_e"] = "0" # written by the pane JS
    store.write("fin/bookings#index", {})
    expect(cookies.to_h).to eq({})
  end
end
