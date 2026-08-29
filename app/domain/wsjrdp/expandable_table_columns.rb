# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# THE ordered column description of one dataset (doc/wsjrdp/expandable_table.md).
# Written once, next to nothing else, and read by the three places that used to
# keep their own copy: the table's policy (codec + default columns), the rows
# object (the sort allow-list) and the rendering helper (the widget's Hashes).
#
#   module Fin::DatevBookingsColumns
#     COLUMNS = Wsjrdp::ExpandableTableColumns.define(css_prefix: "bkcol") do |c|
#       c.column key: "booking_date", abbr: "bdt", label: "Datum", width: "7rem",
#         sort: "booking_date", default: true
#       ...
#     end
#
#     def self.codec = COLUMNS.codec
#     def self.default_keys = COLUMNS.default_keys
#     def self.sort_expressions = COLUMNS.sort_expressions
#   end
#
# `css_prefix:` derives each column's css_class as "<prefix>-<key>" unless the
# column declares one itself.
class Wsjrdp::ExpandableTableColumns
  include Enumerable

  # Collects the columns of one `define` block, in declaration order -- which is
  # the table's column order before the user reorders anything.
  class Builder
    attr_reader :columns

    def initialize(css_prefix: nil)
      @css_prefix = css_prefix
      @columns = []
    end

    def column(**options)
      options[:css_class] ||= "#{@css_prefix}-#{options[:key]}" if @css_prefix
      @columns << Wsjrdp::ExpandableTableColumn.new(**options)
    end
  end

  def self.define(css_prefix: nil)
    builder = Builder.new(css_prefix: css_prefix)
    yield builder
    new(builder.columns)
  end

  def initialize(columns)
    @columns = columns.freeze
    @keys = @columns.map(&:key).freeze
    validate!
    @by_key = @columns.to_h { |col| [col.key, col] }.freeze
    @codec = @columns.to_h { |col| [col.key, col.abbr] }.freeze
    @default_keys = @columns.select(&:default?).map(&:key).freeze
    @sort_expressions = @columns.select(&:sortable?).to_h { |col| [col.key, col.sort] }.freeze
    freeze
  end

  # The column keys, in column order.
  #
  # codec: key => abbr, in column order -- the table policy's `columns:` codec,
  #   which doubles as the allow-list of the ?c= and ?s= params (D8.5).
  # default_keys: the columns shown before the user picks any -- the policy's
  #   `cols: {default:}`.
  # sort_expressions: key => SQL expression / extractor, for the columns that can
  #   be sorted -- the `sort:` allow-list of Wsjrdp::ExpandableTableRows.
  attr_reader :keys, :codec, :default_keys, :sort_expressions

  def each(&block) = @columns.each(&block)

  def to_a = @columns

  def size = @columns.size

  def fetch(key) = @by_key.fetch(key.to_s)

  def key?(key) = @by_key.key?(key.to_s)

  private

  # Keys and abbreviations are both wire tokens of the ?c= / ?s= params, so they
  # have to be unique AND to pass the token rule -- which lives in ONE place,
  # Wsjrdp::TableStatePolicy, because it is that class's `columns:` codec the
  # tokens end up in.
  def validate!
    duplicates(@keys).then do |dupes|
      raise ArgumentError, "duplicate column key(s): #{dupes.join(", ")}" if dupes.any?
    end
    abbrs = @columns.map(&:abbr)
    duplicates(abbrs).then do |dupes|
      raise ArgumentError, "duplicate column abbreviation(s): #{dupes.join(", ")}" if dupes.any?
    end
    (@keys + abbrs).each { |token| Wsjrdp::TableStatePolicy.validate_token!(token) }
  end

  def duplicates(tokens) = tokens.tally.select { |_token, count| count > 1 }.keys
end
