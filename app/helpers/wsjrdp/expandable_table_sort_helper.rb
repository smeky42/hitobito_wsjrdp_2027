# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# The sort controls of shared/wsjrdp/_expandable_table: the sort links of the
# header (a column's own and its variants' chips), the rank boxes and the
# "Sortiert nach" bar (doc/wsjrdp/expandable_table.md, "Sorting").
#
# Every sort control is a plain link to the URL of a PLAIN click: the clicked
# key alone. The URL of a shift-click (append a level, or step it in place)
# rides along in data-shift-href, which shared/wsjrdp/_expandable_table_js
# follows instead when the shift key is down. The tooltips sit on the arrows
# and say what exactly the next click and the next shift-click do.
module Wsjrdp::ExpandableTableSortHelper
  SORT_DIRECTION_WORDS = {"asc" => "aufsteigend", "desc" => "absteigend"}.freeze
  SORT_ARROWS = {"asc" => "↑", "desc" => "↓"}.freeze
  SORT_ARROW_NONE = "⇅"

  # The URL after a plain click on `key`'s sort arrow: `key` becomes the only
  # sort, its direction one step along its cycle (`first` -> opposite -> off,
  # Wsjrdp::ExpandableTableSort.after_click). A resulting empty sort sets the
  # param explicitly blank, so it also clears a remembered or preselected sort.
  def et_sort_toggle_url(state, key, first: "asc")
    et_sort_url(state, Wsjrdp::ExpandableTableSort.after_click(state.sort_list, key, first: first))
  end

  # The URL after a shift-click on `key`'s sort arrow: appended as the last
  # level, or stepped in place; a variant takes over its column's level
  # (Wsjrdp::ExpandableTableSort.after_shift_click).
  def et_sort_shift_url(state, key, first: "asc")
    list = Wsjrdp::ExpandableTableSort.after_shift_click(state.sort_list, key, first: first,
      slot: ->(sort_key) { state.sort_column_for(sort_key) || sort_key })
    et_sort_url(state, list)
  end

  # The URL with the sort `list` ([[key, dir], ...]); blank when empty.
  def et_sort_url(state, list) = et_url(state, {sort: state.encode_sort_list(list)})

  # sort key => the name tooltips and the bar give it: the column's label (this
  # table's own, if it renames the column), for a variant followed by the
  # variant's title ("2026 IST").
  def et_sort_names(state, all_columns)
    all_columns.each_with_object({}) do |col, names|
      label = state.column_label(col[:key], col[:label]).to_s
      names[col[:sort_key].to_s] = label if col[:sort_key]
      Array(col[:sort_variants]).each { |variant| names[variant[:key].to_s] = "#{label} #{variant[:title]}" }
    end
  end

  # The 0-based level of the sort that sorts by column `column_key` (by itself
  # or by one of its variants), or nil.
  def et_sort_level_of_column(state, column_key)
    state.sort_list.index { |key, _dir| (state.sort_column_for(key) || key) == column_key.to_s }
  end

  # The sort link of one key: `content` (the column label, a chip text) and the
  # arrow, the arrow carrying the tooltip.
  def et_sort_link(state, key, content, first:, names:, multi: true, css_class: nil)
    key = key.to_s
    dir = Wsjrdp::ExpandableTableSort.dir_of(state.sort_list, key)
    data = multi ? {shift_href: et_sort_shift_url(state, key, first: first)} : {}
    link_to et_sort_toggle_url(state, key, first: first),
      class: ["exp-sort text-reset text-decoration-none", ("exp-sort-active" if dir), css_class],
      aria: {sort: (dir ? "#{dir}ending" : nil)}, data: data do
      safe_join([content, et_sort_arrow(dir, title: et_sort_arrow_tip(state, key, first: first, names: names, multi: multi))])
    end
  end

  # The arrow of a sort key: ⇅ while it does not sort, ↑ / ↓ while it does.
  def et_sort_arrow(dir, title: nil)
    content_tag(:span, dir ? SORT_ARROWS.fetch(dir.to_s) : SORT_ARROW_NONE,
      class: ["exp-sort-caret", ("exp-sort-on" if dir)], title: title)
  end

  # What the next click -- and, on a multi-sort table, the next shift-click --
  # on `key`'s arrow does, one line each.
  def et_sort_arrow_tip(state, key, first:, names:, multi: true)
    key = key.to_s
    list = state.sort_list
    nxt = Wsjrdp::ExpandableTableSort.next_dir(Wsjrdp::ExpandableTableSort.dir_of(list, key), first)
    name = "„#{names.fetch(key, key)}“"
    others = list.any? { |other, _dir| other != key }
    click = if nxt
      "Klick: #{"nur noch " if others}#{SORT_DIRECTION_WORDS.fetch(nxt)} nach #{name} sortieren"
    else
      others ? "Klick: alle Sortierungen entfernen" : "Klick: nicht mehr nach #{name} sortieren"
    end
    return click unless multi

    at = list.index { |other, _dir| (state.sort_column_for(other) || other) == (state.sort_column_for(key) || key) }
    # Without any other level, a shift-click does what a click does.
    return click if at.nil? && !others

    shift = if at.nil?
      "Shift-Klick: als #{list.size + 1}. Stufe #{SORT_DIRECTION_WORDS.fetch(nxt)} anfügen"
    elsif list[at][0] != key
      "Shift-Klick: Stufe #{at + 1} durch #{name} #{SORT_DIRECTION_WORDS.fetch(first.to_s)} ersetzen"
    elsif nxt
      "Shift-Klick: Stufe #{at + 1} auf #{SORT_DIRECTION_WORDS.fetch(nxt)} ändern"
    else
      "Shift-Klick: Stufe #{at + 1} entfernen"
    end
    "#{click}\n#{shift}"
  end

  # The rank box of level `index` (0-based): the level's number in a small
  # outlined box, shown while the sort has two levels or more. A shift-click
  # removes the level; a plain click does nothing.
  def et_sort_rank_box(state, index, names:, removable: true)
    key = state.sort_list.dig(index, 0)
    return "".html_safe if key.nil?

    options = {class: "exp-sort-rank", "aria-label": "Sortierstufe #{index + 1}"}
    if removable
      options[:title] = "Shift-Klick: Stufe #{index + 1} (#{names.fetch(key, key)}) entfernen"
      options[:data] = {shift_href: et_sort_url(state, Wsjrdp::ExpandableTableSort.without(state.sort_list, index))}
    end
    content_tag(:span, index + 1, options)
  end
end
