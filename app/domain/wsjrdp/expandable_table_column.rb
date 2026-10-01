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
class Wsjrdp::ExpandableTableColumn < Data.define(:key, :abbr, :label, :condensed_label,
  :numeric, :width, :sort, :sort_first, :sort_variants, :default, :css_class)
  SORT_DIRECTIONS = %w[asc desc].freeze

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

  def initialize(key:, abbr: nil, label: nil, condensed_label: nil, numeric: false,
    width: nil, sort: nil, sort_first: "asc", sort_variants: [], default: false, css_class: nil)
    key = key.to_s
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
          condensed_label: condensed_label, numeric: numeric, width: width,
          sort: sort, sort_first: sort_first, sort_variants: variants.freeze,
          default: default, css_class: css_class)
  end

  def self.validate_direction!(dir)
    dir = dir.to_s
    return dir if SORT_DIRECTIONS.include?(dir)

    raise ArgumentError, "sort direction #{dir.inspect} must be one of #{SORT_DIRECTIONS.join(", ")}"
  end

  def sortable? = !sort.nil?

  def default? = !!default

  # The column config Hash of shared/wsjrdp/_expandable_table. `sort_key:` is the
  # column's own key whenever it declares a sort -- that is what makes the header
  # clickable and what the state resolves a click back into. `sort_variants:`
  # are the header's chips, [{key:, label:, title:, first:}].
  def to_table_column(cell:)
    {key: key, abbr: abbr, label: label, condensed_label: condensed_label,
     numeric: numeric, width: width, css_class: css_class,
     sort_key: (key if sortable?), sort_first: sort_first,
     sort_variants: sort_variants.map { |v| {key: v.key, label: v.label, title: v.title, first: v.first} },
     cell: cell}
  end
end
