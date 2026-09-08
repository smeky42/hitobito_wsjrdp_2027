# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# View helpers for the shared `shared/wsjrdp/_expandable_table` widget (see the guide
# in doc/wsjrdp/expandable_table.md).
#
# Everything a table needs from the request -- the current page / page size /
# sort / column selection / filter / open rows -- is resolved by the CONTROLLER
# into a Wsjrdp::TableState (Wsjrdp::TableStateful) and handed to the widget.
# This helper therefore only READS that state and BUILDS links from it; it never
# looks at params, session or cookies (D8.4 of
# doc/plans/2026-09_expandable-table-state.md, enforced by
# spec/domain/wsjrdp/expandable_table_state_guard_spec.rb).
#
# The one legitimate use of the request here is link construction: `et_url` and
# `et_carry_params` merge request.query_parameters so a link keeps every OTHER
# param (a sibling table's state, a page param of the host, the locale) untouched.
# Those values are only ever passed through -- they are never trusted, and never
# turned into state.
#
# Param names come from the state, one letter per field within the table's
# prefix namespace (D2a):
#
#   * prefix ""    -> params  s / c / f / z / p / o / e
#   * prefix "bk"  -> params  bks / bkc / bkf / bkz / bkp / bko / bke
module Wsjrdp::ExpandableTableHelper
  ET_HIDDEN_MARKER = "~" # marks a hidden column in the `cols` param (URL-safe)

  # Block-based facade for `render "shared/wsjrdp/expandable_table"`. See
  # Wsjrdp::ExpandableTableBuilder for the available methods.
  def wsjrdp_expandable_table
    builder = Wsjrdp::ExpandableTableBuilder.new
    yield builder
    render "shared/wsjrdp/expandable_table", **builder.to_locals
  end

  # --- the lazily loaded row detail ------------------------------------------

  # The DOM id of one row's detail frame. The widget writes it into the frame it
  # renders per row (`t.detail_src`); the detail's own view answers in the frame
  # the REQUEST names (WsjrdpFormHelper#wsjrdp_detail_frame), never in one it
  # builds itself -- the same detail is loaded from tables with different
  # prefixes. This stays the one place that knows the format, for the writing
  # side and for a canonical id.
  def wsjrdp_detail_frame_id(prefix, key) = "bkframe-#{prefix}-#{key}"

  # --- URL building ----------------------------------------------------------
  # THE only methods that touch the request (see the note above).

  # A URL on the current path with this table's `changes` applied (keys are field
  # names -- :sort, :cols, :filter, :per_page, :page, :open), every other param
  # preserved. A nil value removes the param; an empty string sets it explicitly
  # blank, which is how a user CLEARS a remembered field (a blank param beats the
  # store, an absent one does not). This table's page resets unless keep_page: or
  # an explicit :page change. D4: changing the filter, the page or the page size
  # closes every open row, so `o` is dropped there. `extra:` sets raw params
  # outside the table's namespace (the reset marker).
  def et_url(state, changes = {}, keep_page: false, extra: {})
    changes = changes.transform_keys(&:to_sym)
    query = et_carry_params(state)
    changes.each { |field, value| et_apply_change(query, state, field, value) }
    query.delete(state.param_name(:open)) if changes.keys.intersect?(%i[filter page per_page])
    query.delete(state.param_name(:page)) unless keep_page || changes.key?(:page)
    extra.each { |name, value| query[name.to_s] = value.to_s }
    return et_current_path if query.empty?
    # Wsjrdp::RelaxedUrlQuery keeps "," and "~" literal (e.g. ?s=bez,nr~ instead of
    # ?s=bez%2Cnr%7E) -- see doc/wsjrdp/url_encoding.md for the rules and why the
    # encode+relax combination is only safe inside that helper.
    "#{et_current_path}?#{Wsjrdp::RelaxedUrlQuery.to_query(query)}"
  end

  # Clears ONLY the filter of this table -- the filter builder's
  # "Zurücksetzen". Sort, columns, page size, the sibling tables and every
  # non-table param stay untouched; this table's page and open rows go with the
  # filter change (D4).
  #
  # The filter param is emitted PRESENT, not dropped: it carries the policy's
  # `default:` tree in wire form, or is blank (`?f=`) when the table declares no
  # default. A present param is the explicit choice that beats a remembered
  # filter, whereas an absent one would fall through to the store and bring the
  # just-cleared filter straight back (same rule as the column picker's
  # "Standard-Spalten").
  def et_filter_reset_url(state)
    et_url(state, {filter: state.filter.default_wire})
  end

  # The DOM id of this table's filter pane. The pane body (rendered by
  # shared/wsjrdp/filtering/_builder between the filter line and the toolbar)
  # and its toggle button (rendered by shared/wsjrdp/filtering/_line at the
  # right end of that line) meet here: the toggle carries it as
  # data-pane-target, shared/wsjrdp/_collapsible_panes wires them -- and mirrors
  # the pane's open state onto every [data-pane-line="<this id>"] element.
  def et_pane_id(state)
    "#{state.cookie_name(:pane)}_pane"
  end

  # The DOM id of this table's "Schnellauswahl" preset bar. A cross-partial
  # contract like et_pane_id: shared/wsjrdp/filtering/_line RENDERS the bar,
  # while the builder's JS (lockPresets) reaches it by this id -- the bar sits
  # outside .flt-root, so it cannot be found by walking the DOM.
  def et_filter_presets_id(state)
    "#{state.cookie_name(:pane)}_presets"
  end

  # Drops this table's whole state and asks the controller to forget what it
  # remembered (D3): `?<prefix>r=1`. NOTHING IN THE UI CALLS THIS -- there is no
  # table-wide reset button; the filter's "Zurücksetzen" resets only the filter
  # (et_filter_reset_url). The param stays supported (Wsjrdp::TableStateful
  # handles it, `table_state_reset` does it page-wide), and this is the one place
  # that knows how to build such a URL should a host ever want the control.
  def et_reset_url(state)
    et_url(state, Wsjrdp::TableStatePolicy::FIELDS.index_with { nil },
      extra: {state.reset_param => "1"})
  end

  # The current query params, for links and for the hidden fields of a GET form.
  # `except:` takes field names of THIS table.
  def et_carry_params(state, except: [])
    names = Array(except).map { |field| state.param_name(field) }
    request.query_parameters.deep_dup.except(*names)
  end

  # The path a widget form posts / navigates to (never with a query string --
  # the form's own fields carry the params).
  def et_current_path
    request.path
  end

  # Hidden fields that re-submit the given query params unchanged through a GET
  # form, mirroring Rack's bracket notation for nesting (a[b]=1, a[]=x). Without
  # the recursion, a host page param that is a nested Hash (`show[all]=1`) would
  # be flattened to its String form and blow up the next request.
  def et_hidden_params(params, prefix = nil)
    fields = params.map do |key, value|
      name = prefix ? "#{prefix}[#{key}]" : key.to_s
      case value
      when Hash
        et_hidden_params(value, name)
      when Array
        safe_join(value.map { |v| hidden_field_tag("#{name}[]", v, id: nil) })
      else
        hidden_field_tag(name, value, id: nil)
      end
    end
    safe_join(fields)
  end

  # --- column selection ------------------------------------------------------

  # Full ordered column state as [column, active] pairs: order and visibility
  # come from the resolved state, matched to the view's column configs by key.
  # A column the state does not know (not in the policy's column codec) is
  # appended hidden.
  #
  # The view passes the DATASET's full column list; which of those columns this
  # table has, and what it calls them, is the controller's declaration and comes
  # from the state (`cols: {exclude:, labels:}` -> #column_configs). Both readers
  # of this method -- the headers and the column picker -- therefore see the same
  # shaped set, which is also the set the `<prefix>c` param encodes.
  def et_column_states(state, all_columns)
    columns = state.column_configs(all_columns)
    by_key = columns.index_by { |col| col[:key].to_s }
    ordered = state.column_states.filter_map { |key, active| [by_key[key], active] if by_key[key] }
    seen = ordered.map { |col, _| col[:key].to_s }.to_set
    ordered + columns.reject { |col| seen.include?(col[:key].to_s) }.map { |col| [col, false] }
  end

  # The visible columns, in order.
  def et_visible_columns(state, all_columns)
    et_column_states(state, all_columns).filter_map { |col, active| col if active }
  end

  # The `cols` wire value for a [column, active] list (used by the picker form).
  def et_encode_cols(state, states)
    state.encode_column_states(states.map { |col, active| [col[:key], active] })
  end

  # --- sort state (multi-column, in the single <prefix>s param) --------------

  # The active sort as [[column_key, dir], ...], primary first.
  def et_sort_list(state) = state.sort_list

  # The URL after clicking `key`'s header: the clicked column becomes primary and
  # its direction advances asc -> desc -> removed. A resulting empty sort sets the
  # param explicitly blank, so it also clears a remembered sort. When
  # `multi: false`, only the first key is kept.
  def et_sort_toggle_url(state, key, multi: true)
    list = multi ? Wsjrdp::ExpandableTableSort.after_click(state.sort_list, key) :
      Wsjrdp::ExpandableTableSort.after_click_single(state.sort_list, key)
    et_url(state, {sort: state.encode_sort_list(list)})
  end

  # [dir, rank] for a column key in the current sort list, or [nil, nil].
  def et_sort_state(list, key)
    Wsjrdp::ExpandableTableSort.state(list, key)
  end

  private

  def et_apply_change(query, state, field, value)
    name = state.param_name(field)
    value.nil? ? query.delete(name) : query[name] = value.to_s
  end
end
