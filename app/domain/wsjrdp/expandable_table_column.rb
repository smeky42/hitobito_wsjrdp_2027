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
#   default         shown before the user picks any columns
#   css_class       per-column class (responsive hiding); usually derived from
#                   the collection's css_prefix
class Wsjrdp::ExpandableTableColumn < Data.define(:key, :abbr, :label, :condensed_label,
  :numeric, :width, :sort, :default, :css_class)
  def initialize(key:, abbr: nil, label: nil, condensed_label: nil, numeric: false,
    width: nil, sort: nil, default: false, css_class: nil)
    super(key: key.to_s, abbr: (abbr || key).to_s, label: label,
          condensed_label: condensed_label, numeric: numeric, width: width,
          sort: sort, default: default, css_class: css_class)
  end

  def sortable? = !sort.nil?

  def default? = !!default

  # The column config Hash of shared/wsjrdp/_expandable_table. `sort_key:` is the
  # column's own key whenever it declares a sort -- that is what makes the header
  # clickable and what the state resolves a click back into.
  def to_table_column(cell:)
    {key: key, abbr: abbr, label: label, condensed_label: condensed_label,
     numeric: numeric, width: width, css_class: css_class,
     sort_key: (key if sortable?), cell: cell}
  end
end
