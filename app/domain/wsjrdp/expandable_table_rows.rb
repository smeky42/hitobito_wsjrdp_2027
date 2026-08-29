# frozen_string_literal: true

#  Copyright (c) 2026 German Contingent for the World Scout Jamboree 2027.
#
#  This file is part of hitobito_wsjrdp_2027 and licensed under the
#  Affero General Public License version 3 or later. See the COPYING
#  file at the top-level directory or at
#  https://github.com/smeky42/hitobito_wsjrdp_2027

# THE rows of one expandable table: an already filtered/scoped source, ordered by
# the table's resolved Wsjrdp::TableState and cut to the current page. One object
# for every table of the app -- relation-backed (the DATEV bookings, the Moss
# transactions, the reconciliation entries) and array-backed (the Buchhaltung
# summaries) alike.
#
#   Wsjrdp::ExpandableTableRows.new(booking_table_state,
#     booking_table_state.filter.scope(DatevBooking.all),
#     sort: Fin::DatevBookingsColumns.sort_expressions,
#     sum: :signed_base_amount, preload: :batch)
#
# The order comes from the STATE and never from params (D8.3 of
# doc/plans/2026-09_expandable-table-state.md): a hand-edited URL changes neither
# the rows nor their order beyond what the controller's policy allows. Filtering
# is not this object's job either -- the caller hands in the already filtered
# scope (Wsjrdp::TableState::Filter#scope compiles it).
#
#   state         the table's resolved Wsjrdp::TableState
#   source        an ActiveRecord relation OR an Array of row Hashes
#   sort:         column key => SQL expression (relation) or ->(row){ comparable }
#                 (Array). THE allow-list: a sort the state resolved but this map
#                 does not know is dropped, so only fixed, safe expressions reach
#                 ORDER BY. Normally a column collection's #sort_expressions.
#   sum:          the column #total_sum aggregates over the WHOLE source; nil = none
#   preload:      associations preloaded on the rendered page (relation only)
#   tiebreaker:   the last ORDER BY level, so equal rows keep a deterministic
#                 order: an ORDER BY fragment for a relation (":id" => "id ASC",
#                 "accounting_entries.id DESC" verbatim), a ->(row){ comparable }
#                 for an Array, where it is required
#   natural_order: ->(source){ ordered source }, used when NOTHING is sorted -- an
#                 order no column sort can express (the reconciliation entries put
#                 their match proposals first). Without one, a relation falls back
#                 to the tiebreaker and an Array keeps the order it arrived in:
#                 an array comes pre-ordered from its own query, and re-sorting it
#                 in Ruby would apply a different collation than that query did.
class Wsjrdp::ExpandableTableRows
  attr_reader :state

  def initialize(state, source, sort:, sum: nil, preload: [], tiebreaker: :id, natural_order: nil)
    @state = state
    @source = source
    @sort = sort
    @sum = sum
    @preload = preload
    @tiebreaker = tiebreaker
    @natural_order = natural_order
    return unless array? && !@tiebreaker.is_a?(Proc)

    raise ArgumentError, "an array-backed table needs a ->(row){ comparable } tiebreaker"
  end

  # The current page: sorted, then cut by the state (D4's page clamp and the
  # "Alle" page size both live in Wsjrdp::TableState#paginate).
  def page
    @page ||= @state.paginate(with_preload(ordered))
  end

  # Sorted, limited to `count` rows and NOT paged -- for an inline preview inside
  # another table's detail row. Nothing calls it today; it is the replacement for
  # the query objects' #limited.
  def limit(count)
    with_preload(ordered).limit(count)
  end

  # Over the whole source, not just the current page.
  def total_count
    @total_count ||= page.total_count
  end

  # Sum of `sum:` over the whole source, nil when the table declares none. The
  # summed columns carry a baked sign (doc/fin/money_conventions.md), so a plain
  # SUM is correct.
  def total_sum
    return nil unless @sum

    @total_sum ||= array? ? @source.sum { |row| row[@sum] } : @source.sum(@sum)
  end

  # The active multi-column sort as [[column_key, dir], ...] (primary first),
  # from the resolved state and restricted to the `sort:` allow-list (the state's
  # own column codec already dropped anything that is not a column of this table).
  def sort_list
    @sort_list ||= @state.sort_list.select { |key, _dir| @sort.key?(key) }
  end

  private

  def array? = @source.is_a?(Array)

  def ordered
    @ordered ||= array? ? ordered_array : ordered_relation
  end

  def with_preload(rows)
    return rows if array? || @preload.blank?

    rows.preload(@preload)
  end

  # Multi-column ORDER BY, NULLS LAST, tiebreaker last. An empty sort (nothing
  # chosen, or the user clicked the last column off) is the natural order.
  def ordered_relation
    return natural_relation if sort_list.empty?

    order = sort_list.map { |key, dir| "#{@sort.fetch(key)} #{direction(dir)} NULLS LAST" }
    order << tiebreaker_sql
    @source.reorder(Arel.sql(order.join(", ")))
  end

  def natural_relation
    return @natural_order.call(@source) if @natural_order

    @source.reorder(Arel.sql(tiebreaker_sql))
  end

  def direction(dir) = (dir.to_s == "desc") ? "DESC" : "ASC"

  # A tiebreaker that names its own direction is taken verbatim; a bare column
  # sorts ascending.
  def tiebreaker_sql
    @tiebreaker_sql ||= @tiebreaker.to_s.then do |sql|
      /\s(?:asc|desc)\z/i.match?(sql) ? sql : "#{sql} ASC"
    end
  end

  # Stable multi-key sort over the same list, in memory: each level through its
  # extractor, ties broken by the tiebreaker so equal rows stay deterministic
  # (Array#sort is not stable).
  def ordered_array
    return natural_array if sort_list.empty?

    extractors = sort_list.map { |key, dir| [@sort.fetch(key), dir] }
    @source.sort do |a, b|
      cmp = 0
      extractors.each do |extractor, dir|
        c = extractor.call(a) <=> extractor.call(b)
        c = 0 if c.nil?
        c = -c if dir.to_s == "desc"
        (cmp = c).zero? || break
      end
      cmp.zero? ? ((@tiebreaker.call(a) <=> @tiebreaker.call(b)) || 0) : cmp
    end
  end

  def natural_array
    @natural_order ? @natural_order.call(@source) : @source
  end
end
