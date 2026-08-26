# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# Multi-column sort state for shared/_expandable_table, encoded as ONE URL param
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
# comma too is a legal query sub-delim (see ExpandableTableHelper#et_url, which
# keeps it literal), so a whole sort reads cleanly in the URL: ?sort=bez,nr~.
# decode also accepts the full "!(...)" form, so old links keep working.
#
# This module is PURE value logic (no params / request / DB): the view helper
# (ExpandableTableHelper) uses it to read the param and build the header links,
# and the controllers / DatevBookingsQuery use it to turn the same param into an
# ORDER BY. See doc/expandable_table.md.
module ExpandableTableSort
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

  # Apply one header click to the current list. The clicked column becomes the
  # PRIMARY sort and its direction advances: not-sorted -> asc -> desc -> removed.
  #   after_click([], "bez")                          => [["bez","asc"]]
  #   after_click([["bez","asc"]], "bez")             => [["bez","desc"]]
  #   after_click([["bez","desc"]], "bez")            => []
  #   after_click([["bez","asc"]], "nr")              => [["nr","asc"],["bez","asc"]]
  #   after_click([["nr","asc"],["bez","asc"]],"bez") => [["bez","desc"],["nr","asc"]]
  def after_click(list, token)
    token = token.to_s
    idx = list.index { |sym, _| sym == token }
    return [[token, "asc"]] + list if idx.nil?

    dir = list[idx][1].to_s
    rest = list.reject.with_index { |_, i| i == idx }
    (dir == "asc") ? [[token, "desc"]] + rest : rest
  end

  # [dir, rank] (1-based priority) for a token in the list, or [nil, nil] if the
  # column is not part of the current sort.
  def state(list, token)
    token = token.to_s
    idx = list.index { |sym, _| sym == token }
    idx ? [list[idx][1], idx + 1] : [nil, nil]
  end
end
