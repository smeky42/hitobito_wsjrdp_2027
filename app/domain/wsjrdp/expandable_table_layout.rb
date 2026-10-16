# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The widths of an expandable table (shared/wsjrdp/_expandable_table) whose
# columns have a `target_width`, and the offsets of its sticky columns -- see
# doc/wsjrdp/expandable_table.md, "Widths". A table without any target_width
# keeps the widget's own reckoning and never gets here.
#
# The room R a table has beyond the sum of its widths (100cqw minus that sum)
# is spent in three phases, all in CSS against the size container around the
# table, whole pixels (round down):
#
# 1. The columns with a target_width widen towards it, each by its
#    target_grow per unit of the level c1 (--exp-c1). A column at its target
#    stops; the others go on faster -- the level is the water level of the
#    spans (target_width - width) weighed by target_grow:
#
#      c1 = clamp(0, max_k((R - S_k) / F_k), max_i span_i / tg_i)
#
#    with the target columns in the order of span / tg, S_k the spans of the
#    first k of them (those already at their target) and F_k the weights of
#    the rest. The max of these lines is the level: it is the line of the
#    columns still widening and above all the others.
# 2. Once every target is reached, the columns with `grow` widen further, by
#    their weight per unit of c2 (--exp-c2), up to the gaps' grow_max per
#    unit (unbounded without t.gaps, as for a table without targets).
# 3. The rest goes to the gaps (--exp-g), up to their max; then the table
#    stops widening.
#
# A column is `width + min(tg * c1, span) [+ grow * c2] [+ g]` wide.
class Wsjrdp::ExpandableTableLayout
  PX_PER_REM = 16

  # Whether a column (the widget's Hash) widens towards a target.
  def self.target_column?(col)
    col[:target_width].present? && col[:width].present? &&
      col[:target_width].to_f > col[:width].to_f && target_grow_of(col).positive?
  end

  def self.target_grow_of(col) = (col[:target_grow] || 1).to_f

  # The left offsets of the sticky columns: the leading run of shown columns
  # with `sticky` (and a rem width, no merge, no group, shown on a phone) --
  # key => CSS length, each the sum of the widths before it, the selection
  # column's 2rem included. Empty without sticky columns at the start.
  def self.sticky_lefts(columns, col_width, selection: false)
    lead = columns.take_while do |col|
      col[:sticky] && col[:width].to_s.match?(Wsjrdp::ExpandableTableColumn::REM_WIDTH) &&
        col[:merge].blank? && col[:group].blank? && col[:mobile] != false
    end
    offsets = selection ? ["2rem"] : []
    lead.each_with_object({}) do |col, lefts|
      lefts[col[:key]] = offsets.empty? ? "0px" : "calc(#{offsets.join(" + ")})"
      offsets << col_width.call(col)
    end
  end

  # The styles of a table narrower than its narrowest width, where it would
  # scroll sideways: a container query on its wrapper (container-name
  # exp-<id_prefix>) that collapses the columns with `narrow: false` (their
  # widths, --exp-nn, leave the narrowest width) and shows what only a narrow
  # table shows (detail_page narrow_only: .exp-narrow-only, and a page link
  # among others, .exp-narrow-only-group). The narrowest width is min_rem,
  # on a phone (below the md breakpoint) without the mobile: false columns
  # (mobile_rem); the collapsing columns' widths there are narrow_phone_rem,
  # the mobile: false ones being gone already. Selectors through the table's
  # own children, so a table nested in a detail is not touched.
  def self.narrow_css(id_prefix, min_rem:, mobile_rem:, narrow_rem:, narrow_phone_rem:)
    table = "[data-exptbl=\"#{id_prefix}\"] > table"
    detail = "#{table} > tbody > tr > td > .exp-detail"
    rules = ->(collapsed) {
      "#{table} { --exp-nn: #{num_s(collapsed)}rem; } " \
        "#{table} > colgroup > col.exp-no-narrow { width: 0 !important; } " \
        "#{table} > * > tr > .exp-no-narrow { width: 0 !important; padding: 0 !important; font-size: 0; " \
        "line-height: 0; overflow: hidden; } " \
        "#{table} > * > tr > .exp-no-narrow > * { display: none; } " \
        "#{detail} > .exp-narrow-only, #{detail} > .booking-detail > .exp-narrow-only { display: block !important; } " \
        "#{detail} > .booking-detail > .exp-detail-links > .exp-narrow-only-group { display: inline-flex !important; }"
    }
    query = ->(min, collapsed) { "@container exp-#{id_prefix} (width < #{num_s(min)}rem) { #{rules.call(collapsed)} }" }
    return query.call(min_rem, narrow_rem) unless mobile_rem.positive?

    "@media (min-width: 768px) { #{query.call(min_rem, narrow_rem)} } " \
      "@media (max-width: 767.98px) { #{query.call(min_rem - mobile_rem, narrow_phone_rem)} }"
  end

  def self.num_s(value)
    rounded = value.to_f.round(4)
    (rounded == rounded.to_i) ? rounded.to_i.to_s : rounded.to_s
  end
  private_class_method :num_s

  # columns: the shown columns (the widget's Hashes), min_rem: the sum of
  # their widths (with the selection column's), mobile_rem: the sum of the
  # widths of those with `mobile: false` (a phone leaves them out: the styles
  # set --exp-nm to --exp-nm-w there), narrow_rem: of those with `narrow:
  # false` (a narrow table leaves them out: --exp-nn), gap_keys: the columns with a
  # gap at their right, grow_max / gap_max: the gaps' (CSS lengths).
  def initialize(columns:, min_rem:, gap_keys:, grow_max:, gap_max:, mobile_rem: 0, narrow_rem: 0)
    @columns = columns
    @min_rem = min_rem
    @mobile_rem = mobile_rem
    @narrow_rem = narrow_rem
    @gap_keys = gap_keys
    @grow_max = grow_max
    @gap_max = gap_max
    @targets = columns.select { |col| self.class.target_column?(col) }
      .sort_by { |col| span_of(col) / self.class.target_grow_of(col) }
    @grow_weight = columns.sum { |col| col[:grow].to_f }
    @span_sum = @targets.sum { |col| span_of(col) }
  end

  # The CSS width of a column.
  def col_width(col)
    parts = [col[:width]]
    if self.class.target_column?(col)
      parts << "min(#{num(self.class.target_grow_of(col))} * var(--exp-c1), #{num(span_of(col))}rem)"
    end
    parts << "#{num(col[:grow].to_f)} * var(--exp-c2)" if col[:grow].to_f.positive?
    parts << "var(--exp-g)" if @gap_keys.include?(col[:key])
    (parts.size > 1) ? "calc(#{parts.join(" + ")})" : parts.first
  end

  # The table's style: the three levels, the target columns' sum and the
  # table's width.
  def table_style
    [*(["--exp-nm-w: #{num(@mobile_rem)}rem"] if @mobile_rem.positive?),
      "--exp-c1: #{c1_expression}", "--exp-c2: #{c2_expression}", "--exp-t: #{targets_expression}",
      "--exp-g: #{gap_expression}", "min-width: #{min_expression}",
      "width: calc(#{min_expression} + var(--exp-t) + #{num(@grow_weight)} * var(--exp-c2) + " \
        "#{@gap_keys.size} * var(--exp-g))"].join("; ")
  end

  # The widest the table gets with t.gaps: every target, every column grown
  # by its weight * grow_max, every gap at its max.
  def max_width_style
    "max-width: calc(#{num(@min_rem)}rem + #{num(@span_sum)}rem + #{num(@grow_weight)} * #{@grow_max} + " \
      "#{@gap_keys.size} * #{@gap_max})"
  end

  # The same reckoning in Ruby, in pixels: what each shown column gets on top
  # of its width (key => px) for `room_px` beyond the widths -- the CSS above
  # in another form, for the specs and for reading. grow_max_px nil:
  # unbounded (no t.gaps).
  def extras_at(room_px, grow_max_px:, gap_max_px:)
    c1 = floor_px(level_at(room_px)).clamp(0, max_level_px)
    target_px = @targets.to_h { |col| [col[:key], [self.class.target_grow_of(col) * c1, span_of(col) * PX_PER_REM].min] }
    c2 = @grow_weight.positive? ? [floor_px((room_px - (@span_sum * PX_PER_REM)) / @grow_weight), 0].max : 0
    c2 = [c2, grow_max_px].min if grow_max_px
    gap = @gap_keys.any? ? floor_px((room_px - target_px.values.sum - (@grow_weight * c2)) / @gap_keys.size) : 0
    gap = gap.clamp(0, gap_max_px)
    @columns.to_h do |col|
      [col[:key], target_px.fetch(col[:key], 0) + (col[:grow].to_f * c2) + (@gap_keys.include?(col[:key]) ? gap : 0)]
    end
  end

  private

  def span_of(col) = col[:target_width].to_f - col[:width].to_f

  def room = "(100cqw - #{min_expression})"

  # The narrowest width: the widths' sum, on a phone and in a narrow table
  # without the columns they do without.
  def min_expression
    parts = [("var(--exp-nm, 0rem)" if @mobile_rem.positive?), ("var(--exp-nn, 0rem)" if @narrow_rem.positive?)].compact
    parts.empty? ? "#{num(@min_rem)}rem" : "calc(#{num(@min_rem)}rem - #{parts.join(" - ")})"
  end

  # The level's lines, one per phase of the water level (see above).
  def level_lines
    spent = 0.0
    weights = @targets.sum { |col| self.class.target_grow_of(col) }
    @targets.map do |col|
      line = "(#{room} - #{num(spent)}rem) / #{num(weights)}"
      spent += span_of(col)
      weights -= self.class.target_grow_of(col)
      line
    end
  end

  def max_level_rem = @targets.map { |col| span_of(col) / self.class.target_grow_of(col) }.max

  def c1_expression
    level = (level_lines.size == 1) ? level_lines.first : "max(#{level_lines.join(", ")})"
    "clamp(0px, round(down, #{level}, 1px), #{num(max_level_rem)}rem)"
  end

  def c2_expression
    return "0px" unless @grow_weight.positive?

    "clamp(0px, round(down, (#{room} - #{num(@span_sum)}rem) / #{num(@grow_weight)}, 1px), #{@grow_max})"
  end

  def targets_expression
    parts = @targets.map { |col| "min(#{num(self.class.target_grow_of(col))} * var(--exp-c1), #{num(span_of(col))}rem)" }
    "calc(#{parts.join(" + ")})"
  end

  def gap_expression
    return "0px" if @gap_keys.empty?

    "clamp(0px, round(down, (#{room} - var(--exp-t) - #{num(@grow_weight)} * var(--exp-c2)) / " \
      "#{@gap_keys.size}, 1px), #{@gap_max})"
  end

  # The level of phase 1 in pixels, unrounded.
  def level_at(room_px)
    spent = 0.0
    weights = @targets.sum { |col| self.class.target_grow_of(col) }
    @targets.map do |col|
      line = (room_px - (spent * PX_PER_REM)) / weights
      spent += span_of(col)
      weights -= self.class.target_grow_of(col)
      line
    end.max
  end

  def max_level_px = max_level_rem * PX_PER_REM

  def floor_px(value) = value.floor

  # A number as CSS wants it: no trailing ".0".
  def num(value) = self.class.send(:num_s, value)
end
