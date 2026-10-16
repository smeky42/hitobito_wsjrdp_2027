# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# ONE column of an expandable table, described ONCE per dataset -- see
# Wsjrdp::ExpandableTableColumns for the ordered collection and
# doc/wsjrdp/expandable_table.md for the widget that renders it.
#
# Everything a column IS lives here; only how a cell is RENDERED stays with the
# host (the `cell:` lambda passed to #to_table_column, which needs helper
# context). The three consumers of one description are
#
#   * the table's policy   -- #codec (key => abbr) is the allow-list of the ?c=
#                             and ?s= params, #default_keys the initial columns,
#   * the rows object      -- #sort_expressions is the ORDER BY allow-list,
#   * the widget           -- the Hash #to_table_column builds.
#
#   key             the LONG name used everywhere in code (D2b)
#   abbr            the short wire token (URL / column picker); defaults to key
#   label           the header
#   condensed_label the header of the compact in-detail variant, if it differs
#   numeric         right-align
#   width           fixed CSS width for table-layout: fixed (nil = share the rest)
#   sort            how this column sorts: an SQL expression (String) for a
#                   relation-backed table, a ->(row){ comparable } extractor for
#                   an array-backed one, nil for a column that cannot be sorted
#   sort_first      the direction the first click sorts in: "asc" (default; a
#                   name, a number) or "desc" (an amount, where the largest
#                   matter first)
#   sort_variants   further ways to sort by this column, each with a chip of its
#                   own in the header -- a column showing several measures (IST,
#                   budget, share spent) sorts by each. A list of Hashes
#                   {name:, label:, title:, sort:, first:} (see SortVariant).
#                   A column may have variants and no `sort:` of its own; then
#                   only its chips sort.
#   default         shown before the user picks any columns
#   css_class       per-column class (responsive hiding); usually derived from
#                   the collection's css_prefix
#
# Widths (doc/wsjrdp/expandable_table.md, "Widths"): `width` is the column's
# narrowest width; `target_width` (with `target_grow`), `grow` and the table's
# t.gaps let it widen with the room the table has. `truncate` keeps a cell on
# one line, `sticky` keeps a leading column in view while the table scrolls
# sideways.
class Wsjrdp::ExpandableTableColumn < Data.define(:key, :abbr, :label, :condensed_label,
  :header_label, :header_tooltip, :group, :grow, :target_width, :target_grow, :truncate, :sticky, :tabular_nums,
  :merge, :merge_share, :merge_layouts, :header_align, :numeric, :width, :sort, :sort_first, :sort_variants, :default, :mobile,
  :narrow, :css_class)
  SORT_DIRECTIONS = %w[asc desc].freeze
  # The form `width` and `target_width` take where widths are reckoned with
  # (target_width, sticky): rem, so the widget can add them up.
  REM_WIDTH = /\A\d+(\.\d+)?rem\z/

  # One further way to sort by a column. It is a SORT KEY of its own (in the ?s=
  # param, in the rows' sort allow-list) but never a column: it cannot be shown,
  # hidden or reordered, and it belongs to its column -- a table without the
  # column cannot sort by its variants either.
  #
  #   name   the variant's part of the key: the key is "<column key>__<name>",
  #          the wire token "<column abbr>_<name>"
  #   label  the chip text ("ist")
  #   title  the measure's name in tooltips and the "Sortiert nach" bar ("IST");
  #          defaults to the label
  #   sort   like the column's `sort:`
  #   first  like the column's `sort_first:`; defaults to the column's
  SortVariant = Data.define(:key, :abbr, :column_key, :label, :title, :sort, :first)

  #   header_label  what the header shows instead of the label ("" for a header
  #                 without title, "\n" for a line break); the label stays the
  #                 column's name in the columns menu
  #   header_tooltip the header's tooltip
  #   tabular_nums  digits of one width (CSS font-variant-numeric: tabular-nums,
  #                 the same font), so figures line up digit under digit; on by
  #                 default for a numeric column, `true` for others (a date)
  #   merge         neighbouring shown columns with the same merge key keep a
  #                 header each (sortable, in the columns menu one by one) but
  #                 share ONE cell per row, which the host renders with
  #                 `merged_cell:` of #to_table_column (row, shown keys)
  #   merge_share   a merged column's share of the merged width (the sum of
  #                 the shown merged columns' widths), so their headers spread
  #                 as wanted: 1 (the default) for all splits it evenly
  #   merge_layouts the header layouts of the column's merge
  #                 (Wsjrdp::ExpandableTableHeaderLayout), set by the
  #                 collection's merge_header -- not given to a column
  #   header_align  "start", "center" or "end" for the header; nil keeps the
  #                 default -- in a merged run the headers spread like
  #                 space-between (first at the start, last at the end, the
  #                 others centred), elsewhere the column's own alignment
  #   grow          how much the column widens with a table that has room to
  #                 spare (t.gaps) -- before any gap grows: a weight, 0 (the
  #                 default) for a column that keeps its width; it widens by
  #                 weight * the gaps' grow_max at most, 2 twice as much as 1.
  #                 With a `target_width` it is the widening PAST the target,
  #                 once every column has reached its target
  #   target_width  the width the column widens to FIRST, from `width`, before
  #                 any column widens past its target (`grow`) and before any
  #                 gap grows; rem like `width`, at least as wide
  #   target_grow   how fast the column approaches its target_width compared
  #                 with the other columns that have one: a weight, 1 by
  #                 default (when the target is wider than the width); a column
  #                 that reaches its target stops there and leaves the room to
  #                 the others
  #   truncate      true: the column's cells stay on one line, cut off with
  #                 "…"; a cut-off cell without a tooltip of its own shows its
  #                 full text in one on hover
  #   sticky        true: the column stays in view at the left while the table
  #                 scrolls sideways -- for the LEADING shown columns only (a
  #                 sticky column behind a non-sticky one scrolls); needs a
  #                 width in rem, not with merge, group or mobile: false
  #   group         a heading over the header: neighbouring shown columns of the
  #                 same group share one cell of an extra header row ("Rolle"
  #                 over "WSJ" and "Kontingent")
  #   mobile        false for a column a phone does without: under the md
  #                 breakpoint (768px) its header, cells and footer collapse to
  #                 nothing (the styles' .exp-no-mobile); it stays in the menu
  #   narrow        false for a column the table does without where it would
  #                 otherwise scroll sideways: while its container is narrower
  #                 than the table's narrowest width, the column collapses like
  #                 one with mobile: false (.exp-no-narrow); it stays in the menu
  def initialize(key:, abbr: nil, label: nil, condensed_label: nil, header_label: nil, header_tooltip: nil,
    group: nil, grow: 0, target_width: nil, target_grow: nil, truncate: false, sticky: false,
    tabular_nums: nil, merge: nil, merge_share: 1, merge_layouts: nil, header_align: nil, numeric: false, width: nil, sort: nil,
    sort_first: "asc", sort_variants: [], default: false, mobile: true, narrow: true, css_class: nil)
    key = key.to_s
    target_grow = self.class.validate_target!(key, width, target_width, target_grow)
    self.class.validate_sticky!(key, width, merge, group, mobile && narrow) if sticky
    abbr = (abbr || key).to_s
    sort_first = self.class.validate_direction!(sort_first)
    variants = sort_variants.map do |variant|
      next variant if variant.is_a?(SortVariant)

      variant = variant.to_h.transform_keys(&:to_sym)
      name = variant.fetch(:name).to_s
      SortVariant.new(key: "#{key}__#{name}", abbr: "#{abbr}_#{name}", column_key: key,
        label: variant.fetch(:label, name).to_s, title: (variant[:title] || variant.fetch(:label, name)).to_s,
        sort: variant.fetch(:sort), first: self.class.validate_direction!(variant.fetch(:first, sort_first)))
    end
    super(key: key, abbr: abbr, label: label,
          condensed_label: condensed_label, header_label: header_label, header_tooltip: header_tooltip, group: group,
          grow: grow, target_width: target_width&.to_s, target_grow: target_grow, truncate: truncate ? true : false,
          sticky: sticky ? true : false, tabular_nums: tabular_nums.nil? ? numeric : tabular_nums, merge: merge&.to_s, merge_share: merge_share,
          merge_layouts: merge_layouts, header_align: header_align&.to_s, numeric: numeric, width: width,
          sort: sort, sort_first: sort_first, sort_variants: variants.freeze,
          default: default, mobile: mobile, narrow: narrow, css_class: css_class)
  end

  def self.validate_direction!(dir)
    dir = dir.to_s
    return dir if SORT_DIRECTIONS.include?(dir)

    raise ArgumentError, "sort direction #{dir.inspect} must be one of #{SORT_DIRECTIONS.join(", ")}"
  end

  # The target_grow a column gets: the given one, 1 for a target wider than
  # the width, else 0. Raises for a target the widget cannot reckon with.
  def self.validate_target!(key, width, target_width, target_grow)
    if target_width.nil?
      raise ArgumentError, "column #{key}: target_grow needs a target_width" unless target_grow.nil?

      return 0
    end
    unless width.to_s.match?(REM_WIDTH) && target_width.to_s.match?(REM_WIDTH)
      raise ArgumentError, "column #{key}: width and target_width must be rem (#{width.inspect}, #{target_width.inspect})"
    end
    span = target_width.to_f - width.to_f
    raise ArgumentError, "column #{key}: target_width #{target_width} is narrower than width #{width}" if span.negative?
    return 0 if span.zero? && target_grow.nil?
    raise ArgumentError, "column #{key}: target_grow must be above 0, not #{target_grow.inspect}" unless target_grow.nil? || target_grow.to_f.positive?

    span.zero? ? 0 : (target_grow || 1)
  end

  def self.validate_sticky!(key, width, merge, group, mobile)
    raise ArgumentError, "column #{key}: a sticky column needs a width in rem" unless width.to_s.match?(REM_WIDTH)
    raise ArgumentError, "column #{key}: sticky does not go with merge" if merge.present?
    raise ArgumentError, "column #{key}: sticky does not go with group" if group.present?
    raise ArgumentError, "column #{key}: sticky does not go with mobile: false or narrow: false" if mobile == false
  end

  def sortable? = !sort.nil?

  def default? = !!default

  # The column config Hash of shared/wsjrdp/_expandable_table. `sort_key:` is the
  # column's own key whenever it declares a sort -- that is what makes the header
  # clickable and what the state resolves a click back into. `sort_variants:`
  # are the header's chips, [{key:, label:, title:, first:}].
  def to_table_column(cell:, merged_cell: nil)
    {key: key, abbr: abbr, label: label, condensed_label: condensed_label,
     header_label: header_label, header_tooltip: header_tooltip, group: group, grow: grow,
     target_width: target_width, target_grow: target_grow, truncate: truncate, sticky: sticky,
     tabular_nums: tabular_nums, merge: merge, merge_share: merge_share, merge_layouts: merge_layouts,
     header_align: header_align,
     merged_cell: merged_cell,
     numeric: numeric, width: width, mobile: mobile, narrow: narrow, css_class: css_class,
     sort_key: (key if sortable?), sort_first: sort_first,
     sort_variants: sort_variants.map { |v| {key: v.key, label: v.label, title: v.title, first: v.first} },
     cell: cell}
  end
end
