# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# View helpers for the shared `shared/_expandable_table` widget (see the guide
# in doc/expandable_table.md). Everything a table needs from the request — the
# current page / page size / sort / column selection — is read through ONE
# param namespace so several independent tables can live on the same page:
#
#   * prefix ""    -> params  page / per / sort / sort_dir / cols / filter
#   * prefix "bk"  -> params  bk_page / bk_per / bk_sort / ...
#   * prefix "ae"  -> params  ae_page / ae_per / ae_sort / ...
#
# The SAME prefix is used by the controller (to build the query — e.g.
# DatevBookingsQuery.new(params, prefix:)) and by the view (to render the
# current state and build links), so the two always agree. URL builders keep
# every OTHER param (including sibling tables' params) untouched, which is what
# makes independent paging work.
module ExpandableTableHelper
  ET_HIDDEN_MARKER = "~" # marks a hidden column in the `cols` param (URL-safe)

  # The concrete param name for a logical base within a prefix namespace.
  def et_param_name(prefix, base)
    prefix.to_s.empty? ? base.to_s : "#{prefix}_#{base}"
  end

  # The raw request value of a namespaced param.
  def et_param(prefix, base)
    params[et_param_name(prefix, base)]
  end

  # A URL on the current path with the given namespaced param `changes` applied,
  # every other param preserved. A nil/blank value removes the param. The page
  # param of THIS table is reset unless keep_page: true (a new sort / filter /
  # page size always returns to page 1). Sibling tables' params are untouched.
  def et_url(prefix, changes, keep_page: false)
    qp = request.query_parameters.deep_dup
    changes.each do |base, value|
      name = et_param_name(prefix, base)
      if value.nil? || value.to_s.empty?
        qp.delete(name)
      else
        qp[name] = value
      end
    end
    qp.delete(et_param_name(prefix, :page)) unless keep_page
    return request.path if qp.empty?
    # RelaxedUrlQuery keeps "," and "~" literal (e.g. ?sort=bez,nr~ instead of
    # ?sort=bez%2Cnr%7E) -- see doc/url_encoding.md for the rules and why the
    # encode+relax combination is only safe inside that helper.
    "#{request.path}?#{RelaxedUrlQuery.to_query(qp)}"
  end

  # Hidden fields that re-submit the given query params unchanged through a GET
  # form, mirroring Rack's bracket notation for nesting (a[b]=1, a[]=x). Without
  # the recursion, a nested Hash (e.g. the suppliers grid's show[...] params)
  # would be flattened to its String form and blow up the next request.
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

  # --- column selection (server-side, encoded in <prefix>_cols) --------------

  # Decode a `cols` value into ordered [key, active] pairs, keeping only keys
  # that exist in `all_columns` (each column is a Hash with :key and optional
  # :abbr; the abbr is the compact URL token, defaulting to the key).
  def et_decode_cols(value, all_columns)
    by_token = {}
    all_columns.each do |col|
      key = col[:key].to_s
      by_token[key] = key
      by_token[col[:abbr].to_s] = key if col[:abbr].present?
    end
    tokens = value.is_a?(Array) ? value : value.to_s.split(",")
    tokens.filter_map do |t|
      t = t.to_s.strip
      next if t.blank?
      active = !t.start_with?(ET_HIDDEN_MARKER)
      token = active ? t : t[ET_HIDDEN_MARKER.length..]
      key = by_token[token]
      key ? [key, active] : nil
    end
  end

  # Encode ordered [key, active] pairs to the compact `cols` string, using each
  # column's :abbr (falling back to its key).
  def et_encode_cols(states, all_columns)
    abbr = all_columns.to_h { |c| [c[:key].to_s, (c[:abbr].presence || c[:key]).to_s] }
    states.map { |key, active| "#{active ? "" : ET_HIDDEN_MARKER}#{abbr[key.to_s] || key}" }.join(",")
  end

  # Full ordered column state as [column, active] pairs. Order + visibility come
  # from <prefix>_cols; when absent, the default order with `default_keys` shown
  # (nil => every column shown). Any column missing from the param is appended
  # hidden (forward-compatible with newly added columns).
  def et_column_states(all_columns, prefix, default_keys: nil)
    raw = et_param(prefix, :cols)
    by_key = all_columns.index_by { |c| c[:key].to_s }
    if raw.present?
      decoded = et_decode_cols(raw, all_columns)
      ordered = decoded.filter_map { |key, active| [by_key[key], active] if by_key[key] }
      seen = ordered.map { |c, _| c[:key].to_s }.to_set
      ordered + all_columns.reject { |c| seen.include?(c[:key].to_s) }.map { |c| [c, false] }
    else
      all_columns.map { |c| [c, default_keys.nil? || default_keys.map(&:to_s).include?(c[:key].to_s)] }
    end
  end

  # The visible columns, in order.
  def et_visible_columns(all_columns, prefix, default_keys: nil)
    et_column_states(all_columns, prefix, default_keys: default_keys).filter_map { |c, active| c if active }
  end

  # --- per-page --------------------------------------------------------------

  # Current page size for a table: the <prefix>_per param, or default_per.
  # "all" lifts the limit. Clamped to max.
  def et_per_page(prefix, default_per, max: 500, all_value: 1_000_000)
    raw = et_param(prefix, :per).to_s
    return all_value if raw == "all"
    per = raw.to_i
    per = default_per if per <= 0
    [per, max].min
  end

  def et_per_value(prefix, default_per, max: 500)
    raw = et_param(prefix, :per).to_s
    return "all" if raw == "all"
    per = raw.to_i
    per = default_per if per <= 0
    [per, max].min.to_s
  end

  # --- sort state ------------------------------------------------------------

  # The active sort key: <prefix>_sort, or the default. Returns nil when no sort
  # is defined at all.
  def et_sort_key(prefix, default_key: nil)
    et_param(prefix, :sort).presence || default_key
  end

  # The active sort direction: <prefix>_sort_dir, or the default direction when
  # the active column IS the default column, else "asc".
  def et_sort_dir(prefix, default_key: nil, default_dir: "asc")
    raw = et_param(prefix, :sort_dir).to_s
    return raw if %w[asc desc].include?(raw)
    (et_sort_key(prefix, default_key: default_key).to_s == default_key.to_s) ? default_dir : "asc"
  end

  # --- multi-column sort (single <prefix>_sort param, RISON) ------------------
  #
  # The newer multi-column mode: the whole sort (several columns + per-column
  # direction, in priority order) lives in ONE param, RISON-encoded by
  # ExpandableTableSort. Opt in per table with `multi_sort: true`; the controller
  # / query reads the same param via ExpandableTableSort.decode.

  # The active sort as [[symbol, dir], ...] (primary first), from <prefix>_sort.
  def et_sort_list(prefix)
    ExpandableTableSort.decode(et_param(prefix, :sort).to_s)
  end

  # The URL after clicking `token`'s header: the clicked column becomes primary
  # and its direction advances asc -> desc -> removed. `list` is the already
  # decoded current sort (avoids re-parsing per column). A resulting empty sort
  # drops the param (natural order).
  def et_sort_toggle_url(prefix, token, list)
    et_url(prefix, {sort: ExpandableTableSort.encode(ExpandableTableSort.after_click(list, token))})
  end

  # [dir, rank] for a token in the current sort list, or [nil, nil] if unsorted.
  def et_sort_state(list, token)
    ExpandableTableSort.state(list, token)
  end
end
