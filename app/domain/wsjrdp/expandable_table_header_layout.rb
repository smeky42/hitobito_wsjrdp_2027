# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The header layouts of one merged column (ExpandableTableColumns::Builder
# #merge_header), from the most compact to the most stacked; the table shows
# the most compact one whose headers fit (Wsjrdp::ExpandableTableHeader,
# doc/wsjrdp/expandable_table.md, "Header layouts").
#
# A layout is its rows, each row the headers in it:
#
#   [%w[label], %w[key secondary_key]]                    # a layout of two rows
#   {rows: [%w[label], %w[key secondary_key]], wrap: true} # headers may wrap
#
# A row is an Array of entries -- a column key, or {key:, align:, span:} --
# or {cells: [...], flow: true, justify: "start" | "center" | "between",
# separator: " · "}: its headers one after the other in one cell across the
# merged column.
class Wsjrdp::ExpandableTableHeaderLayout
  Entry = Data.define(:key, :align, :span)
  Row = Data.define(:entries, :flow, :justify, :separator)
  Layout = Data.define(:rows, :wrap)

  ALIGNS = %w[start center end].freeze
  JUSTIFIES = %w[start center between].freeze

  attr_reader :merge, :layouts

  # merge: the merge key; layouts: the layouts as given; members: the keys of
  # the merge's columns (an entry must name one of them).
  def initialize(merge, layouts, members:)
    @merge = merge.to_s
    raise ArgumentError, "merge_header #{@merge}: no layout" if Array(layouts).empty?

    @layouts = Array(layouts).map { |layout| parse_layout(layout, members.map(&:to_s)) }.freeze
    freeze
  end

  private

  def parse_layout(layout, members)
    layout = {rows: layout} if layout.is_a?(Array)
    layout = layout.to_h.transform_keys(&:to_sym)
    rows = Array(layout.fetch(:rows)).map { |row| parse_row(row, members) }
    raise ArgumentError, "merge_header #{@merge}: a layout without rows" if rows.empty?

    Layout.new(rows: rows.freeze, wrap: layout[:wrap] ? true : false)
  end

  def parse_row(row, members)
    row = {cells: row} if row.is_a?(Array)
    row = row.to_h.transform_keys(&:to_sym)
    entries = Array(row.fetch(:cells)).map { |entry| parse_entry(entry, members) }
    raise ArgumentError, "merge_header #{@merge}: an empty row" if entries.empty?

    justify = (row[:justify] || "start").to_s
    raise ArgumentError, "merge_header #{@merge}: justify #{justify.inspect}" unless JUSTIFIES.include?(justify)

    Row.new(entries: entries.freeze, flow: row[:flow] ? true : false, justify: justify,
      separator: row[:separator]&.to_s)
  end

  def parse_entry(entry, members)
    entry = {key: entry} unless entry.is_a?(Hash)
    entry = entry.transform_keys(&:to_sym)
    key = entry.fetch(:key).to_s
    raise ArgumentError, "merge_header #{@merge}: #{key} is no column of the merge" unless members.include?(key)

    align = entry[:align]&.to_s
    raise ArgumentError, "merge_header #{@merge}: align #{align.inspect}" if align && !ALIGNS.include?(align)

    span = entry[:span]&.to_i
    raise ArgumentError, "merge_header #{@merge}: span #{span}" if span && span < 1

    Entry.new(key: key, align: align, span: span)
  end
end
