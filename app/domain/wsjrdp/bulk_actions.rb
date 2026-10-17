# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The bulk actions of a table with row selection (doc/wsjrdp/expandable_table.md,
# "Bulk actions"): what the bar over the selected rows offers
# (`t.bulk_actions`, shared/wsjrdp/_expandable_table_bulk_bar) and what the
# controller runs on the posted selection (Wsjrdp::BulkActionable).
#
#   ACTIONS = Wsjrdp::BulkActions.define(noun: {one: "Buchung", many: "Buchungen"}) do |a|
#     a.action key: "unit_budget", label: "Als Unit-Budget markieren", icon: :wallet,
#       hint: {one: "Zählt 1 Buchung zum Unit-Budget", many: "Zählt %{count} Buchungen zum Unit-Budget"},
#       done: "%{count} Buchungen: als Unit-Budget markiert.",
#       authorize: [:update, DatevBooking], apply: :bulk_mark_unit_budget
#     a.action key: "secondary_cost_center", label: "Sekundäre Kostenstelle setzen", icon: :tag,
#       param: {name: :secondary_cost_center_number, label: "Sekundäre Kostenstelle",
#               options: :secondary_cost_center_options, default: "3810"},
#       hint: {...}, done: "...%{target}...", authorize: [:update, DatevBooking], apply: :bulk_assign
#   end
#
# An action:
#
#   key        the value the bar posts as `bulk_action` (a-z, 0-9, _)
#   label      the button's text; icon its icon
#   hint       {one:, many:}: what the action will do, for the confirm dialog
#              and the button's tooltip; %{count} is the number of selected
#              rows, %{target} the chosen option's text
#   done       the flash after it ran, with %{count} (rows changed) and %{target}
#   param      optional: one value the action needs, a select -- name (the
#              posted param), label, options (a method of the controller that
#              answers [[text, value], ...]) and default (a value, or a method)
#   authorize  [action, subject] for can?/authorize!: the bar leaves out the
#              actions the user may not run, the controller refuses them
#   apply      a method of the controller, called with the selected ids and the
#              param's value (nil without one) inside a transaction; it answers
#              how many rows it changed and raises ArgumentError for a value it
#              refuses
#   danger     true colours the button as a destructive one
#   partition  optional: a method of the controller, called with the selected
#              rows (a relation) and the param's value, that answers a
#              Partition -- the rows the action changes (`affected`), extra
#              preview columns for them (`columns`: [{label:, cell: ->(row)}])
#              and the selected rows it leaves alone (`groups`: Group with
#              rows, text -- %{count} filled in -- and warning). The preview
#              lists the affected rows with the extra columns, then each group
#              (a warning group with its rows), and the action runs on the
#              affected rows only.
class Wsjrdp::BulkActions
  include Enumerable

  KEY_FORMAT = /\A[a-z][a-z0-9_]*\z/
  ACTION_KEYS = %i[key label icon hint done param authorize apply danger partition].freeze
  PARAM_KEYS = %i[name label options default].freeze

  Param = Data.define(:name, :label, :options, :default)

  # Selected rows an action leaves alone: why (text, with %{count}), and
  # whether that deserves a warning (the preview then lists them).
  Group = Data.define(:rows, :text, :warning) do
    def initialize(rows:, text:, warning: false) = super
  end

  # What an action makes of the selection (`partition:`).
  Partition = Data.define(:affected, :columns, :groups) do
    def initialize(affected:, columns: [], groups: []) = super
  end

  Action = Data.define(:key, :label, :icon, :hint, :done, :param, :authorize, :apply, :danger, :partition) do
    # The hint for `count` selected rows.
    def hint_for(count, target: nil)
      format_text((count == 1) ? hint.fetch(:one) : hint.fetch(:many), count: count, target: target)
    end

    def done_message(count, target: nil) = format_text(done, count: count, target: target)

    # The param's options ([[text, value], ...]) and its default, from the
    # controller (`host`) that serves the table.
    def options_in(host) = param ? host.send(param.options) : []

    def default_in(host) = param&.default.is_a?(Symbol) ? host.send(param.default) : param&.default

    # The text of a param value among the options, nil for none of them.
    def target_in(host, value) = options_in(host).find { |_, option| option.to_s == value.to_s }&.first

    private

    def format_text(text, count:, target:)
      text.gsub("%{count}", count.to_s).gsub("%{target}", target.to_s)
    end
  end

  # What one and several rows are called, for the bar and the flash
  # ("Keine Buchungen ausgewählt.").
  attr_reader :noun

  def self.define(noun: {one: "Zeile", many: "Zeilen"}, &block)
    builder = Builder.new
    block.call(builder)
    new(builder.actions, noun: noun)
  end

  def initialize(actions, noun:)
    @actions = actions.freeze
    @noun = {one: noun.fetch(:one), many: noun.fetch(:many)}.freeze
  end

  def each(&) = @actions.each(&)

  # The action of a posted key, nil for an unknown one.
  def [](key) = @actions.find { |action| action.key == key.to_s }

  def keys = @actions.map(&:key)

  # Collects the actions of a define block, checking each.
  class Builder
    attr_reader :actions

    def initialize
      @actions = []
    end

    def action(**options)
      unknown = options.keys - ACTION_KEYS
      raise ArgumentError, "bulk action: unknown options #{unknown.inspect}" if unknown.any?

      key = options.fetch(:key).to_s
      raise ArgumentError, "bulk action key #{key.inspect} must match #{KEY_FORMAT.inspect}" unless key.match?(KEY_FORMAT)
      raise ArgumentError, "bulk action #{key.inspect} is declared twice" if @actions.any? { |a| a.key == key }

      @actions << Action.new(key: key, label: options.fetch(:label), icon: options.fetch(:icon),
        hint: hint(key, options.fetch(:hint)), done: options.fetch(:done), param: param(key, options[:param]),
        authorize: options[:authorize], apply: apply(key, options.fetch(:apply)), danger: !!options[:danger],
        partition: partition(key, options[:partition]))
    end

    private

    def hint(key, value)
      unless value.is_a?(Hash) && value.key?(:one) && value.key?(:many)
        raise ArgumentError, "bulk action #{key.inspect}: hint needs :one and :many"
      end

      value.slice(:one, :many).freeze
    end

    def param(key, value)
      return nil if value.nil?

      unknown = value.keys - PARAM_KEYS
      raise ArgumentError, "bulk action #{key.inspect}: unknown param options #{unknown.inspect}" if unknown.any?
      unless value[:options].is_a?(Symbol)
        raise ArgumentError, "bulk action #{key.inspect}: param options must name a controller method"
      end

      Param.new(name: value.fetch(:name).to_s, label: value.fetch(:label), options: value[:options],
        default: value[:default])
    end

    def partition(key, value)
      return nil if value.nil?
      return value if value.is_a?(Symbol)

      raise ArgumentError, "bulk action #{key.inspect}: partition must name a controller method"
    end

    def apply(key, value)
      raise ArgumentError, "bulk action #{key.inspect}: apply must name a controller method" unless value.is_a?(Symbol)

      value
    end
  end
end
