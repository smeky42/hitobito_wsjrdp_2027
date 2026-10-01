# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Multi-column sort state for shared/wsjrdp/_expandable_table, encoded as ONE URL param
# (<prefix>_sort) using A-Rison -- a RISON array WITHOUT the "!(...)" wrapper, so
# it is just a comma-separated list of short column symbols:
#
#   bez,nr~      ==  [["bez", "asc"], ["nr", "desc"]]
#                    (first = primary sort; a trailing "~" means descending)
#
# The symbols are the columns' `abbr` tokens; they are chosen so RISON never has
# to quote them -- a bare RISON id must not contain any of ' ! : ( ) , * @ $ or
# whitespace and must not start with "-" or a digit. "~" is a safe idchar (and
# URL-unreserved), which is exactly why it -- not "-" -- marks descending. The
# comma too is a legal query sub-delim (see Wsjrdp::ExpandableTableHelper#et_url, which
# keeps it literal), so a whole sort reads cleanly in the URL: ?sort=bez,nr~.
# decode also accepts the full "!(...)" form, so old links keep working.
#
# This module is PURE value logic (no params / request / DB): the view helper
# (Wsjrdp::ExpandableTableHelper) uses it to read the param and build the header links,
# and the controllers / Wsjrdp::ExpandableTableRows use it to turn the same param into an
# ORDER BY. See doc/wsjrdp/expandable_table.md.
module Wsjrdp::ExpandableTableSort
  DESC_SUFFIX = "~"

  module_function

  # A-Rison (or full RISON) string -> [[symbol, "asc"|"desc"], ...]. Tolerant:
  # accepts the bare "bez,nr~" form AND the wrapped "!(bez,nr~)" form; anything
  # else / empty yields [] (the caller falls back to its natural / default
  # order). Order is preserved; duplicate columns are dropped (first wins).
  def decode(value)
    s = value.to_s.strip
    return [] if s.empty?
    s = s[2..-2] if s.start_with?("!(") && s.end_with?(")") # tolerate wrapped RISON
    return [] if s.empty?

    seen = {}
    s.split(",").filter_map do |raw|
      tok = raw.strip
      next if tok.empty?
      desc = tok.end_with?(DESC_SUFFIX)
      sym = desc ? tok[0...-DESC_SUFFIX.length] : tok
      next if sym.empty? || seen[sym] # ignore empties and duplicate columns
      seen[sym] = true
      [sym, desc ? "desc" : "asc"]
    end
  end

  # [[symbol, dir], ...] -> A-Rison "bez,nr~" (no wrapper); blank list -> nil
  # (drop the param).
  def encode(list)
    return nil if list.blank?

    list.map { |sym, dir| (dir.to_s == "desc") ? "#{sym}#{DESC_SUFFIX}" : sym.to_s }.join(",")
  end

  # The direction a sort key takes after one more click: a key cycles through
  # its first direction, the opposite one and "not sorted" (nil). A name or a
  # number starts ascending, an amount usually descending (the column's
  # `sort_first:`).
  #   next_dir(nil, "asc")    => "asc"
  #   next_dir("asc", "asc")  => "desc"
  #   next_dir("desc", "asc") => nil
  #   next_dir(nil, "desc")   => "desc"
  def next_dir(current, first = "asc")
    first = first.to_s
    cycle = [first, opposite(first), nil]
    cycle[(cycle.index(current&.to_s) + 1) % cycle.size]
  end

  def opposite(dir) = (dir.to_s == "desc") ? "asc" : "desc"

  # The direction of a key in the list, or nil.
  def dir_of(list, token)
    token = token.to_s
    list.find { |sym, _| sym == token }&.last
  end

  # A plain click: the clicked key becomes the ONLY sort, its direction one step
  # further along its cycle (from wherever it stood in the list); a step to "not
  # sorted" clears the whole sort.
  #   after_click([], "bez")                          => [["bez","asc"]]
  #   after_click([["bez","asc"]], "bez")             => [["bez","desc"]]
  #   after_click([["bez","desc"]], "bez")            => []
  #   after_click([["nr","asc"],["bez","asc"]], "bez") => [["bez","desc"]]
  def after_click(list, token, first: "asc")
    token = token.to_s
    dir = next_dir(dir_of(list, token), first)
    dir ? [[token, dir]] : []
  end

  # A shift-click: a key already in the list steps along its cycle IN PLACE (and
  # leaves the list at "not sorted"); a new key is appended as the last level.
  # Keys of one SLOT -- the sort variants of one column ("ist", "soll", "%") --
  # share one level: a variant clicked while another variant of its column
  # sorts takes over that level at its first direction. `slot:` maps a key to
  # its slot (default: every key is a slot of its own).
  #   after_shift_click([["nr","asc"]], "bez")             => [["nr","asc"],["bez","asc"]]
  #   after_shift_click([["nr","asc"],["bez","asc"]], "nr") => [["nr","desc"],["bez","asc"]]
  def after_shift_click(list, token, first: "asc", slot: ->(key) { key })
    token = token.to_s
    at = list.index { |sym, _| slot.call(sym) == slot.call(token) }
    return list + [[token, next_dir(nil, first)]] if at.nil?

    dir = (list[at][0] == token) ? next_dir(list[at][1], first) : next_dir(nil, first)
    return list.reject.with_index { |_, i| i == at } if dir.nil?

    list.each_with_index.map { |level, i| (i == at) ? [token, dir] : level }
  end

  # The list without its level at `index` (the "x" of the "Sortiert nach" bar,
  # the shift-click on a rank box).
  def without(list, index) = list.reject.with_index { |_, i| i == index }

  # Only the level at `index` (the bar's "nur diese").
  def only(list, index) = list[index] ? [list[index]] : list

  # The level at `from` moved to position `to` (the bar's "‹" / "›").
  def move(list, from, to)
    return list unless list[from] && to.between?(0, list.size - 1)

    rest = without(list, from)
    rest.insert(to, list[from])
  end

  # [dir, rank] (1-based priority) for a token in the list, or [nil, nil] if the
  # column is not part of the current sort.
  def state(list, token)
    token = token.to_s
    idx = list.index { |sym, _| sym == token }
    idx ? [list[idx][1], idx + 1] : [nil, nil]
  end
end
