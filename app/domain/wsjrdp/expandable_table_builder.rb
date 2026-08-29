# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Block-based builder for the shared expandable table widget
# (shared/wsjrdp/_expandable_table). Collects settings via named methods and
# produces the locals hash the partial expects, so callers don't have to
# assemble ~25 keyword arguments by hand.
#
#   = wsjrdp_expandable_table do |t|
#     t.rows    transactions, id: "mtx"     # a Wsjrdp::ExpandableTableRows of the host
#     t.columns moss_transaction_table_columns, menu: true
#     t.row_key { |tx| tx.id }
#     t.detail_page { |tx| moss_transaction_path(tx) }
#     t.detail  { |tx, ctx| render ... }
#     t.sort    multi: true
#     t.paging                                    # or per_options: [10, 25, :all]
#     t.filter  filter_cfg
#     t.summary "42 Transaktionen"
#   end
#
# A table is named ONCE, by `t.rows`: the host's Wsjrdp::ExpandableTableRows
# carries both halves the widget needs -- the resolved Wsjrdp::TableState (the
# param namespace, the sort, the visible columns, the page size, the page, the
# open rows, the filter and the nesting level, all with their defaults from the
# controller's policy) and the current page of rows. `t.state` / `t.data` stay
# for the rare table that has no rows object.
# See doc/plans/2026-09_expandable-table-state.md.
#
class Wsjrdp::ExpandableTableBuilder
  # The page-size steps of `t.paging` when a host names none. `:all` is the
  # symbol the state resolves to (wire form "all", labelled "Alle").
  DEFAULT_PER_OPTIONS = [25, 50, 100, 200, 500, :all].freeze

  def initialize
    @locals = {}
  end

  # THE table: a Wsjrdp::ExpandableTableRows, which brings its own state and its
  # own current page. Equivalent to `t.state rows.state, id: id` + `t.data
  # rows.page`, so a view names its table exactly once. `id:` overrides the DOM
  # id prefix (default: the state's prefix).
  def rows(value, id: nil)
    state(value.state, id: id)
    data(value.page)
  end

  # The resolved Wsjrdp::TableState of this table (required unless `t.rows` set
  # it). Two tables on one page use states with different prefixes, so they
  # page/sort/filter independently. `id:` overrides the DOM id prefix (default:
  # the prefix).
  def state(value, id: nil)
    @locals[:state] = value
    @locals[:id_prefix] = id || value.prefix.presence
  end

  # The row collection and (optionally separate) pagination object.
  # When pagination is the same object as rows (the common case), pass only rows.
  def data(rows, pagination: rows)
    @locals[:rows] = rows
    @locals[:pagination] = pagination
  end

  # Column definitions. +cols+ is the FULL set of column hashes the partial
  # expects; which of them are visible, and in which order, comes from the state.
  #   menu:  show the column hamburger (default false)
  #   extra: host-injected columns outside the picker (e.g. a proposal column)
  def columns(cols, menu: false, extra: nil)
    @locals[:columns] = cols
    @locals[:columns_menu] = menu
    @locals[:extra_columns] = extra if extra
  end

  # Unique key per row (for DOM ids, open-state and selection).
  def row_key(&block)
    @locals[:row_key] = block
  end

  # The PRIMARY double link of the detail's header line: "Detailseite", the
  # row's own page. The block returns the path; a blank one renders no link for
  # that row. Declaring it (or a #detail_link) makes the table expandable even
  # without a detail -- the detail row then holds the header line alone.
  def detail_page(&block)
    @locals[:detail_page] = block
  end

  # An ADDITIONAL double link in the detail's header line, left of the primary
  # one and in declaration order (callable several times). The block returns the
  # URL, or nil for a row that has no such target (no group is rendered then).
  #   label:          the left part's text
  #   icon:           its FontAwesome 5 name WITHOUT the "fa-" prefix
  #   title:          tooltip/aria-label of the left (same tab) part
  #   title_new_tab:  tooltip/aria-label of the right (new tab) part
  def detail_link(label:, icon:, title:, title_new_tab:, &block)
    (@locals[:detail_links] ||= []) <<
      {label: label, icon: icon, title: title, title_new_tab: title_new_tab, url: block}
  end

  # Server-rendered inline detail. The block receives (row) or (row, table_context).
  def detail(&block)
    @locals[:detail] = block
  end

  # Lazy-loaded detail via turbo frame. The block returns a URL.
  def detail_src(&block)
    @locals[:detail_src] = block
  end

  # Content injected at the top of each detail.
  def detail_top(&block)
    @locals[:detail_top] = block
  end

  # Content injected at the bottom of each detail.
  def detail_extra(&block)
    @locals[:detail_extra] = block
  end

  # Sort DISPLAY mode. The sort itself -- and its default -- lives in the state.
  #   multi: multi-column sort (default true); false keeps at most one key
  def sort(multi: true)
    @locals[:multi_sort] = multi
  end

  # Turns paging on: page links above and below the table, and the "pro Seite"
  # select (unless the controller fixed the page size). The current page and page
  # size come from the state, their defaults from the policy -- a bare `t.paging`
  # is therefore the normal call.
  #   per_options: the select's choices, `:all` being "Alle" (default: the list
  #                below; pass one only when this table wants other steps)
  def paging(per_options: DEFAULT_PER_OPTIONS)
    @locals[:per_options] = per_options
  end

  # CNF filter configuration: the DISPLAY options of the builder (`apply_url:`,
  # `condensed_locked:`, `disabled:`) plus `presets:` -- this table's
  # quick-select filter presets when the VIEW declares them rather than the
  # controller's policy. Takes a Hash (what the bookings adapter passes through)
  # or keywords:
  #
  #   t.filter apply_url: apply_personal_accounts_path,
  #     presets: [{key: "with_bookings", label: "Nur mit Buchungen",
  #                slots: [[["booking_count", "gt", 0]]]}]
  #
  # A preset may also carry icon: (a FontAwesome 5 name WITHOUT the "fa-"
  # prefix) and css_class: (added verbatim to its toggle link); both are display
  # only and default to nil.
  #
  # Declaring presets HERE and in the policy is a host error and raises in
  # #to_locals -- there is one place per table, never two.
  def filter(config = nil, **options)
    @locals[:filter] = options.any? ? (config || {}).merge(options) : config
  end

  # Summary line shown above the table (e.g. "42 Buchungen · Summe: 1.234 €").
  def summary(text)
    @locals[:summary] = text
  end

  # Row selection configuration hash (name, id_field, form, …).
  def selection(config)
    @locals[:selection] = config
  end

  # Compact in-detail rendering mode.
  def condensed(value = true)
    @locals[:condensed] = value
  end

  # Per-row CSS class lambda.
  def row_class(&block)
    @locals[:row_class] = block
  end

  # --- sub-rows: a row that brings rows of its own ---------------------------
  #
  # The block returns the sub-rows of one row (nil or an empty list: none).
  # They are rendered right after the row, inside the same
  # <tbody class="exp-group">, with the table's VISIBLE columns -- so a column
  # hidden through the menu is hidden in every row of the group. Sorting,
  # paging, the filter, the selection, the open-rows param and the summary
  # count the PARENT rows only; nothing about a sub-row reaches
  # Wsjrdp::ExpandableTableRows or the state.
  def sub_rows(&block)
    @locals[:sub_rows] = block
  end

  # The HTML of ONE sub-row cell. The block gets the sub-row and the column
  # description the head cells get (a Hash with :key, :numeric, :css_class, …),
  # so the same sub-row renders differently per column. Required as soon as
  # #sub_rows is declared.
  def sub_cell(&block)
    @locals[:sub_cell] = block
  end

  # Per-sub-row CSS class lambda (the sub-row's own <tr>).
  def sub_row_class(&block)
    @locals[:sub_row_class] = block
  end

  # Per-group CSS class lambda: the class of the <tbody class="exp-group"> that
  # holds a row, its sub-rows and its detail row. The block gets the PARENT row.
  def group_class(&block)
    @locals[:group_class] = block
  end

  # The assembled locals hash for the partial.
  def to_locals
    validate_filter_presets!
    validate_sub_rows!
    @locals
  end

  private

  # A table's filter presets are declared in ONE place: the controller's policy
  # (`filter: {..., presets: [...]}`) or the view (`t.filter presets: [...]`).
  # Both at once is ambiguous -- which list is "the" Schnellauswahl? -- so it
  # fails loudly here, where the two sources meet.
  def validate_filter_presets!
    view_presets = @locals[:filter].is_a?(Hash) ? @locals[:filter][:presets] : nil
    state = @locals[:state]
    return if view_presets.blank? || state.nil? || state.filter.presets.empty?

    raise ArgumentError, "table #{state.store_key.inspect} (prefix #{state.prefix.inspect}) " \
                         "declares filter presets in its policy AND in the view -- declare them once"
  end

  # Sub-rows are rendered cell by cell, so the two halves belong together: the
  # widget could not put a sub-row into the table's columns without #sub_cell.
  # It fails here rather than at the first row that brings one.
  def validate_sub_rows!
    return if @locals[:sub_rows].nil? || @locals[:sub_cell]

    raise ArgumentError, "expandable_table declares sub_rows but no sub_cell -- " \
                         "a sub-row's cells are rendered by sub_cell(sub, col)"
  end
end
