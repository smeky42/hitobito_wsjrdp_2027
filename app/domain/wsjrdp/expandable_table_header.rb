# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The header rows of an expandable table (shared/wsjrdp/_expandable_table):
# for each header VARIANT the rows, for each row the cells -- which columns a
# cell covers (colspan), how many rows it spans (rowspan), its alignment and
# whether its text may wrap. doc/wsjrdp/expandable_table.md, "Header layouts".
#
# The shown columns fall into runs: a column group (`group:`), a merged run
# (neighbouring columns with one `merge:`) and a single column. A group is two
# rows, its name over its columns' headers. A merged run with a header layout
# (ExpandableTableColumns::Builder#merge_header) has the rows of its layout;
# one without has its headers side by side in one row. A table has as many
# rows as its deepest run; a shallower run's first row reaches down so that
# its last row is the table's last.
#
# A merged run may have several layouts, from the most compact to the most
# stacked; variant k takes every run's k-th layout (its last when it has
# fewer). The widget renders every variant and its script shows the first
# whose headers fit without wrapping, the last one without the script.
class Wsjrdp::ExpandableTableHeader
  # A cell: kind :column (one column's header), :flow (several columns'
  # headers in one cell, one after the other) or :group (a group's name).
  # columns: the column Hashes it covers, in order (colspan); headers: the
  # columns whose headers it holds -- one for :column, several for :flow,
  # none for :group.
  Cell = Data.define(:kind, :columns, :headers, :rowspan, :align, :wrap, :label, :justify, :separator) do
    def column = headers.first

    def colspan = columns.size

    # The rightmost column it covers (its gap is the cell's).
    def last_key = columns.last[:key]
  end

  DEFAULT_ALIGN = ->(index, count) {
    if index.zero?
      "start"
    else
      ((index == count - 1) ? "end" : "center")
    end
  }

  attr_reader :variants

  # columns: the shown columns (the widget's Hashes, in order); header_align:
  # ->(col) { alignment } for a single column's header.
  def initialize(columns:, header_align:)
    @columns = columns
    @header_align = header_align
    @runs = columns.chunk_while do |a, b|
      (a[:group].present? && a[:group] == b[:group]) || (a[:merge].present? && a[:merge] == b[:merge])
    end.to_a
    count = @runs.map { |run| layouts_of(run).size }.max || 1
    @variants = (0...[count, 1].max).map { |index| rows_of_variant(index) }
  end

  # Whether the header has several variants (the widget then shows one).
  def variants? = @variants.size > 1

  # Whether a variant has more than one row.
  def multi_row?(index = 0) = @variants[index].size > 1

  # Whether any variant has more than one row (the widths then go into a
  # colgroup).
  def any_multi_row? = @variants.any? { |rows| rows.size > 1 }

  private

  def layouts_of(run)
    return [] unless run.size > 1 && run.first[:merge].present?

    Array(run.first[:merge_layouts]&.layouts)
  end

  def rows_of_variant(index)
    blocks = @runs.map { |run| block_of(run, index) }
    # No columns: one empty row (the widget shows a hint instead of a table).
    depth = blocks.map(&:size).max || 1
    rows = Array.new(depth) { [] }
    blocks.each do |block|
      extra = depth - block.size
      block.each_with_index do |cells, row_index|
        cells = cells.map { |cell| cell.with(rowspan: cell.rowspan + extra) } if row_index.zero? && extra.positive?
        rows[row_index.zero? ? 0 : row_index + extra].concat(cells)
      end
    end
    rows
  end

  # The rows of one run in this variant (each an Array of cells).
  def block_of(run, index)
    if run.first[:group].present? && run.all? { |col| col[:group] == run.first[:group] }
      [[cell(:group, run, [], label: run.first[:group])], run.map { |col| single(col) }]
    elsif (layouts = layouts_of(run)).any?
      layout_rows(run, layouts[[index, layouts.size - 1].min])
    else
      [run.map { |col| single(col) }]
    end
  end

  def single(col) = cell(:column, [col], [col], align: @header_align.call(col))

  def cell(kind, columns, headers, align: nil, wrap: false, label: nil, justify: nil, separator: nil)
    Cell.new(kind: kind, columns: columns, headers: headers, rowspan: 1, align: align, wrap: wrap,
      label: label, justify: justify, separator: separator)
  end

  # A layout's rows for the run's shown columns: a row keeps the entries whose
  # column is shown, an empty row is left out. Each entry covers from its own
  # column to the one before the next entry, the first from the run's start,
  # the last to its end (or its own `span`).
  def layout_rows(run, layout)
    position = run.each_with_index.to_h { |col, i| [col[:key], i] }
    layout.rows.filter_map do |row|
      entries = row.entries.select { |entry| position.key?(entry.key) }.sort_by { |entry| position[entry.key] }
      next if entries.empty?

      if row.flow
        headers = entries.map { |entry| run[position[entry.key]] }
        next [cell(:flow, run, headers, wrap: layout.wrap, justify: row.justify, separator: row.separator)]
      end

      entries.each_with_index.map do |entry, i|
        start = i.zero? ? 0 : position[entry.key]
        stop = if entry.span
          position[entry.key] + entry.span - 1
        else
          (i == entries.size - 1) ? run.size - 1 : position[entries[i + 1].key] - 1
        end
        stop = stop.clamp(start, run.size - 1)
        cell(:column, run[start..stop], [run[position[entry.key]]],
          align: entry.align || DEFAULT_ALIGN.call(i, entries.size), wrap: layout.wrap)
      end
    end.presence || [run.map { |col| single(col) }]
  end
end
